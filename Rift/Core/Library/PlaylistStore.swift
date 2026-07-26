// SPDX-License-Identifier: GPL-3.0-only
//
// PlaylistStore — user playlists. Local-first like LikeStore: every edit lands
// in playlists.json instantly and works anonymous; when signed in, the same
// edit is pushed best-effort to YouTube Music (ytmusicapi create_playlist /
// edit_playlist / delete_playlist protocol). The local copy is the source of
// truth for the UI — a failed push never blocks or reverts anything.

import Foundation

@MainActor
final class PlaylistStore: ObservableObject {
    static let shared = PlaylistStore()

    struct UserPlaylist: Identifiable, Codable {
        let id: String            // local UUID — stable across renames/pushes
        var remoteId: String?     // YTM playlistId once created remotely
        var title: String
        var tracks: [PlayableTrack]
    }

    /// Set from any context menu's "New Playlist…" — ContentView presents the
    /// name prompt (one app-level alert instead of a sheet per call site).
    struct NewPrompt: Identifiable { let id = UUID(); let track: PlayableTrack? }
    @Published var newPrompt: NewPrompt?

    @Published private(set) var playlists: [UserPlaylist] = []

    private let file: URL? = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("com.mustafapatharia.riftmusicapp/playlists.json")

    init() {
        if let file, let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([UserPlaylist].self, from: data) {
            playlists = saved
        }
    }

    func playlist(_ id: String) -> UserPlaylist? { playlists.first { $0.id == id } }

    // MARK: edits (local now, remote best-effort)

    func create(_ title: String, with track: PlayableTrack? = nil) {
        let name = title.trimmingCharacters(in: .whitespaces)
        let p = UserPlaylist(id: UUID().uuidString, remoteId: nil,
                             title: name.isEmpty ? "New Playlist" : name,
                             tracks: track.map { [$0] } ?? [])
        playlists.append(p)
        save()
        push { [weak self] in
            let rid = try await InnerTubeClient.createPlaylist(title: p.title)
            try await InnerTubeClient.addPlaylistItems(
                playlistId: rid, videoIds: p.tracks.map(\.id).filter(Self.isRemoteId))
            await MainActor.run { self?.setRemoteId(rid, for: p.id) }
        }
    }

    func add(_ track: PlayableTrack, to id: String) {
        guard let i = index(id),
              !playlists[i].tracks.contains(where: { $0.id == track.id }) else { return }
        playlists[i].tracks.append(track)
        save()
        guard let rid = playlists[i].remoteId, Self.isRemoteId(track.id) else { return }
        push { try await InnerTubeClient.addPlaylistItems(playlistId: rid, videoIds: [track.id]) }
    }

    func remove(trackId: String, from id: String) {
        guard let i = index(id) else { return }
        playlists[i].tracks.removeAll { $0.id == trackId }
        save()
        guard let rid = playlists[i].remoteId, Self.isRemoteId(trackId) else { return }
        push { try await InnerTubeClient.removePlaylistItems(playlistId: rid, videoIds: [trackId]) }
    }

    func rename(_ id: String, to title: String) {
        let name = title.trimmingCharacters(in: .whitespaces)
        guard let i = index(id), !name.isEmpty, playlists[i].title != name else { return }
        playlists[i].title = name
        save()
        guard let rid = playlists[i].remoteId else { return }
        push { try await InnerTubeClient.renamePlaylist(playlistId: rid, title: name) }
    }

    func delete(_ id: String) {
        guard let i = index(id) else { return }
        let rid = playlists[i].remoteId
        playlists.remove(at: i)
        save()
        if let rid { push { try await InnerTubeClient.deletePlaylist(playlistId: rid) } }
    }

    /// YTM playlistIds already mirrored remotely — Library uses this to hide
    /// the duplicate card coming back down in libraryPlaylists().
    var remoteIds: Set<String> { Set(playlists.compactMap(\.remoteId)) }

    // MARK: plumbing

    private func index(_ id: String) -> Int? { playlists.firstIndex { $0.id == id } }

    // Local files have a file-URL id — they can't exist on YTM, keep them local.
    nonisolated private static func isRemoteId(_ id: String) -> Bool { URL(string: id)?.isFileURL != true }

    private func setRemoteId(_ rid: String, for id: String) {
        guard let i = index(id) else { return }
        playlists[i].remoteId = rid
        save()
    }

    private func save() {
        if let file { try? JSONEncoder().encode(playlists).write(to: file) }
    }

    // ponytail: fire-and-forget push, no retry queue — a playlist created while
    // anonymous stays local-only even after sign-in; add an outbox if that bites.
    private func push(_ op: @escaping @Sendable () async throws -> Void) {
        guard AuthStore.load() != nil else { return }
        Task.detached { try? await op() }
    }
}
