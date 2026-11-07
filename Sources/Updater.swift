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

    /// Automatic check: silent unless an unskipped newer release exists; throttled to once a day.
    static func checkAtLaunch() {
        let d = Store.defaults
        if let last = d.object(forKey: lastCheckKey) as? Date, Date().timeIntervalSince(last) < 86_400 { return }
        check(manual: false)
    }

    static func check(manual: Bool) {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            var tag: String?, page: URL?
            if (resp as? HTTPURLResponse)?.statusCode == 200,
               let json = (data.flatMap { try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any] {
                tag = json["tag_name"] as? String
                page = (json["html_url"] as? String).flatMap(URL.init(string:))
            }
            DispatchQueue.main.async {
                if tag != nil { Store.defaults.set(Date(), forKey: lastCheckKey) }
                guard let tag, let page else {
                    if manual { alert("Couldn't check for updates", "No release found or GitHub is unreachable.") }
                    return
                }
                if isNewer(tag, than: current) {
                    if manual || Store.defaults.string(forKey: skippedKey) != tag { offer(tag, page) }
                } else if manual {
                    alert("You're up to date", "File Explorer \(current) is the latest version.")
                }
            }
        }.resume()
    }

    private static func offer(_ tag: String, _ page: URL) {
        let a = NSAlert()
        a.messageText = "File Explorer \(tag) is available"
        a.informativeText = "You have \(current). Open the download page?"
        a.addButton(withTitle: "Download")
        a.addButton(withTitle: "Later")
        a.addButton(withTitle: "Skip This Version")
        switch a.runModal() {
        case .alertFirstButtonReturn: NSWorkspace.shared.open(page)
        case .alertThirdButtonReturn: Store.defaults.set(tag, forKey: skippedKey)
        default: break
        }
    }

    private static func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }
}
