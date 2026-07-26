// SPDX-License-Identifier: GPL-3.0-only
//
// HeroCard — the big featured banner at the top of Home (ref: "Trending" /
// artist hero). Full-bleed artwork with a gradient scrim, kind label, title,
// and a Play affordance. Opens the collection or plays the song.

import SwiftUI

struct HeroCard: View {
    @EnvironmentObject var player: PlayerController
    let card: MusicCard
    @State private var hover = false
    @State private var loading = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Tap the banner background to open the collection (or play a song).
            Group {
                if card.kind == .song {
                    Button { player.play(card.asTrack) } label: { banner }.buttonStyle(.plain)
                } else {
                    NavigationLink(value: card) { banner }.buttonStyle(.plain)
                }
            }
        }
        .scaleEffect(hover ? 1.01 : 1)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: hover)
        .onHover { hover = $0 }
    }

    private var banner: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: card.artworkURL) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(.quaternary)
            }
            .frame(height: 230).frame(maxWidth: .infinity).clipped()

            LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.72)],
                           startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 8) {
                Text(kindLabel.uppercased())
                    .font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.8))
                Text(card.title)
                    .font(.system(size: 34, weight: .heavy)).foregroundStyle(.white).lineLimit(2)
                if !card.subtitle.isEmpty {
                    Text(card.subtitle).font(.callout).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                }
                // Real play button (stops the tap from bubbling to navigation).
                GlassPillButton("Play", icon: "play.fill", loading: loading) { play() }
                    .padding(.top, 4)
            }
            .padding(22)
        }
        .frame(height: 230)
        .clipShape(.rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(hover ? 0.4 : 0.25), radius: hover ? 22 : 14, y: 8)
    }

    private func play() {
        if card.kind == .song { player.play(card.asTrack); return }
        loading = true
        Task {
            defer { loading = false }
            if let tracks = try? await InnerTubeClient.tracks(forBrowseId: card.id),
               let first = tracks.first {
                player.play(first, in: tracks)
            }
        }
    }

    private var kindLabel: String {
        switch card.kind {
        case .song: return "Featured"
        case .album: return "Album"
        case .playlist: return "Playlist"
        case .artist: return "Artist"
        }
    }
}
