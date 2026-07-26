// SPDX-License-Identifier: GPL-3.0-only
//
// SetupController — drives the one-time "get a fast yt-dlp" flow at launch.
//
//   system yt-dlp present         → ready, nothing to do
//   Homebrew present, no yt-dlp   → `brew install yt-dlp` silently (no prompt)
//   no Homebrew                   → prompt the user; on consent, bootstrap
//                                   Homebrew (one admin password) + yt-dlp
//
// The slow onefile is always downloaded as a fallback so playback works even if
// the user skips setup — they just get ~13s cold loads until they install.

import Foundation

@MainActor
final class SetupController: ObservableObject {
    enum Phase: Equatable {
        case checking, ready, installing(String), needsHomebrew, failed(String)
    }
    @Published private(set) var phase: Phase = .checking
    /// The onboarding sheet shows while the user hasn't yet chosen to install.
    @Published var showPrompt = false

    func start() {
        Task {
            switch await YtDlpManager.shared.readiness() {
            case .systemReady:
                phase = .ready
            case .brewNoYtdlp:
                phase = .installing("Installing yt-dlp…")
                let ok = await YtDlpManager.shared.brewInstallYtDlp()
                phase = ok ? .ready : .failed("Couldn’t install yt-dlp via Homebrew.")
            case .noBrew:
                // Keep playback alive (slow) while we ask; then prompt.
                Task { await YtDlpManager.shared.ensureOnefileFallback() }
                phase = .needsHomebrew
                showPrompt = true
            }
        }
    }

    /// User tapped Install in the prompt → bootstrap Homebrew + yt-dlp.
    func installFastEngine() {
        Task {
            phase = .installing("Installing the playback engine — you’ll be asked for your password. This can take a few minutes…")
            let ok = await YtDlpManager.shared.bootstrapHomebrew()
            phase = ok ? .ready : .failed("Install failed. The app still works, but new songs load slowly until yt-dlp is installed.")
            showPrompt = !ok   // keep the sheet up on failure so they can retry
        }
    }

    func skip() { showPrompt = false }
}
