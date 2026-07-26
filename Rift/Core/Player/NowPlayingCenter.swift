// SPDX-License-Identifier: GPL-3.0-only
//
// NowPlayingCenter — bridges the player to macOS system media UI:
// MPNowPlayingInfoCenter (Control Center / lock screen / menu-bar Now Playing)
// and MPRemoteCommandCenter (F7/F8 media keys, headphone controls).
// Commands route back to the PlayerController via the closures set on init.

import Foundation
import MediaPlayer
import AppKit

@MainActor
final class NowPlayingCenter {
    struct Handlers {
        var play: () -> Void
        var pause: () -> Void
        var toggle: () -> Void
        var next: () -> Void
        var previous: () -> Void
        var seek: (TimeInterval) -> Void
    }

    private let info = MPNowPlayingInfoCenter.default()
    private var artworkURL: URL?

    init(_ h: Handlers) {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { _ in h.play(); return .success }
        c.pauseCommand.addTarget { _ in h.pause(); return .success }
        c.togglePlayPauseCommand.addTarget { _ in h.toggle(); return .success }
        c.nextTrackCommand.addTarget { _ in h.next(); return .success }
        c.previousTrackCommand.addTarget { _ in h.previous(); return .success }
        c.changePlaybackPositionCommand.addTarget { event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            h.seek(e.positionTime); return .success
        }
        c.nextTrackCommand.isEnabled = true
        c.previousTrackCommand.isEnabled = true
    }

    /// Push track metadata. Artwork fetched async and patched in when ready.
    func update(track: PlayableTrack?, duration: TimeInterval, elapsed: TimeInterval, playing: Bool) {
        guard let track else {
            info.nowPlayingInfo = nil
            info.playbackState = .stopped
            return
        }
        var np: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
        ]
        if duration > 0 { np[MPMediaItemPropertyPlaybackDuration] = duration }
        // Keep existing artwork if same track (avoids flicker while scrubbing).
        if let existing = info.nowPlayingInfo?[MPMediaItemPropertyArtwork], artworkURL == track.artworkURL {
            np[MPMediaItemPropertyArtwork] = existing
        }
        info.nowPlayingInfo = np
        info.playbackState = playing ? .playing : .paused

        if artworkURL != track.artworkURL {
            artworkURL = track.artworkURL
            if let url = track.artworkURL { fetchArtwork(url, for: track.id) }
        }
    }

    private func fetchArtwork(_ url: URL, for trackId: String) {
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data) else { return }
            // Ignore if the track changed while loading.
            guard artworkURL == url else { return }
            // MediaPlayer invokes this handler on its OWN queue, so it must be
            // @Sendable / non-main-actor — otherwise Swift 6 traps on the wrong
            // executor. NSImage is safe to read for drawing off the main thread.
            let img = image
            let art = MPMediaItemArtwork(boundsSize: img.size) { @Sendable _ in img }
            var np = info.nowPlayingInfo ?? [:]
            np[MPMediaItemPropertyArtwork] = art
            info.nowPlayingInfo = np
        }
    }
}
