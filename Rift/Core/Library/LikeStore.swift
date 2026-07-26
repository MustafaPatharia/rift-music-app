// SPDX-License-Identifier: GPL-3.0-only
//
// LikeStore — liked songs. Local-first: the heart flips instantly and persists
// to likes.json; when signed in, the change is also pushed to YouTube Music
// (ytmusicapi rate_song protocol). Anonymous likes stay local.

import Foundation

@MainActor
final class LikeStore: ObservableObject {
    static let shared = LikeStore()

    @Published private(set) var ids: Set<String> = []

    private let file: URL? = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("com.mustafapatharia.riftmusicapp/likes.json")

    init() {
        if let file, let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode(Set<String>.self, from: data) {
            ids = saved
        }
    }

    func isLiked(_ id: String) -> Bool { ids.contains(id) }

    /// Merge liked ids pulled FROM YouTube Music (sync-down). Local set only —
    /// never fires the rate API (these are already liked remotely).
    func importLiked(_ imported: [String]) {
        let merged = ids.union(imported)
        guard merged != ids else { return }
        ids = merged
        if let file { try? JSONEncoder().encode(ids).write(to: file) }
    }

    func toggle(_ track: PlayableTrack) {
        let liked = !ids.contains(track.id)
        if liked { ids.insert(track.id) } else { ids.remove(track.id) }
        if let file { try? JSONEncoder().encode(ids).write(to: file) }
        // Push to YTM (no-op for local files; silently useless when anonymous —
        // the local heart is still the source of truth for the UI).
        guard URL(string: track.id)?.isFileURL != true, AuthStore.load() != nil else { return }
        Task.detached {
            try? await InnerTubeClient.rate(videoId: track.id, liked: liked)
        }
    }
}
