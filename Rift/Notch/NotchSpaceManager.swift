// SPDX-License-Identifier: GPL-3.0-only
//
// Adapted for Rift from Atoll (Ebullioscopic/Atoll), GPL-3.0, originally
// boring.notch. Trimmed Atoll's unused event-tap fields. See /NOTICE.
//
// One shared space at max absolute level that the notch window joins, so it
// renders above the menu bar and stays put across Space switches.

import Foundation

@MainActor
final class NotchSpaceManager {
    static let shared = NotchSpaceManager()
    let notchSpace: CGSSpace

    private init() {
        notchSpace = CGSSpace(level: 2147483647) // max level
    }
}
