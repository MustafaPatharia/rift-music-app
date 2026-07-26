// SPDX-License-Identifier: GPL-3.0-only
//
// YtDlpManager — owns the yt-dlp the app actually runs.
//
// #10 (bundle) + #11 (auto-update) are one mechanism here. Preference order:
//   1. Homebrew yt-dlp        (~0.4s startup — best)
//   2. zipimport `yt-dlp` + any local python3 (~0.5s — the no-brew fast path:
//      the 3 MB platform-independent release, run as `python3 yt-dlp …`.
//      python3 is looked up ONLY at paths that exist for real (CLT, Xcode,
//      Homebrew, python.org) — never the /usr/bin/python3 shim, which pops the
//      CLT install dialog on Macs without developer tools.)
//   3. PyInstaller onefile `yt-dlp_macos` (~13s per call — last resort so
//      playback never dies; PyInstaller re-unpacks itself every run).
// When a resolve fails (transient 500 *or* a YouTube cipher change) the player
// asks us to update(); the fix ships in a newer yt-dlp, so pulling the latest
// release self-heals the break.
//
// ponytail: no bundled baseline → first launch needs network to fetch yt-dlp.
// Fine — you can't stream from YouTube offline anyway. Add a bundled copy only if
// a true offline-first-launch story ever matters.

import Foundation

