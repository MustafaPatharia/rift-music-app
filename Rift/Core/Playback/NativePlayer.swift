// SPDX-License-Identifier: GPL-3.0-only
//
// NativePlayer — pure-native audio path. AVPlayer (AVFoundation) plays a direct
// stream URL resolved by StreamResolver (yt-dlp, out of process). No WebView.
// Also plays local files: a file:// PlayableTrack.id skips resolution.

import Foundation
import Combine
import AVFoundation

@MainActor
final class NativePlayer: NSObject, PlaybackSource {

    private let stateSubject = CurrentValueSubject<PlaybackState, Never>(.idle)
    private let timeSubject = CurrentValueSubject<TimeInterval, Never>(0)
    private let durationSubject = CurrentValueSubject<TimeInterval, Never>(0)

    var state: AnyPublisher<PlaybackState, Never> { stateSubject.eraseToAnyPublisher() }
    var currentTime: AnyPublisher<TimeInterval, Never> { timeSubject.eraseToAnyPublisher() }
    var duration: AnyPublisher<TimeInterval, Never> { durationSubject.eraseToAnyPublisher() }

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var itemObservers = Set<AnyCancellable>()
    private var resolveTask: Task<Void, Never>?
    private var current: PlayableTrack?     // for self-heal reloads
    private var triedFresh = false          // one forced re-resolve per load

