// SPDX-License-Identifier: GPL-3.0-only
//
// TrackPosterCard — the poster-first song tile (owner's call: no table rows
// for songs anywhere; posters like the home shelves). Hover lift + play
// overlay, standard song context menu. Used by search results, the full
// history page, and any future song grid.

import SwiftUI

/// Five-bar audio visualizer indicator. Sine-driven (deterministic, cheap),
/// pauses flat when playback is paused. Used as the "this poster is playing"
/// badge on song tiles.
struct EQBars: View {
    let active: Bool
    var style: AnyShapeStyle = AnyShapeStyle(.tint)
    private let speeds: [Double] = [2.1, 3.3, 2.7, 3.9, 2.4]
    private let phases: [Double] = [0, 1.3, 2.6, 0.7, 1.9]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !active)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<5, id: \.self) { i in
                    Capsule()
                        .frame(width: 3,
                               height: active ? 5 + 12 * abs(sin(t * speeds[i] + phases[i])) : 4)
                }
            }
        }
        .frame(width: 26, height: 18)
        .foregroundStyle(style)
        .animation(.easeOut(duration: 0.25), value: active)
    }
}

struct TrackPosterCard: View {
    @EnvironmentObject var player: PlayerController
    let track: PlayableTrack
    var size: CGFloat = 150
    let play: () -> Void
    @State private var hover = false

    private var isCurrent: Bool { player.track?.id == track.id }

    var body: some View {
        Button(action: play) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    Artwork(url: track.artworkURL, size: size)
                        .clipShape(.rect(cornerRadius: 10))
                        .shadow(color: .black.opacity(hover ? 0.35 : 0.18),
                                radius: hover ? 14 : 6, y: 5)
                    if isCurrent && player.isPlaying {
                        // This poster is what's playing — live EQ badge.
                        EQBars(active: true, style: AnyShapeStyle(.white))
                            .padding(.horizontal, 7).padding(.vertical, 5)
                            .background(.black.opacity(0.55), in: .rect(cornerRadius: 8))
                            .padding(8)
                            .transition(.scale.combined(with: .opacity))
                    } else if hover || isCurrent {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 30)).symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.55))
                            .padding(8)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                Text(track.title).font(.callout.weight(.medium)).lineLimit(2)
                    .multilineTextAlignment(.leading)
                if !track.artist.isEmpty {
                    Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(width: size, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .scaleEffect(hover ? 1.03 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hover)
        .onHover { hover = $0 }
        .contextMenu {
            Button(action: play) { Label("Play", systemImage: "play.fill") }
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
}
