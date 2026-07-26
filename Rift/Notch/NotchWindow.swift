// SPDX-License-Identifier: GPL-3.0-only
//
// Adapted for Rift from Atoll's DynamicIslandWindow (Ebullioscopic/Atoll,
// GPL-3.0, originally boring.notch). Dropped Atoll's ScreenCaptureVisibility
// dependency; kept the panel configuration that makes a borderless floating
// window sit over the menu bar across every Space. See /NOTICE.

import Cocoa

/// Borderless floating panel that hosts the notch UI. Sits above the menu bar,
/// joins all Spaces, and never steals focus from the app it overlays.
final class NotchWindow: NSPanel {
    override init(contentRect: NSRect,
                  styleMask: NSWindow.StyleMask,
                  backing: NSWindow.BackingStoreType,
                  defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)

        isFloatingPanel = true
        hidesOnDeactivate = false
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isMovable = false

        collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces, .ignoresCycle, .stationary]

        isReleasedWhenClosed = false
        level = .mainMenu + 3
        hasShadow = false
    }

    // Non-activating panel: hosts controls without pulling focus off the main app.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
