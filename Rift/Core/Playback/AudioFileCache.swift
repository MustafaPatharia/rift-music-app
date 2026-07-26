// SPDX-License-Identifier: GPL-3.0-only
//
// AudioFileCache — true-offline layer. Once a YouTube track has streamed, its
// m4a bytes are saved to disk; subsequent plays (offline, or after a relaunch)
// read the local file directly — no network, no yt-dlp, no googlevideo expiry.
//
// Sits UNDER StreamCache: StreamCache remembers the resolved URL (instant load,
// still needs network); this remembers the actual audio (works with no network).

import Foundation

actor AudioFileCache {
    static let shared = AudioFileCache()

    private let dir: URL?
    private var inFlight = Set<String>()
    // ponytail: fixed 2 GB budget, trim oldest on insert. Per-track TTL / pinning
    // for explicit "download for offline" if the library feature ever needs it.
    private let maxBytes: Int64 = 2_000_000_000

    // videoId → real (yt-dlp) duration, persisted next to the audio. Offline replay
    // needs this: AVPlayer mis-reads some YouTube m4a as ~2× length, so we can't
    // trust its duration and search/browse tracks carry no duration of their own.
    private var durations: [String: TimeInterval] = [:]
    private let durationsFile: URL?

    /// EXPLICIT downloads registry. A file on disk is just cache (transient,
    /// auto-expires) — it becomes a "download" ONLY when the user hits Download,
    /// which records its metadata here. Downloaded files are pinned: never
    /// trimmed for size, never TTL-purged.
    struct Meta: Codable, Sendable {
        let title: String
        let artist: String
        let artworkURL: String?
        let downloadedAt: Date?
    }
    private var metas: [String: Meta] = [:]
    private let metasFile: URL?

    /// Non-downloaded cached audio older than this is purged — cache, not library.
    private let cacheTTL: TimeInterval = 6 * 3600

    init() {
        let fm = FileManager.default
        let d = fm.urls(for: .cachesDirectory, in: .userDomainMask).first
            .map { $0.appendingPathComponent("com.mustafapatharia.riftmusicapp/audio", isDirectory: true) }
        dir = d
        durationsFile = d?.appendingPathComponent("durations.json")
        metasFile = d?.appendingPathComponent("tracks.json")
        if let d { try? fm.createDirectory(at: d, withIntermediateDirectories: true) }
        if let f = durationsFile, let data = try? Data(contentsOf: f),
           let map = try? JSONDecoder().decode([String: TimeInterval].self, from: data) {
            durations = map
        }
        if let f = metasFile, let data = try? Data(contentsOf: f),
           let map = try? JSONDecoder().decode([String: Meta].self, from: data) {
            metas = map
        }
        Task { await self.purgeStaleCache() }   // expire old cache on launch
    }

    func meta(for videoId: String) -> Meta? { metas[videoId] }

    /// The user's explicit downloads (metadata recorded AND bytes on disk),
    /// newest download first.
    func downloads() -> [(id: String, meta: Meta)] {
        metas.compactMap { (id, m) in
            localFile(for: id) != nil ? (id, m) : nil
        }
        .sorted { ($0.meta.downloadedAt ?? .distantPast) > ($1.meta.downloadedAt ?? .distantPast) }
    }

    func setMeta(_ m: Meta, for videoId: String) {
        metas[videoId] = m
        guard let f = metasFile, let data = try? JSONEncoder().encode(metas) else { return }
        try? data.write(to: f)
    }

    /// The real duration for a cached track, if we recorded one.
    func duration(for videoId: String) -> TimeInterval? { durations[videoId] }

    private func persistDurations() {
        guard let f = durationsFile, let data = try? JSONEncoder().encode(durations) else { return }
        try? data.write(to: f)
    }

    private func fileURL(_ videoId: String) -> URL? {
        // videoIds are [A-Za-z0-9_-]{11} — safe as a filename, no sanitizing needed.
        dir?.appendingPathComponent(videoId + ".m4a")
    }

    /// The on-disk m4a if we already have it, else nil. Cheap existence check.
    func localFile(for videoId: String) -> URL? {
        guard let u = fileURL(videoId), FileManager.default.fileExists(atPath: u.path) else { return nil }
        return u
    }

    /// Fetch the audio bytes once and store them. No-op if already present or a
    /// download for this id is in flight. Best-effort: failure just means no
    /// offline copy, playback already streamed fine.
    func save(_ videoId: String, from url: URL, headers: [String: String], duration: TimeInterval?) async {
        guard let dest = fileURL(videoId) else { return }
        if let duration, duration > 0 { durations[videoId] = duration; persistDurations() }
        if FileManager.default.fileExists(atPath: dest.path) { return }
        if inFlight.contains(videoId) { return }
        inFlight.insert(videoId)
        defer { inFlight.remove(videoId) }

        var req = URLRequest(url: url)
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        // ponytail: this re-fetches the bytes AVPlayer is already streaming (double
        // download of first play). Boring + robust. Tee via AVAssetResourceLoader
        // only if the extra fetch ever shows up in a bandwidth complaint.
        do {
            let (tmp, resp) = try await URLSession.shared.download(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                try? FileManager.default.removeItem(at: tmp); return
            }
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
            trim()
        } catch { /* offline copy is best-effort */ }
    }

    /// All cached track ids (files on disk) — the offline "Downloads" library.
    func allIds() -> [String] {
        guard let dir,
              let items = try? FileManager.default.contentsOfDirectory(atPath: dir.path)
        else { return [] }
        return items.filter { $0.hasSuffix(".m4a") }.map { String($0.dropLast(4)) }
    }

    private func bytes(of ids: [String]) -> Int64 {
        ids.reduce(Int64(0)) { sum, id in
            guard let u = fileURL(id),
                  let v = try? u.resourceValues(forKeys: [.fileSizeKey]),
                  let s = v.fileSize else { return sum }
            return sum + Int64(s)
        }
    }

    /// Bytes of the user's explicit downloads (settings display).
    func downloadsBytes() -> Int64 { bytes(of: allIds().filter { metas[$0] != nil }) }
    /// Bytes of transient playback cache — files never explicitly downloaded.
    func cacheBytes() -> Int64 { bytes(of: allIds().filter { metas[$0] == nil }) }

    /// Delete only the transient cache; explicit downloads stay.
    func clearCache() {
        for id in allIds() where metas[id] == nil { remove(id) }
    }

    /// Delete the user's explicit downloads (their files + registry entries).
    func clearDownloads() {
        for id in metas.keys { remove(id) }
    }

    /// Cache files (not downloads) older than cacheTTL are expired — the audio
    /// on disk is a playback cache, not the user's library.
    private func purgeStaleCache() {
        let fm = FileManager.default
        for id in allIds() where metas[id] == nil {
            guard let u = fileURL(id),
                  let mod = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            else { continue }
            if Date().timeIntervalSince(mod) > cacheTTL { try? fm.removeItem(at: u) }
        }
    }

    /// Drop a track's local copy (self-heal path deletes a corrupt/failed file so
    /// the next play re-resolves instead of failing on it again).
    func remove(_ videoId: String) {
        guard let u = fileURL(videoId) else { return }
        try? FileManager.default.removeItem(at: u)
        if durations.removeValue(forKey: videoId) != nil { persistDurations() }
        if metas.removeValue(forKey: videoId) != nil,
           let f = metasFile, let data = try? JSONEncoder().encode(metas) {
            try? data.write(to: f)
        }
    }

    /// Keep the audio dir under maxBytes, deleting least-recently-modified CACHE
    /// files first. Explicit downloads are pinned — never trimmed.
    private func trim() {
        guard let dir else { return }
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let items = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: keys) else { return }
        var files = items.compactMap { u -> (url: URL, size: Int64, date: Date)? in
            guard let v = try? u.resourceValues(forKeys: Set(keys)),
                  let size = v.fileSize, let date = v.contentModificationDate else { return nil }
            return (u, Int64(size), date)
        }
        var total = files.reduce(Int64(0)) { $0 + $1.size }
        guard total > maxBytes else { return }
        files.sort { $0.date < $1.date }   // oldest first
        for f in files {
            if total <= maxBytes { break }
            let id = f.url.deletingPathExtension().lastPathComponent
            if metas[id] != nil { continue }   // pinned download — keep
            try? fm.removeItem(at: f.url)
            total -= f.size
        }
    }
}
