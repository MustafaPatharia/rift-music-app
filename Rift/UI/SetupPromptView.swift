// SPDX-License-Identifier: GPL-3.0-only
//
// SetupPromptView — the onboarding sheet shown when a Mac has no Homebrew, so
// new songs would load slowly (~13s) off the standalone yt-dlp. Offers a one-time
// install (one admin-password prompt) for the fast ~0.5s path.

import SwiftUI

struct SetupPromptView: View {
    @EnvironmentObject var setup: SetupController

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "bolt.badge.clock")
                .font(.system(size: 46)).foregroundStyle(.tint)

            Text("Enable fast playback").font(.title2.bold())

            Text("For instant song loading, MY Music installs a small helper "
                 + "(yt-dlp, via Homebrew). It's a one-time setup and asks for your "
                 + "password once — just like adding to Keychain.\n\n"
                 + "Without it the app still plays, but new songs take ~13 seconds to start.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)

            switch setup.phase {
            case .installing(let msg):
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(msg).font(.callout).foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            case .failed(let msg):
                Text(msg).font(.callout).foregroundStyle(.red)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                actionButtons(installTitle: "Try Again")
            default:
                actionButtons(installTitle: "Install")
            }
        }
        .padding(32)
        .frame(width: 460)
    }

    private var isInstalling: Bool {
        if case .installing = setup.phase { return true }
        return false
    }

    @ViewBuilder private func actionButtons(installTitle: String) -> some View {
        HStack(spacing: 12) {
            GlassPillButton("Not Now") { setup.skip() }
                .disabled(isInstalling)
            GlassPillButton(installTitle, prominent: true, loading: isInstalling) {
                setup.installFastEngine()
            }
            .disabled(isInstalling)
        }
        .padding(.top, 6)
    }
}
