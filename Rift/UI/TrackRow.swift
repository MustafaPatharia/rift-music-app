// SPDX-License-Identifier: GPL-3.0-only
//
// TrackRow — one track line, reused by search results and album/playlist detail.
// Shows a leading track number (detail) or artwork (search), and a waveform on
// the currently playing row.

import SwiftUI

struct TrackRow: View {
    @EnvironmentObject private var player: PlayerController
    let index: Int?        // non-nil = show number, nil = show artwork
    let track: PlayableTrack
    let isCurrent: Bool
    let isPlaying: Bool
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let index {
                    Text("\(index)").font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary).frame(width: 26)
                } else {
                    Artwork(url: track.artworkURL, size: 44)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title).lineLimit(1).fontWeight(isCurrent ? .semibold : .regular)
                    if !track.artist.isEmpty {
                        Text(track.artist).lineLimit(1).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isCurrent && isPlaying {
                    Image(systemName: "waveform").foregroundStyle(.tint).symbolEffect(.variableColor)
                }
                queueMenu.opacity(hover ? 1 : 0)   // reveal on hover
            }
            .padding(.vertical, 5).padding(.horizontal, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .background(isCurrent ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(.clear),
                    in: .rect(cornerRadius: 8))
        .contextMenu { queueActions }
    }

    private var queueMenu: some View {
        Menu {
            queueActions
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary).frame(width: 26, height: 26).contentShape(.rect)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }

    @ViewBuilder private var queueActions: some View {
        Button { action() } label: { Label("Play", systemImage: "play.fill") }
        Button { player.playNext(track) } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }
        Button { player.addToQueue(track) } label: { Label("Add to Queue", systemImage: "text.append") }
        Divider()
        Button { LikeStore.shared.toggle(track) } label: {
            LikeStore.shared.isLiked(track.id)
                ? Label("Remove from Liked", systemImage: "heart.slash")
                : Label("Like", systemImage: "heart")
        }
        AddToPlaylistMenu(track: track)
        Button { Downloader.download(track) } label: { Label("Download", systemImage: "arrow.down.circle") }
    }
}
