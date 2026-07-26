// SPDX-License-Identifier: GPL-3.0-only
//
// Downloader — explicit "Download" action. Resolves the stream (cache-first),
// saves the audio bytes for true offline, and records the track's metadata so
// the Library "Downloads" shelf can show it even if it was never played.

import Foundation

enum Downloader {
    /// Fire-and-forget download of one track. Idempotent — already-downloaded
    /// tracks just (re)record their metadata.
    /// ponytail: no progress UI / error surfacing yet — logs only. Add a
    /// download-state store when someone asks to watch progress.
    static func download(_ track: PlayableTrack) {
        guard URL(string: track.id)?.isFileURL != true else { return }   // already local
        Task.detached {
            await AudioFileCache.shared.setMeta(
                .init(title: track.title, artist: track.artist,
                      artworkURL: track.artworkURL?.absoluteString,
                      downloadedAt: Date()),
                for: track.id)
            if await AudioFileCache.shared.localFile(for: track.id) != nil {
                Log.player.info("↓ \(track.title, privacy: .public) — already downloaded")
                return
            }
            // Resolve: stream cache first, else yt-dlp.
            var r = await StreamCache.shared.get(track.id)
            if r == nil {
                r = try? await StreamResolver.resolveAudio(videoId: track.id)
                if let r { await StreamCache.shared.put(track.id, r) }
            }
            guard let r else {
                Log.player.error("↓ \(track.title, privacy: .public) — resolve failed, not downloaded")
                return
            }
            await AudioFileCache.shared.save(track.id, from: r.url, headers: r.headers,
                                             duration: r.duration)
            let ok = await AudioFileCache.shared.localFile(for: track.id) != nil
            Log.player.info("↓ \(track.title, privacy: .public) — \(ok ? "downloaded" : "failed", privacy: .public)")
        }
    }
}