actor YtDlpManager {
    static let shared = YtDlpManager()

    // Universal2 standalone build; `latest` always points at the newest release.
    private static let downloadURL = URL(string:
        "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!
    // Platform-independent zipimport build (~3 MB, needs python3.9+) — the fast
    // no-brew path.
    private static let zipDownloadURL = URL(string:
        "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp")!
    private static let updateThrottle: TimeInterval = 6 * 3600   // don't re-pull more than this often
    private static let lastUpdateKey = "ytdlp.lastUpdate"

    private let binURL: URL           // Application Support/com.mustafapatharia.riftmusicapp/bin/yt-dlp_macos (onefile)
    private let zipURL: URL           // …/bin/yt-dlp.zip (zipimport, run via python3)
    private var inFlight: Task<Bool, Never>?   // dedup concurrent downloads (actor reentrancy)

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("com.mustafapatharia.riftmusicapp/bin", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        binURL = base.appendingPathComponent("yt-dlp")
        zipURL = base.appendingPathComponent("yt-dlp.zip")
    }

    // What a playback resolve needs; the SetupController decides how to get there.
    enum Readiness { case systemReady, brewNoYtdlp, noBrew }

    func readiness() -> Readiness {
        if Self.brewFallback() != nil { return .systemReady }
        // A local python3 makes the zipimport flavor fast (~0.5s) — no install
        // prompt needed; the zip auto-downloads on first resolve.
        if pythonPath() != nil { return .systemReady }
        return Self.brewPath() != nil ? .brewNoYtdlp : .noBrew
    }

    /// `brew install yt-dlp` (Homebrew already present). One-time ~30s, then
    /// 0.4s/call forever. No sudo — the Homebrew prefix is user-owned.
    func brewInstallYtDlp() async -> Bool {
        guard let brew = Self.brewPath() else { return false }
        Log.ytdlp.info("brew install yt-dlp…")
        let ok = await Self.run(brew, ["install", "yt-dlp"]) && Self.brewFallback() != nil
        Log.ytdlp.info("brew install yt-dlp \(ok ? "ok" : "FAILED", privacy: .public)")
        return ok
    }

    /// Install Homebrew (one native admin-password prompt) then yt-dlp, giving a
    /// no-brew Mac the fast 0.4s/call path instead of the 13s onefile.
    ///
    /// The privileged part runs via `osascript ... with administrator privileges`
    /// (Authorization Services — we never see the password): install the Xcode
    /// Command Line Tools (git, required by brew) and create a user-owned Homebrew
    /// prefix so the installer itself — which refuses to run as root — needs no
    /// further sudo.
    ///
    /// ponytail: UNTESTED on a machine without Homebrew (dev Mac already has it).
    /// The CLT softwareupdate label parse is the brittle bit — verify on a clean
    /// VM before shipping. Onefile fallback keeps playback alive if this fails.
    func bootstrapHomebrew() async -> Bool {
        let user = NSUserName()
        let prefix = Self.brewPrefix()
        let prep = """
        if ! /usr/bin/xcode-select -p >/dev/null 2>&1; then \
        /usr/bin/touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress; \
        P=$(/usr/sbin/softwareupdate -l 2>/dev/null | /usr/bin/grep -E 'Label:.*Command Line Tools' | /usr/bin/sed -E 's/.*Label: *//' | /usr/bin/tail -n1); \
        /usr/sbin/softwareupdate -i "$P"; \
        /bin/rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress; \
        fi; \
        /bin/mkdir -p \(prefix) && /usr/sbin/chown -R \(user):admin \(prefix)
        """
        Log.ytdlp.info("bootstrapping Homebrew (admin prompt)…")
        guard await Self.runAdmin(prep) else {
            Log.ytdlp.error("Homebrew prep (admin step) failed/declined")
            return false
        }
        let install = #"NONINTERACTIVE=1 /bin/bash -c "$(/usr/bin/curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#
        guard await Self.run("/bin/bash", ["-lc", install]) else {
            Log.ytdlp.error("Homebrew installer failed")
            return false
        }
        return await brewInstallYtDlp()
    }

    /// Make sure *something* runnable exists so playback never dies, even before
    /// setup finishes — zipimport when a python3 exists (fast), else the onefile.
    func ensureOnefileFallback() async { _ = await command() }

    /// The argv to run yt-dlp with, best flavor first (see file header for the
    /// preference order) — downloading on the spot if nothing exists yet so a
    /// play before setup completes still works.
    func command() async -> [String]? {
        if let sys = Self.brewFallback() { return [sys] }
        if let python = pythonPath() {
            if FileManager.default.fileExists(atPath: zipURL.path) { return [python, zipURL.path] }
            if await ensureDownloaded(flavor: .zip) { return [python, zipURL.path] }
            // zip fetch failed → fall through to onefile
        }
        if FileManager.default.isExecutableFile(atPath: binURL.path) { return [binURL.path] }
        return await ensureDownloaded(flavor: .onefile) ? [binURL.path] : nil
    }

    /// Pull the latest yt-dlp (the cipher-breakage self-heal). Throttled so a burst
    /// of transient failures doesn't re-download each time. Updates the flavor
    /// currently in use (zip when a python3 exists, else onefile); Homebrew
    /// installs are updated too when brew is the active path.
    @discardableResult
    func update(force: Bool = false) async -> Bool {
        if !force {
            let last = UserDefaults.standard.double(forKey: Self.lastUpdateKey)
            if last > 0, Date().timeIntervalSince1970 - last < Self.updateThrottle { return false }
        }
        let ok: Bool
        if Self.brewFallback() != nil, let brew = Self.brewPath() {
            let upgraded = await Self.run(brew, ["upgrade", "yt-dlp"])
            // `upgrade` exits non-zero when already newest — that's still "ok".
            ok = upgraded || Self.brewFallback() != nil
        } else if pythonPath() != nil {
            ok = await ensureDownloaded(flavor: .zip, replaceExisting: true)
        } else {
            ok = await ensureDownloaded(flavor: .onefile, replaceExisting: true)
        }
        if ok { UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastUpdateKey) }
        Log.ytdlp.info("update yt-dlp \(ok ? "ok" : "no-op/failed", privacy: .public)")
        return ok
    }

    private enum Flavor { case onefile, zip }

    /// Single in-flight download shared by all callers. `replaceExisting` forces a
    /// re-pull even when a copy is already present (update path).
    private func ensureDownloaded(flavor: Flavor, replaceExisting: Bool = false) async -> Bool {
        let dest = flavor == .zip ? zipURL : binURL
        if !replaceExisting, FileManager.default.fileExists(atPath: dest.path) { return true }
        if let t = inFlight { return await t.value }
        let t = Task { await self.performDownload(flavor: flavor) }
        inFlight = t
        let ok = await t.value
        inFlight = nil
        return ok
    }

    private func performDownload(flavor: Flavor) async -> Bool {
        let fm = FileManager.default
        let (src, dest) = flavor == .zip ? (Self.zipDownloadURL, zipURL)
                                         : (Self.downloadURL, binURL)
        let staging = dest.appendingPathExtension("new")
        do {
            let (tmp, resp) = try await URLSession.shared.download(from: src)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return false }
            try? fm.removeItem(at: staging)
            try fm.moveItem(at: tmp, to: staging)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staging.path)
            // Verify the download actually runs before trusting it — catches a
            // truncated fetch or a build that won't launch on this Mac.
            let verifyCmd: [String]
            switch flavor {
            case .onefile: verifyCmd = [staging.path]
            case .zip:
                guard let python = pythonPath() else { try? fm.removeItem(at: staging); return false }
                verifyCmd = [python, staging.path]
            }
            guard Self.runsOK(verifyCmd) else { try? fm.removeItem(at: staging); return false }
            try? fm.removeItem(at: dest)
            try fm.moveItem(at: staging, to: dest)   // atomic swap
            Log.ytdlp.info("downloaded yt-dlp (\(flavor == .zip ? "zipimport" : "onefile", privacy: .public))")
            return true
        } catch {
            try? fm.removeItem(at: staging)
            return false
        }
    }

    private static func runsOK(_ argv: [String]) -> Bool { version(argv) != nil }

    /// `yt-dlp --version` output, or nil if it doesn't run — doubles as the
    /// "is this binary actually usable" check on startup.
    private static func version(_ argv: [String]) -> String? {
        guard let exec = argv.first else { return nil }
        let out = Pipe()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exec)
        p.arguments = Array(argv.dropFirst()) + ["--version"]
        p.standardOutput = out; p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let s = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (s?.isEmpty == false) ? s : nil
    }

    /// A python3 ≥3.10 (yt-dlp's floor — CLT/Xcode ship 3.9, too old) that exists
    /// FOR REAL. Never /usr/bin/python3 — that's a shim which pops the Command
    /// Line Tools install dialog on bare Macs. Result cached: the probe spawns a
    /// process per candidate.
    private var cachedPython: String??
    private func pythonPath() -> String? {
        if let c = cachedPython { return c }
        var candidates = [
            "/opt/homebrew/bin/python3", "/usr/local/bin/python3",               // Homebrew
            "/Library/Frameworks/Python.framework/Versions/Current/bin/python3", // python.org
            "/Library/Developer/CommandLineTools/usr/bin/python3",               // CLT (3.9 today — kept for future)
            "/Applications/Xcode.app/Contents/Developer/usr/bin/python3",        // Xcode (ditto)
        ]
        // Any versioned python.org install too (Current symlink isn't always set).
        if let versions = try? FileManager.default.contentsOfDirectory(
            atPath: "/Library/Frameworks/Python.framework/Versions") {
            candidates += versions.map {
                "/Library/Frameworks/Python.framework/Versions/\($0)/bin/python3"
            }
        }
        let found = candidates.first { Self.pythonVersionOK($0) }
        cachedPython = .some(found)
        Log.ytdlp.info("python3 for zipimport: \(found ?? "none", privacy: .public)")
        return found
    }

    /// Runs `python3 --version` and checks ≥3.10.
    private static func pythonVersionOK(_ path: String) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: path) else { return false }
        let out = Pipe()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = ["--version"]
        p.standardOutput = out; p.standardError = out
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        guard p.terminationStatus == 0,
              let s = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8),
              let ver = s.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").last
        else { return false }
        let parts = ver.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else { return false }
        return parts[0] > 3 || (parts[0] == 3 && parts[1] >= 10)
    }

    /// Run an executable to completion (used for `brew install`). Async so the
    /// blocking wait runs off the actor.
    private static func run(_ path: String, _ args: [String]) async -> Bool {
        await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = args
            p.standardOutput = Pipe(); p.standardError = Pipe()
            do { try p.run() } catch { return false }
            p.waitUntilExit()
            return p.terminationStatus == 0
        }.value
    }

    private static func brewFallback() -> String? {
        ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp", "/usr/bin/yt-dlp"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func brewPath() -> String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Apple Silicon → /opt/homebrew, Intel → /usr/local.
    private static func brewPrefix() -> String {
        var u = utsname(); uname(&u)
        let machine = withUnsafeBytes(of: &u.machine) {
            String(cString: $0.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
        return machine.hasPrefix("arm") ? "/opt/homebrew" : "/usr/local"
    }

    /// Run a shell script as root via one native admin-password dialog
    /// (Authorization Services — the password never reaches our process).
    private static func runAdmin(_ script: String) async -> Bool {
        let esc = script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let osa = "do shell script \"\(esc)\" with administrator privileges"
        return await run("/usr/bin/osascript", ["-e", osa])
    }
}
