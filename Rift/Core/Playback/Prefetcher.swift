// SPDX-License-Identifier: GPL-3.0-only
//
// Prefetcher — warms StreamCache for tracks the user is *likely* to tap next
// (home carousels, an opened album, search results). A cold yt-dlp resolve is
// ~2s; doing it in the background while the user reads the list turns the tap
// into a StreamCache hit (<0.5s). This is the only way to hit that latency —
// yt-dlp can't resolve that fast live.
//
// Concurrency-capped so opening a 50-track album doesn't spawn 50 yt-dlp procs.

import Foundation

actor Prefetcher {
    static let shared = Prefetcher()

    private let maxConcurrent = 3
    private var active = 0
    private var inFlight = Set<String>()      // dedup: queued or resolving
    private var pending: [PlayableTrack] = []

    /// Warm the first `limit` resolvable tracks. Idempotent — already-cached,
    /// already-queued, and local-file tracks are skipped. Fire-and-forget.
    func warm(_ tracks: [PlayableTrack], limit: Int = 8) {
        for t in tracks.prefix(limit) {
            if URL(string: t.id)?.isFileURL == true { continue }   // local file, nothing to resolve
            if inFlight.contains(t.id) { continue }
            inFlight.insert(t.id)
            pending.append(t)
        }
        pump()
    }

    private func pump() {
        while active < maxConcurrent, !pending.isEmpty {
            let t = pending.removeFirst()
            active += 1
            Task { await self.resolveOne(t) }
        }
    }

    private func resolveOne(_ t: PlayableTrack) async {
        defer { active -= 1; inFlight.remove(t.id); pump() }
        if await StreamCache.shared.get(t.id) != nil { return }       // already warm
        if await AudioFileCache.shared.localFile(for: t.id) != nil { return }
        guard let r = try? await StreamResolver.resolveAudio(videoId: t.id) else { return }
        await StreamCache.shared.put(t.id, r)
        Log.resolve.info("prefetched \(t.title, privacy: .public)")
    }
}
