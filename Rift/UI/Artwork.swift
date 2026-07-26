// SPDX-License-Identifier: GPL-3.0-only
//
// Artwork — shared async thumbnail used across the dashboard (cards, rows,
// detail headers, now-playing bar). Square by default; `circle` for artists.

import SwiftUI

/// Full-window ambient background: the now-playing artwork, heavily blurred and
/// darkened, so the glass panels frost over the poster instead of the desktop.
struct AmbientArtwork: View {
    let url: URL
    var body: some View {
        AsyncImage(url: url) { img in
            img.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Color.clear
        }
        .ignoresSafeArea()
        .blur(radius: 90)
        .overlay(Color.black.opacity(0.45))
        .clipped()
        .id(url)
        .transition(.opacity)
    }
}

struct Artwork: View {
    let url: URL?
    var size: CGFloat = 44
    var circle: Bool = false

    var body: some View {
        AsyncImage(url: url) { img in
            img.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Rectangle().fill(.quaternary)
                .overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
        }
        .frame(width: size, height: size)
        .clipShape(shape)
    }

    private var shape: AnyShape {
        circle ? AnyShape(.circle) : AnyShape(.rect(cornerRadius: size > 80 ? 10 : 6))
    }
}
