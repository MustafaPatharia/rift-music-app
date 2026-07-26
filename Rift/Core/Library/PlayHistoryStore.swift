// SPDX-License-Identifier: GPL-3.0-only
//
// PlayHistoryStore — LOCAL-ONLY listening history. Every finished play session
// is appended to a JSONL file in Application Support; the stats dashboard and
// the "Recently played" shelf aggregate from it. No cloud, no telemetry — the
// data never leaves this Mac.

import Foundation

/// One listening session of one track. Written when the session CLOSES (track
/// change / end), so `seconds` is the furthest point actually reached.
struct PlayEvent: Codable, Identifiable, Sendable {
    var id: String { "\(trackId)-\(ts.timeIntervalSince1970)" }
    let trackId: String
    let title: String
    let artist: String
    let artworkURL: String?
    let ts: Date                 // when the session started
    let seconds: TimeInterval    // how far into the track the listener got
    let duration: TimeInterval?  // full track length if known

    var asTrack: PlayableTrack {
        PlayableTrack(id: trackId, title: title, artist: cleanArtist,
                      artworkURL: artworkURL.flatMap(URL.init(string:)), duration: duration)
    }

    /// Listening seconds, healed: rows written before the doubled-m4a cap can
    /// carry seconds up to 2× the track length — clamp to duration on read.
    var cleanSeconds: TimeInterval {
        guard let duration, duration > 0 else { return seconds }
        return min(seconds, duration)
    }

    /// Artist, healed: old rows stored the full byline ("Artist • Album • 3:29").
    var cleanArtist: String {
        artist.components(separatedBy: " • ").first ?? artist
    }
}

actor PlayHistoryStore {
    static let shared = PlayHistoryStore()

    private var events: [PlayEvent] = []
    private let file: URL?

    init() {
        let fm = FileManager.default
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            .map { $0.appendingPathComponent("com.mustafapatharia.riftmusicapp", isDirectory: true) }
        if let dir { try? fm.createDirectory(at: dir, withIntermediateDirectories: true) }
        file = dir?.appendingPathComponent("history.jsonl")
        // ponytail: whole file loaded in memory + JSONL append. ~36k events/year of
        // heavy listening ≈ a few MB — fine. Upgrade to SQLite/GRDB if launch decode
        // ever shows up in Instruments.
        if let file, let data = try? String(contentsOf: file, encoding: .utf8) {
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .secondsSince1970
            events = data.split(separator: "\n").compactMap {
                try? dec.decode(PlayEvent.self, from: Data($0.utf8))
            }
        }
    }

    /// Append one closed play session. Sessions under 5s are noise (skips) — dropped.
    func log(_ e: PlayEvent) {
        guard e.seconds >= 5 else { return }
        events.append(e)
        guard let file else { return }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
        guard let line = try? enc.encode(e) else { return }
        if let h = try? FileHandle(forWritingTo: file) {
            defer { try? h.close() }
            _ = try? h.seekToEnd(); try? h.write(contentsOf: line + Data("\n".utf8))
        } else {
            try? (line + Data("\n".utf8)).write(to: file)
        }
    }

    /// All events, oldest→newest.
    func all() -> [PlayEvent] { events }

    /// Wipe all listening history (settings "clear data").
    func clear() {
        events.removeAll()
        if let file { try? FileManager.default.removeItem(at: file) }
    }

    /// Most recent distinct tracks, newest first — the "Recently played" shelf.
    func recent(limit: Int = 12) -> [PlayEvent] {
        var seen = Set<String>()
        var out: [PlayEvent] = []
        for e in events.reversed() where seen.insert(e.trackId).inserted {
            out.append(e)
            if out.count == limit { break }
        }
        return out
    }
}
