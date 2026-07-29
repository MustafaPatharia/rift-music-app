// SPDX-License-Identifier: GPL-3.0-only
//
// Rift — native macOS YouTube Music player. App entry.
// Not affiliated with, endorsed by, or connected to Google LLC / YouTube.
//
// The AppDelegate owns the notch + menu-bar shells; the main window, notch, and
// menu bar all share the one PlayerController from AppServices. The main window
// opens at a fixed size and won't shrink below its content minimum.

import SwiftUI

@main
struct RiftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(AppServices.shared.player)
                .environmentObject(AppServices.shared.auth)
                .environmentObject(AppServices.shared.ui)
                .environmentObject(AppServices.shared.mode)
                .frame(minWidth: 1250, maxWidth: .infinity,
                       minHeight: 850, maxHeight: .infinity)
        }
        .windowStyle(.hiddenTitleBar)
        // Open at the content minimum, not larger — a first launch shouldn't
        // take over the screen. macOS remembers the frame after that, so this
        // only applies until the user resizes it once.
        .defaultSize(width: 1250, height: 850)
        .defaultPosition(.center)
        .windowResizability(.contentMinSize)
        .commands {
            CommandMenu("Playback") {
                let p = AppServices.shared.player
                Button(p.isPlaying ? "Pause" : "Play") { p.togglePlayPause() }
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(p.track == nil)
                Button("Next") { p.next() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                Button("Previous") { p.previous() }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Divider()
                Button("Shuffle") { p.toggleShuffle() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Repeat") { p.cycleRepeat() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Divider()
                Button("Toggle Full Player") {
                    guard p.track != nil else { return }
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        AppServices.shared.ui.showFullPlayer.toggle()
                    }
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                Button("Toggle Queue") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        AppServices.shared.ui.showQueue.toggle()
                    }
                }
                .keyboardShortcut("u", modifiers: .command)
            }
        }

        // No separate Settings window — settings live in-app (sidebar → Settings).
    }
}
