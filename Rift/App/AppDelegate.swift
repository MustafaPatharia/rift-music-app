// SPDX-License-Identifier: GPL-3.0-only
//
// AppDelegate — owns the AppKit shells (notch panel + menu-bar item) and shows
// or hides them per the display-mode setting. Notch is only shown when a
// physical notch exists; a notch request on a non-notch Mac falls back to the
// menu bar so playback controls are always reachable.

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var notch: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let s = AppServices.shared
        menuBar = MenuBarController(player: s.player)
        notch = NotchController(player: s.player)

        s.mode.onChange = { [weak self] mode in self?.apply(mode) }
        apply(s.mode.mode)
    }

    private func apply(_ mode: AppModeController.Mode) {
        let notchOK = notch?.isNotchAvailable ?? false
        let showNotch = (mode == .notch || mode == .both) && notchOK
        // Menu bar is the fallback: also shown when notch was asked for but none exists.
        let showMenuBar = mode == .menuBar || mode == .both || (mode == .notch && !notchOK)

        Log.player.info("display mode → \(mode.rawValue, privacy: .public) (notch available \(notchOK)) ⇒ notch \(showNotch) menuBar \(showMenuBar)")
        showNotch ? notch?.show() : notch?.hide()
        showMenuBar ? menuBar?.install() : menuBar?.remove()
    }
}