    override init() {
        super.init()
        player.automaticallyWaitsToMinimizeStalling = true

        // Poll playback time (250ms) on the main queue → publish.
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] t in
            MainActor.assumeIsolated {   // observer scheduled on .main
                self?.timeSubject.send(t.seconds)
            }
        }
    }

    // No deinit cleanup needed: single app-lifetime instance; the observer is
    // released with the player. (nonisolated deinit can't touch main-actor state.)

    // MARK: PlaybackSource
    func load(_ track: PlayableTrack) {
        current = track
        triedFresh = false
        resolve(track, forceFresh: false)
    }

    /// Re-attempt the current track from scratch (user "retry" or self-heal).
    func reload() {
        guard let t = current else { return }
        triedFresh = false
        resolve(t, forceFresh: true)
    }

    private func resolve(_ track: PlayableTrack, forceFresh: Bool) {
        resolveTask?.cancel()
        // Silence the outgoing track NOW — otherwise it keeps playing until the new
        // stream resolves (~1s of yt-dlp). Tear down its item + observers immediately.
        itemObservers.removeAll()
        player.replaceCurrentItem(with: nil)
        timeSubject.send(0)
        durationSubject.send(0)
        stateSubject.send(.loading)

        // Local file → play directly, no resolution (AVPlayer duration is fine here).
        if let fileURL = URL(string: track.id), fileURL.isFileURL {
            setItem(fileURL, knownDuration: nil); return
        }
        // YouTube videoId → cache hit plays instantly; otherwise resolve out of
        // process, cache, then play. forceFresh evicts a stale (403'd) cache entry.
        let t0 = ContinuousClock.now
        resolveTask = Task { [weak self] in
            guard let self else { return }
            if forceFresh {
                await StreamCache.shared.evict(track.id)
                await AudioFileCache.shared.remove(track.id)   // purge a bad local copy
            }
            // Offline: if the bytes are on disk, play them — no network, no yt-dlp.
            if !forceFresh, let local = await AudioFileCache.shared.localFile(for: track.id) {
                if Task.isCancelled { return }
                // Real duration: track metadata → the one we saved with the bytes →
                // else nil (AVPlayer's, which may double). Never trust AVPlayer here.
                var known = track.duration
                if known == nil { known = await AudioFileCache.shared.duration(for: track.id) }
                if known == nil { known = await StreamCache.shared.get(track.id)?.duration }
                Log.player.info("▶︎ \(track.title, privacy: .public) — instant (offline file, \(Log.ms(since: t0))ms)")
                if let d = known, d > 0 { self.durationSubject.send(d) }
                self.setItem(local, knownDuration: known)
                return
            }
            do {
                let r: StreamResolver.Resolved
                if !forceFresh, let cached = await StreamCache.shared.get(track.id) {
                    r = cached
                    Log.player.info("▶︎ \(track.title, privacy: .public) — fast (stream cache, \(Log.ms(since: t0))ms)")
                } else {
                    r = try await Self.resolveWithRetry(track.id)
                    await StreamCache.shared.put(track.id, r)
                    Log.player.info("▶︎ \(track.title, privacy: .public) — cold (resolved by yt-dlp, \(Log.ms(since: t0))ms)")
                }
                if Task.isCancelled { return }
                if let d = r.duration, d > 0 { self.durationSubject.send(d) }
                self.setItem(r.url, knownDuration: r.duration, headers: r.headers)
                // Save the audio for true-offline replay (best-effort, background).
                let id = track.id
                Task.detached { await AudioFileCache.shared.save(id, from: r.url, headers: r.headers, duration: r.duration) }
            } catch {
                if Task.isCancelled { return }
                self.stateSubject.send(.error(error.localizedDescription))
            }
        }
    }

    /// yt-dlp resolve with one retry — the extractor occasionally 500s transiently.
    private static func resolveWithRetry(_ videoId: String) async throws -> StreamResolver.Resolved {
        do {
            return try await StreamResolver.resolveAudio(videoId: videoId)
        } catch {
            // Transient 500, a cipher change, or the pinned android_vr client going
            // away — pull the latest yt-dlp (throttled) and retry with its full
            // multi-client default (slower, but resilient).
            await YtDlpManager.shared.update()
            try? await Task.sleep(nanoseconds: 600_000_000)
            return try await StreamResolver.resolveAudio(videoId: videoId, fastClient: false)
        }
    }

    /// Warm the cache for a track we're likely to play next (skip-forward),
    /// without touching current playback. Cheap no-op if already cached/local.
    func preload(_ track: PlayableTrack) {
        if let u = URL(string: track.id), u.isFileURL { return }
        Task {
            if await StreamCache.shared.get(track.id) != nil { return }
            if let r = try? await StreamResolver.resolveAudio(videoId: track.id) {
                await StreamCache.shared.put(track.id, r)
            }
        }
    }

    private func setItem(_ url: URL, knownDuration: TimeInterval?, headers: [String: String] = [:]) {
        itemObservers.removeAll()   // drop the previous item's KVO/notification subs (leak fix)

        // googlevideo CDN URLs require yt-dlp's headers (User-Agent etc.) or they
        // 403 → AVPlayer reports a generic "unknown error". Pass them through.
        let asset = headers.isEmpty
            ? AVURLAsset(url: url)
            : AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)

        // Duration + status via KVO → Combine. For YouTube streams we already have
        // the real duration from yt-dlp; ignore AVPlayer's (it doubles some m4a).
        item.publisher(for: \.status).receive(on: DispatchQueue.main).sink { [weak self] status in
            guard let self else { return }
            switch status {
            case .readyToPlay:
                if knownDuration == nil {
                    let d = item.duration.seconds
                    if d.isFinite && d > 0 { self.durationSubject.send(d) }
                }
            case .failed:
                // A cached googlevideo URL that expired mid-life 403s here. Self-heal
                // once: evict + re-resolve fresh before surfacing an error.
                if !self.triedFresh, let t = self.current, URL(string: t.id)?.isFileURL != true {
                    self.triedFresh = true
                    self.resolve(t, forceFresh: true)
                } else {
                    self.stateSubject.send(.error(item.error?.localizedDescription ?? "playback failed"))
                }
            default: break
            }
        }.store(in: &itemObservers)

        // End-of-track.
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.stateSubject.send(.ended) }
            .store(in: &itemObservers)

        player.replaceCurrentItem(with: item)
        play()
    }

    func play() {
        player.play()
        stateSubject.send(.playing)
    }
    func pause() {
        player.pause()
        stateSubject.send(.paused)
    }
    func seek(to seconds: TimeInterval) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
    }
    func setVolume(_ volume: Double) {
        player.volume = Float(max(0, min(1, volume)))
    }
}
