// SPDX-License-Identifier: GPL-3.0-only
//
// AppServices — the single source of truth for app-lifetime singletons the
// SwiftUI scenes and the AppKit AppDelegate both need: the PlayerController and
// the display-mode setting. One player instance drives the main window, the
// notch, and the menu bar alike.

import Foundation

@MainActor
final class AppServices {
    static let shared = AppServices()

    let player = PlayerController(source: NativePlayer())
    let mode = AppModeController()
    let auth = AuthController()
    let ui = UIState()
    let setup = SetupController()
    lazy var playerPanel = PlayerPanelController(player: player, ui: ui)

    private init() {
        // Check/install a fast yt-dlp at launch (system → brew install → prompt to
        // bootstrap Homebrew), so it's ready before the first play.
        setup.start()
    }
}
