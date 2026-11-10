import AppKit

// MARK: - Default file manager
//
// Two system switches make another app stand in for the Finder:
//   * the global `NSFileViewer` default, which NSWorkspace consults for
//     "Show in Finder" / "Reveal" requests coming from every other app;
//   * the Launch Services handler for `public.folder`, which decides who
//     opens a folder (`open ~/Documents`, a folder clicked in the Dock...).
// Both are plain per-user settings and switch back to the Finder cleanly.

enum FileViewer {
    private static let key = "NSFileViewer" as CFString
    private static let finderID = "com.apple.finder"
    static let finderURL = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")

    static var isDefault: Bool {
        let v = CFPreferencesCopyValue(key, kCFPreferencesAnyApplication,
                                       kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? String
        return v != nil && v == Bundle.main.bundleIdentifier
    }

    static func setDefault(_ on: Bool) {
        guard let id = Bundle.main.bundleIdentifier else { return }
        CFPreferencesSetValue(key, on ? id as CFString : nil, kCFPreferencesAnyApplication,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication,
                                 kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        NSWorkspace.shared.setDefaultApplication(at: on ? Bundle.main.bundleURL : finderURL,
                                                 toOpen: .folder) { _ in }
    }

    /// "Show in Finder" must reach the real Finder even while this app is the
    /// file viewer, or the request would loop straight back here.
    static func showInFinder(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        if isDefault {
            let parents = Array(Set(urls.map { $0.deletingLastPathComponent() }))
            NSWorkspace.shared.open(parents, withApplicationAt: finderURL,
                                    configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }

    /// Folders open in a tab; files are revealed (parent folder, item selected).
    static func open(_ urls: [URL]) {
        var first = true
        for url in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            let isPackage = (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage ?? false
            let folder = isDir.boolValue && !isPackage
            let target = folder ? url : url.deletingLastPathComponent()
            let ex: Explorer?
            if let active = AppState.shared.active {
                // A window still sitting on Home takes the folder; otherwise a new tab.
                active.go(to: target, newTab: !(first && active.tab.location == .home && active.tabs.count == 1))
                ex = active
            } else {
                AppState.shared.openNewWindow(at: .folder(target))
                ex = nil
            }
            first = false
            guard !folder else { continue }
            // The listing lands asynchronously; select once it is there.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                guard let ex = ex ?? AppState.shared.active,
                      ex.currentDirectory?.path == target.path else { return }
                ex.tab.selection = [url.path]
                ex.tab.lead = url.path
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.keyWindow?.makeKeyAndOrderFront(nil)
    }

    /// NSWorkspace sends the designated file viewer the same event it sends
    /// the Finder for a reveal: `misc`/`mvis` with a list of files.
    static func installRevealHandler(_ target: AppDelegate) {
        NSAppleEventManager.shared().setEventHandler(
            target, andSelector: #selector(AppDelegate.handleReveal(_:reply:)),
            forEventClass: AEEventClass(0x6D697363) /* misc */, andEventID: AEEventID(0x6D766973) /* mvis */)
    }

    static func urls(from event: NSAppleEventDescriptor) -> [URL] {
        guard let direct = event.paramDescriptor(forKeyword: keyDirectObject) else { return [] }
        let list = direct.descriptorType == typeAEList
            ? (1...max(1, direct.numberOfItems)).compactMap { direct.atIndex($0) } : [direct]
        return list.compactMap { d in
            if let u = d.coerce(toDescriptorType: typeFileURL),
               let s = String(data: u.data, encoding: .utf8) { return URL(string: s) }
            return d.stringValue.map { URL(fileURLWithPath: $0) }
        }
    }
}

extension AppDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        openedFromEvent = true
        FileViewer.open(urls.filter(\.isFileURL))
    }

    @objc func handleReveal(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        openedFromEvent = true
        FileViewer.open(FileViewer.urls(from: event))
    }
}

// MARK: - Finder tags

enum Tags {
    private static let attr = "com.apple.metadata:_kMDItemUserTags"
    /// Label numbers 1-7 under their English names, which is how tags set
    /// from scripts and other systems arrive.
    private static let english = ["Gray", "Green", "Purple", "Blue", "Yellow", "Red", "Orange"]

    /// The seven Finder colours, under the names this Mac shows for them.
    /// Index 0 is "None" and is dropped, so `standard[i]` is label `i + 1`.
    static var standard: [(name: String, color: NSColor)] {
        let ws = NSWorkspace.shared
        return Array(zip(ws.fileLabels, ws.fileLabelColors).dropFirst())
    }

    /// Tags are stored as "Name\n<label number>"; 0 means "no colour of its
    /// own", which the Finder then resolves by name.
    static func name(_ raw: String) -> String {
        String(raw.split(separator: "\n", maxSplits: 1).first ?? "")
    }

    static func label(_ raw: String) -> Int {
        let parts = raw.split(separator: "\n")
        if parts.count == 2, let n = Int(parts[1]), (1...7).contains(n) { return n }
        let n = name(raw)
        if let i = standard.firstIndex(where: { $0.name == n }) { return i + 1 }
        return (english.firstIndex(of: n) ?? -1) + 1
    }

    static func color(_ raw: String) -> NSColor? {
        let n = label(raw), colors = NSWorkspace.shared.fileLabelColors
        return n > 0 && n < colors.count ? colors[n] : nil
    }

    /// Straight from the extended attribute: one small read, no metadata server.
    static func read(_ url: URL) -> [String] {
        let size = getxattr(url.path, attr, nil, 0, 0, 0)
        guard size > 0 else { return [] }
        var data = Data(count: size)
        let got = data.withUnsafeMutableBytes { getxattr(url.path, attr, $0.baseAddress, size, 0, 0) }
        guard got == size else { return [] }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String] ?? []
    }

    /// Written the way the Finder writes it: `setResourceValue(.tagNamesKey)`
    /// would drop the colour number.
    static func write(_ raws: [String], to url: URL) {
        guard !raws.isEmpty,
              let data = try? PropertyListSerialization.data(fromPropertyList: raws, format: .binary, options: 0)
        else { removexattr(url.path, attr, 0); return }
        _ = data.withUnsafeBytes { setxattr(url.path, attr, $0.baseAddress, data.count, 0, 0) }
    }

    /// Adds the standard tag `label` (1-7) to every URL, or removes it when
    /// they all carry it already.
    static func toggle(label n: Int, on urls: [URL]) {
        guard (1...7).contains(n) else { return }
        let current = urls.map { read($0) }
        let remove = current.allSatisfy { $0.contains { label($0) == n } }
        for (url, raws) in zip(urls, current) {
            if remove { write(raws.filter { label($0) != n }, to: url) }
            else if !raws.contains(where: { label($0) == n }) {
                write(raws + ["\(standard[n - 1].name)\n\(n)"], to: url)
            }
        }
    }
}

// MARK: - Recycle Bin: where things came from
//
// The Finder keeps "Put Back" locations in a private store, so the app keeps
// its own for whatever it sends to the Trash.

enum TrashLog {
    private static var storeURL: URL {
        CustomCommands.storeURL.deletingLastPathComponent().appendingPathComponent("trash.json")
    }

    private static func load() -> [String: String] {
        guard let data = try? Data(contentsOf: storeURL),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return map
    }

    private static func save(_ map: [String: String]) {
        // Entries whose file left the Trash some other way are dead weight.
        let live = map.filter { FileManager.default.fileExists(atPath: $0.key) }
        try? JSONEncoder().encode(live).write(to: storeURL, options: .atomic)
    }

    static func record(_ pairs: [(original: URL, trashed: URL)]) {
        guard !pairs.isEmpty else { return }
        var map = load()
        for p in pairs { map[p.trashed.path] = p.original.path }
        save(map)
    }

    static func original(of trashed: URL) -> URL? {
        load()[trashed.path].map { URL(fileURLWithPath: $0) }
    }

    /// Moves each item back where it was trashed from; returns how many made it.
    @discardableResult
    static func restore(_ urls: [URL]) -> Int {
        var map = load()
        var done = 0
        for u in urls {
            guard let path = map[u.path] else { continue }
            let dest = URL(fileURLWithPath: path)
            try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            if (try? FileManager.default.moveItem(at: u, to: dest)) != nil {
                map[u.path] = nil
                done += 1
            }
        }
        save(map)
        return done
    }
}

// MARK: - Spotlight

enum Spotlight {
    /// Files under `root` whose name or text content contains `text`, from
    /// the system index. Empty on network volumes and wherever Spotlight has
    /// no index; blocking, so call it off the main thread.
    static func find(_ text: String, in root: URL, limit: Int = 1000) -> [URL] {
        // Short needles match half the disk: leave those to the name walk.
        guard text.count >= 3, !Loader.isRemote(root) else { return [] }
        let needle = text.replacingOccurrences(of: "\\", with: "\\\\")
                         .replacingOccurrences(of: "\"", with: "\\\"")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        p.arguments = ["-onlyin", root.path,
                       "kMDItemFSName == \"*\(needle)*\"cd || kMDItemTextContent == \"\(needle)*\"cd"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        // mdfind keeps no live query open, so reading to EOF ends with it.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").prefix(limit)
            .map { URL(fileURLWithPath: String($0)) }
    }
}
