// SPDX-License-Identifier: GPL-3.0-only
//
// NotchDetector — is there a physical notch, and where is it? Uses public
// AppKit geometry (safeAreaInsets + auxiliaryTopLeftArea/RightArea), not private
// APIs. On non-notch Macs `hasNotch` is false and the app falls back to menu-bar
// mode (see AppModeController).

import AppKit

enum NotchDetector {
    /// The built-in display carrying a notch, if any.
    static var notchScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
    }

    static var hasNotch: Bool { notchScreen != nil }

    /// Physical notch rect in global (bottom-left origin) screen coordinates.
    /// Width is derived from the auxiliary areas flanking the notch; height is
    /// the top safe-area inset. Falls back to a sane default width if the
    /// auxiliary areas aren't reported.
    static func notchRect(on screen: NSScreen) -> CGRect {
        let frame = screen.frame
        let height = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : 32

        let left = screen.auxiliaryTopLeftArea?.width ?? 0
        let right = screen.auxiliaryTopRightArea?.width ?? 0
        let width: CGFloat = (left > 0 && right > 0) ? (frame.width - left - right) : 200

        let x = frame.minX + (frame.width - width) / 2
        let y = frame.maxY - height
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
