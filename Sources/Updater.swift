import AppKit

/// Checks the GitHub "latest release" of the repo and offers the download page when it is newer
/// than the running build. Runs at launch (at most once a day) and from the app menu.
enum Updater {
    /// Overridable from Info.plist (key FEUpdateRepo), e.g. for forks.
    static var repo: String {
        Bundle.main.object(forInfoDictionaryKey: "FEUpdateRepo") as? String ?? "Swallow74/windows-explorer-mac"
    }
    static var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private static let lastCheckKey = "updateLastCheck"
    private static let skippedKey = "updateSkippedVersion"

    /// "v1.2.0" > "1.1" → true. Numeric, dot-separated; missing parts count as 0.
    static func isNewer(_ remote: String, than local: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let (r, l) = (parts(remote), parts(local))
        for i in 0..<max(r.count, l.count) {
            let (a, b) = (i < r.count ? r[i] : 0, i < l.count ? l[i] : 0)
            if a != b { return a > b }
        }
        return false
    }

    /// Automatic check: silent unless an unskipped newer release exists; throttled to once a day; also re-evaluated hourly while running.
    static func checkAtLaunch() {
        let d = Store.defaults
        if ProcessInfo.processInfo.environment["WINEXP_UPDATE_NOW"] == nil,
           let last = d.object(forKey: lastCheckKey) as? Date, Date().timeIntervalSince(last) < 86_400 { return }
        check(manual: false)
    }

    /// Keeps long-running sessions covered: re-evaluates hourly, the 24h throttle in checkAtLaunch decides.
    static func startPeriodicChecks() {
        Timer.scheduledTimer(withTimeInterval: 3_600, repeats: true) { _ in checkAtLaunch() }
    }

    static func check(manual: Bool) {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            var release: Release?
            if (resp as? HTTPURLResponse)?.statusCode == 200,
               let json = (data.flatMap { try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any] {
                release = Release(json)
            }
            DispatchQueue.main.async {
                if release != nil { Store.defaults.set(Date(), forKey: lastCheckKey) }
                guard let release else {
                    if manual { alert(tr("Couldn't check for updates"), tr("No release found or GitHub is unreachable.")) }
                    return
                }
                if isNewer(release.tag, than: current) {
                    if manual || Store.defaults.string(forKey: skippedKey) != release.tag { offer(release) }
                } else if manual {
                    alert(tr("You're up to date"), tr("File Explorer %@ is the latest version.", current))
                }
            }
        }.resume()
    }

    struct Release {
        let tag: String
        let page: URL
        /// The .zip asset with the app, when the release has one: enables in-app install.
        let zip: URL?

        init?(_ json: [String: Any]) {
            guard let tag = json["tag_name"] as? String,
                  let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else { return nil }
            self.tag = tag
            self.page = page
            let assets = json["assets"] as? [[String: Any]] ?? []
            zip = assets.first { ($0["name"] as? String)?.hasSuffix(".zip") == true }
                .flatMap { ($0["browser_download_url"] as? String).flatMap(URL.init(string:)) }
        }
    }

    /// The running copy can be replaced in place (not read-only, not a translocated/mounted image).
    private static var canSelfUpdate: Bool {
        let bundle = Bundle.main.bundleURL
        return bundle.pathExtension == "app"
            && FileManager.default.isWritableFile(atPath: bundle.deletingLastPathComponent().path)
    }

    private static func offer(_ r: Release) {
        let a = NSAlert()
        a.messageText = tr("File Explorer %@ is available", r.tag)
        a.informativeText = tr("You have %@.", current)
        let auto = r.zip != nil && canSelfUpdate
        if auto { a.addButton(withTitle: tr("Install and Restart")) }
        a.addButton(withTitle: tr("Download Page"))
        a.addButton(withTitle: tr("Later"))
        a.addButton(withTitle: tr("Skip This Version"))
        let base = auto ? 0 : 1   // index of "Download Page" shifts when the first button is absent
        let n = a.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + base
        switch n {
        case 0: if let zip = r.zip { install(zip, tag: r.tag, fallback: r.page) }
        case 1: NSWorkspace.shared.open(r.page)
        case 3: Store.defaults.set(r.tag, forKey: skippedKey)
        default: break
        }
    }

    /// Downloads the zip, checks it is this same app and newer, swaps the bundle once we have quit, relaunches.
    private static func install(_ zip: URL, tag: String, fallback: URL) {
        func fail(_ why: String) {
            DispatchQueue.main.async {
                alert(tr("Update failed"), tr("%@ Opening the download page instead.", why))
                NSWorkspace.shared.open(fallback)
            }
        }
        URLSession.shared.downloadTask(with: zip) { tmp, resp, err in
            guard let tmp, (resp as? HTTPURLResponse)?.statusCode == 200 else { return fail(tr("Download failed.")) }
            let fm = FileManager.default
            let work = fm.temporaryDirectory.appendingPathComponent("FileExplorerUpdate-\(UUID().uuidString)")
            let archive = work.appendingPathComponent("update.zip")
            let out = work.appendingPathComponent("x")
            do {
                try fm.createDirectory(at: out, withIntermediateDirectories: true)
                try fm.moveItem(at: tmp, to: archive)
            } catch { return fail(tr("Couldn't prepare the update.")) }
            guard run("/usr/bin/ditto", ["-x", "-k", archive.path, out.path]) == 0,
                  let app = (try? fm.contentsOfDirectory(at: out, includingPropertiesForKeys: nil))?
                      .first(where: { $0.pathExtension == "app" }),
                  let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
                  info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
                  let ver = info["CFBundleShortVersionString"] as? String, isNewer(ver, than: current),
                  run("/usr/bin/codesign", ["--verify", app.path]) == 0
            else { return fail(tr("The downloaded update didn't pass verification.")) }

            // The helper outlives us: waits for this process to exit, swaps the bundle (restoring the
            // old one if the copy fails), strips quarantine and reopens the app.
            let script = work.appendingPathComponent("swap.sh")
            let body = """
            #!/bin/bash
            while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
            BK="$4"
            if mv "$2" "$BK"; then
                if ditto "$3" "$2" && xattr -dr com.apple.quarantine "$2"; then rm -rf "$BK"
                else rm -rf "$2"; mv "$BK" "$2"; fi
            fi
            open "$2"
            rm -rf "$5"
            """
            do { try body.write(to: script, atomically: true, encoding: .utf8) } catch { return fail(tr("Couldn't prepare the update.")) }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.arguments = [script.path, String(getpid()), Bundle.main.bundlePath, app.path,
                           work.appendingPathComponent("old.app").path, work.path]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            do { try p.run() } catch { return fail(tr("Couldn't start the installer.")) }
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }.resume()
    }

    @discardableResult
    private static func run(_ tool: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run(); p.waitUntilExit() } catch { return -1 }
        return p.terminationStatus
    }

    private static func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }
}
