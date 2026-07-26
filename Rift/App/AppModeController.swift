// SPDX-License-Identifier: GPL-3.0-only
//
// AppModeController — the notch / menu-bar / both setting. Persisted in
// UserDefaults. `onChange` lets the AppDelegate re-apply window visibility when
// the user flips the setting. Pure state; no AppKit here.

import Foundation

@MainActor
final class AppModeController: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case notch, menuBar, both
        var id: String { rawValue }
        var label: String {
            switch self {
            case .notch:   return "Notch (dynamic island)"
            case .menuBar: return "Menu bar"
            case .both:    return "Both"
            }
        }
    }

    private let key = "appDisplayMode"

    @Published var mode: Mode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: key)
            onChange?(mode)
        }
    }

    /// Set by the AppDelegate; fired on every change (already on the main actor).
    var onChange: ((Mode) -> Void)?

    init() {
        let stored = UserDefaults.standard.string(forKey: key)
        mode = stored.flatMap(Mode.init(rawValue:)) ?? .both
    }
}
