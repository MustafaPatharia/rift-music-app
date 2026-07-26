// SPDX-License-Identifier: GPL-3.0-only
//
// MenuBarController — the always-available fallback (and first-class option on
// notch Macs). An NSStatusItem whose click toggles a popover hosting the shared
// CompactPlayerView. install()/remove() are driven by AppModeController.

import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let player: PlayerController
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var sub: AnyCancellable?

    init(player: PlayerController) {
        self.player = player
        super.init()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: CompactPlayerView().environmentObject(player))
        // Live status-item title: track title while something's loaded.
        // objectWillChange fires BEFORE the change lands — hop the runloop so
        // refresh reads the new values.
        sub = player.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refreshTitle() }
        }
    }

    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "MY Music")
        item.button?.imagePosition = .imageLeading
        item.button?.action = #selector(toggle)
        item.button?.target = self
        statusItem = item
        refreshTitle()
    }

    private func refreshTitle() {
        guard let button = statusItem?.button else { return }
        if let t = player.track {
            var title = t.title
            if title.count > 24 { title = String(title.prefix(23)) + "…" }
            button.title = " " + title
            button.image = NSImage(
                systemSymbolName: player.isPlaying ? "waveform" : "pause.fill",
                accessibilityDescription: "MY Music")
        } else {
            button.title = ""
            button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "MY Music")
        }
    }

    func remove() {
        if popover.isShown { popover.performClose(nil) }
        if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
        statusItem = nil
    }

    @objc private func toggle() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
