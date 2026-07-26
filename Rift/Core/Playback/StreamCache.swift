// SPDX-License-Identifier: GPL-3.0-only
//
// StreamCache — remembers resolved googlevideo streams so replay / skip-back is
// instant and preloading the next track makes skip-forward near-gapless. A
// resolved URL is valid until its `expire=` query param lapses (a few hours);
// after that it 403s and must be re-resolved.
//
// Persisted to disk (JSON in Caches) so replay-after-restart is instant too:
// on launch we reload still-valid entries and skip the yt-dlp round-trip.

import Foundation

actor StreamCache {
    static let shared = StreamCache()

    private struct Entry: Codable { let resolved: StreamResolver.Resolved; let expiry: Date }
    private var entries: [String: Entry] = [:]

    private let fileURL: URL? = {
        let fm = FileManager.default
        guard let base = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("com.mustafapatharia.riftmusicapp", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("streams.json")
    }()

    init() { entries = Self.load(from: fileURL) }

    /// A still-valid resolved stream for this videoId, or nil (expired/miss).
    func get(_ videoId: String) -> StreamResolver.Resolved? {
        guard let e = entries[videoId] else { return nil }
        guard e.expiry > Date().addingTimeInterval(30) else {   // 30s safety margin
            entries[videoId] = nil
            persist()
            return nil
        }
        return e.resolved
    }

    func put(_ videoId: String, _ resolved: StreamResolver.Resolved) {
        entries[videoId] = Entry(resolved: resolved, expiry: Self.expiry(from: resolved.url))
        persist()
    }

    /// Drop a stale entry (e.g. its URL 403'd before its `expire=` claimed).
    func evict(_ videoId: String) { entries[videoId] = nil; persist() }

    var count: Int { entries.count }
    func clear() { entries.removeAll(); persist() }

    // MARK: disk

    private static func load(from fileURL: URL?) -> [String: Entry] {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let disk = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
        let cutoff = Date().addingTimeInterval(30)
        return disk.filter { $0.value.expiry > cutoff }   // drop already-expired on launch
    }

    private func persist() {
        guard let fileURL, let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// googlevideo URLs carry `&expire=<unixSeconds>`. Trust it; fall back to a
    /// conservative 1h if it's missing.
    private static func expiry(from url: URL) -> Date {
        if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let raw = comps.queryItems?.first(where: { $0.name == "expire" })?.value,
           let secs = TimeInterval(raw) {
            return Date(timeIntervalSince1970: secs)
        }
        return Date().addingTimeInterval(3600)
    }
}
