import SwiftUI
import AppKit

// MARK: - Locations

enum Location: Hashable {
    case home
    case gallery
    case thisPC
    case network
    /// One network host (key from `NetHost.key`): the shares it offers.
    case networkHost(String)
    case folder(URL)
    case recycleBin
    /// Browsing inside an archive: the archive file, and the path within it.
    case archive(URL, String)

    var isNetworkPage: Bool {
        switch self {
        case .network, .networkHost: return true
        default: return false
        }
    }

    var url: URL? {
        switch self {
        case .folder(let u): return u
        case .archive: return nil
        case .gallery: return Places.pictures
        case .network: return URL(fileURLWithPath: "/Volumes")
        case .recycleBin: return Places.trash
        default: return nil
        }
    }

    /// Language-independent name for the special places, for storing.
    var stableName: String {
        switch self {
        case .home: return "Home"
        case .gallery: return "Gallery"
        case .thisPC: return "This PC"
        case .network: return "Network"
        case .networkHost(let key): return "Network/" + key
        case .recycleBin: return "Recycle Bin"
        default: return title
        }
    }

    var title: String {
        switch self {
        case .home: return tr("Home")
        case .gallery: return tr("Gallery")
        case .thisPC: return tr("This PC")
        case .network: return tr("Network")
        case .networkHost(let key): return NetworkHosts.shared.name(forKey: key)
        case .recycleBin: return tr("Recycle Bin")
        case .folder(let u): return Places.displayName(for: u)
        case .archive(let archive, let inner):
            return inner.isEmpty ? archive.lastPathComponent
                                 : String(inner.split(separator: "/").last ?? "")
        }
    }

    var icon: Icon {
        switch self {
        case .home: return .home
        case .gallery: return .gallery
        case .thisPC: return .thisPC
        case .network, .networkHost: return .network
        case .recycleBin: return .recycleBin
        case .folder(let u): return Places.icon(for: u)
        case .archive: return .compress
        }
    }
}

// MARK: - Tab

struct TabState: Identifiable {
    let id = UUID()
    var history: [Location] = [.home]
    var index: Int = 0
    var items: [FileItem] = []
    var selection: Set<String> = []
    var anchor: String? = nil
    var lead: String? = nil
    var search: String = ""
    var searching: Bool = false
    var editing: String? = nil
    var scrollTarget: String? = nil

    var location: Location { history[min(index, history.count - 1)] }
    var canGoBack: Bool { index > 0 }
    var canGoForward: Bool { index < history.count - 1 }
    var title: String { location.title }
}

// MARK: - Clipboard

enum Clipboard {
    static let cutType = NSPasteboard.PasteboardType("com.winexplorer.cut")
    private(set) static var cutPaths: Set<String> = []

    static func copy(_ urls: [URL]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls as [NSPasteboardWriting])
        cutPaths = []
    }

    static func cut(_ urls: [URL]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls as [NSPasteboardWriting])
        pb.setString("1", forType: cutType)
        cutPaths = Set(urls.map(\.path))
    }

    static var urls: [URL] {
        let pb = NSPasteboard.general
        let objs = pb.readObjects(forClasses: [NSURL.self],
                                  options: [.urlReadingFileURLsOnly: true]) as? [URL]
        return objs ?? []
    }

    static var isCut: Bool { NSPasteboard.general.string(forType: cutType) == "1" }
    static var hasFiles: Bool { !urls.isEmpty }

    static func clearCut() {
        cutPaths = []
        NSPasteboard.general.clearContents()
    }
}

// MARK: - Undo

enum UndoAction {
    case rename(from: URL, to: URL)
    case move(items: [(from: URL, to: URL)])
    case create(url: URL)
    case trash(items: [(original: URL, trashed: URL)])
    case copy(created: [URL])

    var label: String {
        switch self {
        case .rename: return tr("Rename")
        case .move: return tr("Move")
        case .create: return tr("New")
        case .trash: return tr("Delete")
        case .copy: return tr("Copy")
        }
    }
}

// MARK: - File operations

/// Pending "Replace or Skip Files" question; `resolve` runs the transfer.
struct ConflictPrompt {
    let id = UUID()
    let kind: TransferJob.Kind
    let total: Int
    let clashes: [URL]
    let destination: URL
    let resolve: (TransferJob.Conflict) -> Void
}

enum Ops {
    static let fm = FileManager.default

    /// A mounted volume other than the startup disk, i.e. something Windows
    /// would offer "Eject" on.
    static func isEjectable(_ url: URL) -> Bool {
        let p = url.standardizedFileURL.path
        return p != "/" && RemoteServers.mountedVolumes().contains { $0.standardizedFileURL.path == p }
    }

    /// Windows-style conflict naming: "name - Copy", "name - Copy (2)", ...
    static func uniqueURL(for name: String, in dir: URL, copySuffix: Bool) -> URL {
        var candidate = dir.appendingPathComponent(name)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        func build(_ s: String) -> URL {
            dir.appendingPathComponent(ext.isEmpty ? s : "\(s).\(ext)")
        }
        if copySuffix {
            candidate = build("\(stem) - Copy")
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            var n = 2
            while true {
                candidate = build("\(stem) - Copy (\(n))")
                if !fm.fileExists(atPath: candidate.path) { return candidate }
                n += 1
            }
        } else {
            var n = 2
            while true {
                candidate = build("\(stem) (\(n))")
                if !fm.fileExists(atPath: candidate.path) { return candidate }
                n += 1
            }
        }
    }

    static func trash(_ urls: [URL]) -> [(original: URL, trashed: URL)] {
        var out: [(URL, URL)] = []
        for u in urls {
            var resulting: NSURL?
            do {
                try fm.trashItem(at: u, resultingItemURL: &resulting)
                if let r = resulting as URL? { out.append((u, r)) }
            } catch { NSSound.beep() }
        }
        return out
    }

    /// Deletes through a file coordinator, which iCloud Drive and other File
    /// Provider folders require; returns the first error so the caller can show it.
    @discardableResult
    static func deleteForever(_ urls: [URL]) -> Error? {
        var firstError: Error?
        for u in urls {
            var coordError: NSError?
            var removeError: Error?
            NSFileCoordinator(filePresenter: nil).coordinate(
                writingItemAt: u, options: .forDeleting, error: &coordError
            ) { target in
                do { try fm.removeItem(at: target) } catch { removeError = error }
            }
            if firstError == nil { firstError = removeError ?? coordError }
        }
        return firstError
    }

    static func newFolder(in dir: URL, name: String = tr("New folder")) throws -> URL {
        let url = uniqueURL(for: name, in: dir, copySuffix: false)
        try fm.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    static func newFile(in dir: URL, name: String, contents: Data = Data()) throws -> URL {
        let url = uniqueURL(for: name, in: dir, copySuffix: false)
        guard fm.createFile(atPath: url.path, contents: contents) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return url
    }

    static func rename(_ url: URL, to newName: String) throws -> URL {
        let dest = url.deletingLastPathComponent().appendingPathComponent(newName)
        if dest.path == url.path { return url }
        try fm.moveItem(at: url, to: dest)
        return dest
    }

    static func makeShortcut(for urls: [URL], in dir: URL) {
        for u in urls {
            let name = "\(u.deletingPathExtension().lastPathComponent) - Shortcut"
            let dest = uniqueURL(for: name, in: dir, copySuffix: false)
            try? fm.createSymbolicLink(at: dest, withDestinationURL: u)
        }
    }

    @discardableResult
    static func zip(_ urls: [URL], in dir: URL) -> URL? {
        guard let first = urls.first else { return nil }
        let base = urls.count == 1 ? first.deletingPathExtension().lastPathComponent : "Archive"
        let dest = uniqueURL(for: base + ".zip", in: dir, copySuffix: false)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        p.currentDirectoryURL = dir
        // Working inside dir, the "./" prefix stops a file whose name begins
        // with a dash from being parsed as a zip option; zip strips it again
        // when it stores the entry names.
        p.arguments = ["-r", "-q", "./" + dest.lastPathComponent]
            + urls.map { "./" + $0.lastPathComponent }
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        return p.terminationStatus == 0 ? dest : nil
    }

    static func folderSize(_ url: URL) -> (bytes: Int64, files: Int, folders: Int) {
        var bytes: Int64 = 0, files = 0, folders = 0
        let e = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                              options: [], errorHandler: { _, _ in true })
        while let u = e?.nextObject() as? URL {
            let v = try? u.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            if v?.isDirectory == true { folders += 1 }
            else { files += 1; bytes += Int64(v?.fileSize ?? 0) }
        }
        return (bytes, files, folders)
    }
}

// MARK: - Model

final class Explorer: ObservableObject {
    @Published var tabs: [TabState] = [TabState()]
    @Published var active: Int = 0
    @Published var addressEditing = false
    @Published var addressText = ""
    @Published var statusMessage: String? = nil
    @Published var recentFiles: [FileItem] = []
    @Published var undoStack: [UndoAction] = []
    @Published var redoStack: [UndoAction] = []
    @Published var sheet: SheetKind? = nil
    @Published var navExpanded: Set<String> = ["thispc"]
    @Published var filterKind: String? = nil
    @Published var collapsedGroups: Set<String> = []
    /// Tab whose remote-folder listing is running in the background; the
    /// file area overlays an hourglass while it is the one on screen.
    @Published private(set) var waitingTab: UUID? = nil
    private var waitGen = 0

    var waitingOnCurrentTab: Bool { waitingTab == tab.id }

    struct ItemGroup: Identifiable {
        let title: String
        let items: [FileItem]
        var id: String { title }
    }

    /// The items as the file area lays them out: one untitled group when
    /// grouping is off, otherwise Windows' buckets in their own order.
    var displayGroups: [ItemGroup] {
        let mode = Prefs.shared.groupBy
        let items = tab.items
        guard mode != "(None)", !items.isEmpty else { return [ItemGroup(title: "", items: items)] }
        let buckets = Dictionary(grouping: items) { Grouping.key($0, by: mode) }
        return Grouping.ordered(Set(buckets.keys), by: mode)
            .map { ItemGroup(title: $0, items: buckets[$0] ?? []) }
    }

    func toggleGroup(_ title: String) {
        if collapsedGroups.contains(title) { collapsedGroups.remove(title) }
        else { collapsedGroups.insert(title) }
    }

    enum SheetKind: Identifiable {
        case properties([FileItem])
        case confirmDelete([FileItem], permanent: Bool)
        case error(String)
        case settings
        case folderIcon(FileItem)
        case batchRename([FileItem])
        case compare
        case connectServer
        case workspaces
        case conflicts(ConflictPrompt)
        var id: String {
            switch self {
            case .properties(let i): return "props-\(i.count)-\(i.first?.id ?? "")"
            case .confirmDelete(let i, let p): return "del-\(p)-\(i.count)"
            case .error(let m): return "err-\(m)"
            case .settings: return "settings"
            case .folderIcon(let i): return "icon-\(i.id)"
            case .batchRename(let i): return "rename-\(i.count)"
            case .compare: return "compare"
            case .connectServer: return "connect"
            case .workspaces: return "workspaces"
            case .conflicts(let c): return "conflicts-\(c.id)"
            }
        }
    }

    let prefs = Prefs.shared
    /// Called whenever the user drives this pane, so the window can make it active.
    var onInteract: (() -> Void)?
    private var searchWork: DispatchWorkItem?
    private var watcher: DirectoryWatcher?

    var tab: TabState {
        get { tabs[min(active, tabs.count - 1)] }
        set { tabs[min(active, tabs.count - 1)] = newValue }
    }

    init() {
        reload()
        loadRecents()
    }

    // MARK: Loading

    func reload() {
        NavCache.clear()
        let loc = tab.location
        // Listing an archive spawns bsdtar, which can take seconds on a large
        // archive, so it runs off the main thread. So does any folder on a
        // network volume: a sleeping NAS can take over a minute to list, and
        // reading it on the main thread froze the whole window. The old
        // content stays up behind the hourglass overlay until the new
        // listing lands.
        if case .archive(let archive, let inner) = loc {
            let tabID = tab.id
            waitingTab = nil
            var t = tab
            t.items = []
            tab = t
            DispatchQueue.global(qos: .userInitiated).async {
                let children = Archives.children(of: archive, at: inner)
                DispatchQueue.main.async { self.apply(children, toTab: tabID, expecting: loc) }
            }
            return
        }
        if case .folder(let url) = loc, Loader.isRemote(url) {
            let tabID = tab.id
            let showHidden = prefs.showHidden
            waitGen += 1
            let gen = waitGen
            waitingTab = tabID
            DispatchQueue.global(qos: .userInitiated).async {
                let children = Loader.contents(of: url, showHidden: showHidden)
                DispatchQueue.main.async {
                    if self.waitingTab == tabID, gen == self.waitGen { self.waitingTab = nil }
                    self.apply(children, toTab: tabID, expecting: loc)
                }
            }
            return
        }
        waitingTab = nil
        var items: [FileItem] = []
        switch loc {
        case .home:
            items = []
        case .thisPC:
            items = Loader.volumes()
        case .gallery:
            items = Loader.contents(of: Places.pictures, showHidden: prefs.showHidden)
                .filter { $0.isDirectory || $0.kind == .image || $0.kind == .video }
        case .network, .networkHost:
            items = []  // NetworkHosts gathers its own data off the main thread
        case .recycleBin:
            items = Loader.contents(of: Places.trash, showHidden: prefs.showHidden)
        case .folder(let url):
            items = Loader.contents(of: url, showHidden: prefs.showHidden)
        case .archive:
            break  // handled above
        }
        apply(items, toTab: tab.id, expecting: loc)
    }

    /// Filters, sorts and installs a freshly listed set of items, unless the
    /// tab has moved on to another location in the meantime.
    private func apply(_ raw: [FileItem], toTab id: UUID, expecting loc: Location) {
        guard let i = tabs.firstIndex(where: { $0.id == id }), tabs[i].location == loc else { return }
        var items = raw
        if let f = filterKind { items = items.filter { matchesFilter($0, f) } }
        items = Loader.sort(items, by: prefs.sortKey, ascending: prefs.sortAscending)
        tabs[i].items = items
        tabs[i].selection = tabs[i].selection.filter { p in items.contains { $0.id == p } }
        if tabs[i].id == tab.id { watchCurrentFolder() }
    }

    private func matchesFilter(_ item: FileItem, _ filter: String) -> Bool {
        switch filter {
        case "folder": return item.isDirectory && !item.isPackage
        case "document": return [.pdf, .word, .excel, .powerpoint, .text, .code].contains(item.kind)
        case "image": return item.kind == .image
        case "video": return item.kind == .video
        case "audio": return item.kind == .audio
        case "archive": return item.kind == .archive
        case "app": return item.kind == .app || item.kind == .executable
        default: return true
        }
    }

    func resort() {
        tab.items = Loader.sort(tab.items, by: prefs.sortKey, ascending: prefs.sortAscending)
    }

    private func watchCurrentFolder() {
        watcher = nil
        // This PC and Home list mounted drives: watch /Volumes too, so a
        // USB stick pulled out while the page is open disappears instead
        // of staying as a ghost until the next navigation.
        let url = tab.location.url ?? (tab.location == .thisPC || tab.location == .home
            ? URL(fileURLWithPath: "/Volumes") : nil)
        guard let url else { return }
        watcher = DirectoryWatcher(url: url) { [weak self] in
            guard let self else { return }
            if self.tab.editing == nil && !self.tab.searching { self.reload() }
        }
    }

    func loadRecents() {
        // Skipped in tests so the scan doesn't trigger folder-access prompts.
        if ProcessInfo.processInfo.environment["WINEXP_NORECENTS"] != nil { return }
        DispatchQueue.global(qos: .utility).async {
            var pool: [FileItem] = []
            for dir in [Places.downloads, Places.desktop, Places.documents, Places.pictures] {
                pool += Loader.contents(of: dir, showHidden: false).filter { !$0.isDirectory }
            }
            let screenshots = Places.pictures.appendingPathComponent("Screenshots")
            pool += Loader.contents(of: screenshots, showHidden: false).filter { !$0.isDirectory }
            let top = pool.sorted { $0.modified > $1.modified }.prefix(20)
            DispatchQueue.main.async { self.recentFiles = Array(top) }
        }
    }

    // MARK: Navigation

    func go(to loc: Location, newTab: Bool = false) {
        onInteract?()
        if newTab { openTab(loc); return }
        var t = tab
        if t.index < t.history.count - 1 {
            t.history.removeSubrange((t.index + 1)...)
        }
        if t.history.last != loc {
            t.history.append(loc)
            t.index = t.history.count - 1
        }
        t.selection = []
        t.search = ""
        t.searching = false
        t.editing = nil
        tab = t
        reload()
        if case .folder(let u) = loc { revealInSidebar(u) }
    }

    /// Expand the navigation tree down to the parent of the folder you are
    /// looking at. Mirror that for every component of the path, under the
    /// This PC root the tree builds its ids from.
    func revealInSidebar(_ url: URL) {
        // The boot volume prefixes everything; the deepest match is the drive
        // the tree actually hangs this path under.
        guard let v = Loader.volumes().filter({ url.path.hasPrefix($0.url.path) })
                .max(by: { $0.url.path.count < $1.url.path.count }) else { return }
        var id = "thispc/\(v.name)"
        let rest = v.url.path == "/" ? Substring(url.path)
                                     : url.path.dropFirst(v.url.path.count)
        let segs = rest.split(separator: "/")
        // Only the ancestors: the folder itself opens when the user clicks its chevron.
        if !segs.isEmpty { navExpanded.insert(id) }
        for seg in segs.dropLast() {
            id += "/\(seg)"
            navExpanded.insert(id)
        }
    }

    func go(to url: URL, newTab: Bool = false) { go(to: .folder(url), newTab: newTab) }

    func duplicateTab(_ i: Int) {
        guard tabs.indices.contains(i) else { return }
        openTab(tabs[i].location)
    }

    /// Paste into another tab's folder without leaving the current one.
    /// The transfer lands through the same background queue, keeps undo in
    /// the starting pane, refreshes the destination tab even when it is not
    /// the visible one, and honours the cut marker on the clipboard.
    func paste(toTabAt i: Int) {
        guard tabs.indices.contains(i) else { NSSound.beep(); return }
        let urls = Clipboard.urls
        guard !urls.isEmpty else { NSSound.beep(); return }
        let cutting = Clipboard.isCut
        drop(toTabAt: i, urls: urls, move: cutting, clearCutOnLand: cutting)
    }

    /// A drag that lands on a tab drops its files into that tab's folder,
    /// whether or not the tab is showing. Spring-loaded tabs without the
    /// hover timer: one gesture, explicit target.
    func drop(toTabAt i: Int, urls: [URL], move: Bool, clearCutOnLand: Bool = false) {
        guard tabs.indices.contains(i), case .folder(let dir) = tabs[i].location else {
            NSSound.beep(); return
        }
        resolveConflicts(kind: move ? .move : .copy, sources: urls, in: dir) { [weak self] policy in
            self?.runTabDrop(i, dir: dir, urls: urls, move: move, conflict: policy,
                             clearCutOnLand: clearCutOnLand)
        }
    }

    private func runTabDrop(_ i: Int, dir: URL, urls: [URL], move: Bool,
                            conflict: TransferJob.Conflict, clearCutOnLand: Bool) {
        guard tabs.indices.contains(i) else { return }
        let destTab = tabs[i].id
        let destLoc = tabs[i].location
        TransferQueue.shared.enqueue(kind: move ? .move : .copy, sources: urls, to: dir, conflict: conflict) { [weak self] job in
            guard let self else { return }
            switch job.state {
            case .failed(let message):
                if !job.created.isEmpty { self.push(.copy(created: job.created)) }
                self.sheet = .error(message)
            case .finished:
                if !job.moved.isEmpty { self.push(.move(items: job.moved)) }
                if !job.created.isEmpty { self.push(.copy(created: job.created)) }
                if clearCutOnLand { Clipboard.clearCut() }
            default: break
            }
            guard let j = self.tabs.firstIndex(where: { $0.id == destTab }),
                  self.tabs[j].location == destLoc, case .folder(let u) = destLoc else { return }
            if j == self.active { self.reload() }
            else { self.apply(Loader.contents(of: u, showHidden: self.prefs.showHidden),
                              toTab: destTab, expecting: destLoc) }
        }
    }

    func back() {
        guard tab.canGoBack else { NSSound.beep(); return }
        tab.index -= 1; tab.selection = []; tab.searching = false; tab.search = ""
        reload()
    }

    func forward() {
        guard tab.canGoForward else { NSSound.beep(); return }
        tab.index += 1; tab.selection = []; tab.searching = false; tab.search = ""
        reload()
    }

    /// Jump to a point in the tab's history, like Explorer's ⌄ dropdown.
    func goHistory(_ i: Int) {
        guard tab.history.indices.contains(i), i != tab.index else { return }
        tab.index = i; tab.selection = []; tab.searching = false; tab.search = ""
        reload()
    }

    var isInsideArchive: Bool {
        if case .archive = tab.location { return true }
        return false
    }

    func up() {
        switch tab.location {
        case .archive(let archive, let inner):
            if inner.isEmpty {
                go(to: archive.deletingLastPathComponent())
            } else {
                var parts = inner.split(separator: "/").map(String.init)
                parts.removeLast()
                go(to: .archive(archive, parts.joined(separator: "/")))
            }
        case .folder(let url):
            if url.path == "/" { go(to: .thisPC) }
            else { go(to: url.deletingLastPathComponent()) }
        case .networkHost: go(to: .network)
        case .gallery, .network, .recycleBin: go(to: .home)
        case .thisPC: go(to: .home)
        case .home: NSSound.beep()
        }
    }

    var canGoUp: Bool {
        if case .home = tab.location { return false }
        return true
    }

    func open(_ item: FileItem) {
        onInteract?()
        if case .archive(let archive, let inner) = tab.location {
            let entry = inner.isEmpty ? item.name : inner + "/" + item.name
            if item.isDirectory {
                go(to: .archive(archive, entry))
            } else {
                // Extracting a single file still spawns bsdtar; keep it off
                // the main thread so the window never freezes mid-open.
                DispatchQueue.global(qos: .userInitiated).async {
                    let staged = Archives.stage(archive, entry: entry)
                    DispatchQueue.main.async {
                        if let staged {
                            NSWorkspace.shared.open(staged)
                        } else {
                            self.sheet = .error(tr("Could not extract “%@” from the archive.", item.name))
                        }
                    }
                }
            }
            return
        }
        if item.isDirectory && !item.isPackage {
            go(to: item.url)
        } else if Archives.isArchive(item.url) {
            go(to: .archive(item.url, ""))
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    // MARK: Archives

    /// Extracts the whole archive, or just the selection when browsing inside one.
    func extractSelection() {
        if case .archive(let archive, let inner) = tab.location {
            let selected = selectedItems
            let destination = Archives.extractionFolder(for: archive)
            let entries = selected.map { inner.isEmpty ? $0.name : inner + "/" + $0.name }
            runExtraction(archive, entries: entries, to: destination)
            return
        }
        guard let item = selectedItems.first(where: { Archives.isArchive($0.url) }) else {
            NSSound.beep()
            return
        }
        runExtraction(item.url, entries: [], to: Archives.extractionFolder(for: item.url))
    }

    private func runExtraction(_ archive: URL, entries: [String], to destination: URL) {
        flash(tr("Extracting %@", archive.lastPathComponent))
        DispatchQueue.global(qos: .userInitiated).async {
            let error = Archives.extract(archive, entries: entries, to: destination)
            DispatchQueue.main.async {
                if let error {
                    self.sheet = .error(tr("Could not extract the archive.\n%@", error))
                } else {
                    self.flash(tr("Extracted to %@", destination.lastPathComponent))
                    if self.currentDirectory == destination.deletingLastPathComponent() {
                        self.reload()
                    }
                }
            }
        }
    }

    func openSelection() {
        let sel = selectedItems
        if sel.count == 1 { open(sel[0]) }
        else { for i in sel where !(i.isDirectory && !i.isPackage) { NSWorkspace.shared.open(i.url) } }
    }

    // MARK: Tabs

    func openTab(_ loc: Location = .home) {
        var t = TabState()
        t.history = [loc]
        tabs.append(t)
        active = tabs.count - 1
        reload()
    }

    /// Tabs closed in this pane, newest last, for Ctrl+Shift+T.
    private var closedTabs: [TabState] = []

    func reopenClosedTab() {
        guard var t = closedTabs.popLast() else { NSSound.beep(); return }
        t.items = []; t.selection = []; t.anchor = nil; t.lead = nil
        t.search = ""; t.searching = false; t.editing = nil
        tabs.append(t)
        active = tabs.count - 1
        reload()
    }

    func closeTab(_ idx: Int) {
        guard tabs.count > 1 else {
            NSApp.keyWindow?.performClose(nil)
            return
        }
        closedTabs.append(tabs[idx])
        if closedTabs.count > 10 { closedTabs.removeFirst() }
        tabs.remove(at: idx)
        if idx < active { active -= 1 } else { active = min(active, tabs.count - 1) }
        reload()
    }

    func nextTab() { active = (active + 1) % tabs.count; reload() }
    func prevTab() { active = (active - 1 + tabs.count) % tabs.count; reload() }
    func selectTab(_ i: Int) { guard i < tabs.count else { return }; active = i; reload() }

    // MARK: Selection

    var selectedItems: [FileItem] { tab.items.filter { tab.selection.contains($0.id) } }

    func select(_ item: FileItem, extend: Bool, toggle: Bool) {
        onInteract?()
        var t = tab
        if toggle {
            if t.selection.contains(item.id) { t.selection.remove(item.id) }
            else { t.selection.insert(item.id) }
            t.anchor = item.id
        } else if extend, let anchor = t.anchor,
                  let a = t.items.firstIndex(where: { $0.id == anchor }),
                  let b = t.items.firstIndex(where: { $0.id == item.id }) {
            let range = a <= b ? a...b : b...a
            t.selection = Set(range.map { t.items[$0].id })
        } else {
            t.selection = [item.id]
            t.anchor = item.id
        }
        t.lead = item.id
        tab = t
    }

    /// Applies a rubber-band selection on top of whatever it started from.
    func applyMarquee(_ ids: Set<String>, base: Set<String>) {
        let combined = base.union(ids)
        if tab.selection != combined {
            onInteract?()
            tab.selection = combined
        }
    }

    func selectAll() { tab.selection = Set(tab.items.map(\.id)) }
    func selectNone() { tab.selection = [] }
    func invertSelection() {
        let all = Set(tab.items.map(\.id))
        tab.selection = all.subtracting(tab.selection)
    }

    /// The flat on-screen order: respects grouping and collapsed groups.
    /// Identical to `tab.items` when grouping is off.
    var visibleItems: [FileItem] {
        guard Prefs.shared.groupBy != "(None)" else { return tab.items }
        return displayGroups.flatMap { collapsedGroups.contains($0.title) ? [] : $0.items }
    }

    func moveSelection(by delta: Int, extend: Bool) {
        let shown = visibleItems
        guard !shown.isEmpty else { return }
        let current = tab.lead.flatMap { id in shown.firstIndex { $0.id == id } } ?? -1
        let next = max(0, min(shown.count - 1, current + delta))
        let item = shown[next]
        if extend { select(item, extend: true, toggle: false) }
        else { select(item, extend: false, toggle: false) }
        tab.scrollTarget = item.id
    }

    func selectFirst() {
        guard let f = visibleItems.first else { return }
        select(f, extend: false, toggle: false); tab.scrollTarget = f.id
    }

    func selectLast() {
        guard let l = visibleItems.last else { return }
        select(l, extend: false, toggle: false); tab.scrollTarget = l.id
    }

    /// Type-ahead: jump to the next item starting with the typed prefix.
    private(set) var typeAhead = ""
    private var typeAheadStamp = Date.distantPast

    /// Clears the type-ahead buffer (used when a view takes over the keyboard).
    func resetTypeAhead() {
        typeAhead = ""
        typeAheadStamp = .distantPast
    }
    func typeSelect(_ ch: String) {
        let now = Date()
        if now.timeIntervalSince(typeAheadStamp) > 1.0 { typeAhead = "" }
        typeAheadStamp = now
        typeAhead += ch.lowercased()
        if let hit = tab.items.first(where: { $0.displayName.lowercased().hasPrefix(typeAhead) }) {
            select(hit, extend: false, toggle: false)
            tab.scrollTarget = hit.id
        }
    }

    // MARK: Clipboard actions

    var currentDirectory: URL? {
        switch tab.location {
        case .folder(let u): return u
        case .archive: return nil
        case .gallery: return Places.pictures
        case .recycleBin: return Places.trash
        case .network: return URL(fileURLWithPath: "/Volumes")
        default: return nil
        }
    }

    /// Unmounts a volume; a busy one is reported the way Explorer does.
    func eject(_ url: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            do { try NSWorkspace.shared.unmountAndEjectDevice(at: url) }
            catch {
                DispatchQueue.main.async {
                    self.sheet = .error(tr("The device “%@” is currently in use. Close any programs that might be using it, and then try again.", Places.displayName(for: url)))
                }
                return
            }
            DispatchQueue.main.async { self.reload() }
        }
    }

    func copySelection() {
        let sel = selectedItems
        guard !sel.isEmpty else { return }
        Clipboard.copy(sel.map(\.url))
        flash(trp(sel.count, "%@ item copied", "%@ items copied"))
    }

    func cutSelection() {
        let sel = selectedItems
        guard !sel.isEmpty else { return }
        Clipboard.cut(sel.map(\.url))
        flash(trp(sel.count, "%@ item cut", "%@ items cut"))
    }

    func paste() {
        guard let dir = currentDirectory else { NSSound.beep(); return }
        let urls = Clipboard.urls
        guard !urls.isEmpty else { NSSound.beep(); return }
        let cutting = Clipboard.isCut
        // The cut marker is only cleared once the move has actually landed.
        // Clearing it up front meant a failed move (locked volume, permissions)
        // left the user with an empty pasteboard and no way to retry.
        transfer(kind: cutting ? .move : .copy, sources: urls, to: dir) { landed in
            if cutting && landed { Clipboard.clearCut() }
        }
    }

    /// Hands a copy or move to the background queue and folds the result into
    /// the undo stack once it lands.
    func transfer(kind: TransferJob.Kind, sources: [URL], to destination: URL,
                  onSettled: ((Bool) -> Void)? = nil) {
        resolveConflicts(kind: kind, sources: sources, in: destination) { [weak self] policy in
            self?.runTransfer(kind: kind, sources: sources, to: destination,
                              conflict: policy, onSettled: onSettled)
        }
    }

    /// Windows asks "Replace or Skip Files" when the destination already holds
    /// items with the same names. No clash, no question.
    func resolveConflicts(kind: TransferJob.Kind, sources: [URL], in destination: URL,
                          then run: @escaping (TransferJob.Conflict) -> Void) {
        let clashes = Transfers.conflicts(sources, in: destination)
        guard !clashes.isEmpty else { run(.rename); return }
        sheet = .conflicts(ConflictPrompt(kind: kind, total: sources.count, clashes: clashes,
                                          destination: destination, resolve: run))
    }

    private func runTransfer(kind: TransferJob.Kind, sources: [URL], to destination: URL,
                             conflict: TransferJob.Conflict, onSettled: ((Bool) -> Void)?) {
        TransferQueue.shared.enqueue(kind: kind, sources: sources, to: destination, conflict: conflict) { [weak self] job in
            guard let self else { return }
            var succeeded = false
            switch job.state {
            case .failed(let message):
                // A failed cross-volume move can still have left the copy
                // behind; make that copy undoable rather than untracked.
                if !job.created.isEmpty { self.push(.copy(created: job.created)) }
                self.sheet = .error(message)
            case .finished:
                succeeded = true
                if !job.moved.isEmpty { self.push(.move(items: job.moved)) }
                if !job.created.isEmpty { self.push(.copy(created: job.created)) }
            default:
                break
            }
            self.reload()
            let landed = Set((job.created + job.moved.map(\.to)).map { $0.lastPathComponent })
            if !landed.isEmpty {
                self.tab.selection = Set(self.tab.items.filter { landed.contains($0.name) }.map(\.id))
            }
            onSettled?(succeeded)
        }
    }

    func pasteShortcut() {
        guard let dir = currentDirectory else { return }
        Ops.makeShortcut(for: Clipboard.urls, in: dir)
        reload()
    }

    func copyPath() {
        let sel = selectedItems
        let paths = sel.isEmpty ? [currentDirectory?.path].compactMap { $0 } : sel.map { "\"\($0.url.path)\"" }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths.joined(separator: " "), forType: .string)
        flash(tr("Path copied"))
    }

    // MARK: Mutations

    func deleteSelection(permanent: Bool) {
        let sel = selectedItems
        guard !sel.isEmpty else { NSSound.beep(); return }
        if permanent {
            sheet = .confirmDelete(sel, permanent: true)
        } else {
            performDelete(sel, permanent: false)
        }
    }

    func performDelete(_ items: [FileItem], permanent: Bool) {
        if permanent {
            if let error = Ops.deleteForever(items.map(\.url)) {
                sheet = .error(tr("Could not delete: %@", error.localizedDescription))
            }
        } else {
            let trashed = Ops.trash(items.map(\.url))
            if !trashed.isEmpty { push(.trash(items: trashed)) }
            // Volumes without a Trash (SMB/NAS) can't recycle: like Windows,
            // offer to delete permanently instead of failing silently.
            let done = Set(trashed.map(\.original.path))
            let failed = items.filter { !done.contains($0.url.path) }
            if !failed.isEmpty { sheet = .confirmDelete(failed, permanent: true) }
        }
        tab.selection = []
        reload()
    }

    func beginRename() {
        guard let first = selectedItems.first else { NSSound.beep(); return }
        tab.editing = first.id
    }

    /// Renames one specific item. This is what a second click on an
    /// already-selected name does in Explorer and in the Finder: the click
    /// that lands on an item that is already the sole selection turns its
    /// label into an editable field instead of just re-selecting it.
    func beginRename(_ item: FileItem) {
        // The item must still be in this listing: a click can arrive after the
        // pane has navigated (double-click that opens a folder).
        guard tab.editing == nil, tab.items.contains(where: { $0.id == item.id })
        else { return }
        onInteract?()
        var t = tab
        if t.selection != [item.id] {
            t.selection = [item.id]
            t.anchor = item.id
        }
        t.lead = item.id
        t.editing = item.id
        tab = t
    }

    func commitRename(_ item: FileItem, to newName: String) {
        tab.editing = nil
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != item.name else { return }
        var final = trimmed
        // Windows keeps the extension when it is hidden in the UI.
        if !prefs.showExtensions && !item.ext.isEmpty && (trimmed as NSString).pathExtension.isEmpty {
            final = "\(trimmed).\(item.ext)"
        }
        do {
            let dest = try Ops.rename(item.url, to: final)
            push(.rename(from: item.url, to: dest))
            reload()
            tab.selection = [dest.path]
        } catch {
            sheet = .error(tr("The file name you specified is not valid or too long."))
        }
    }

    func newFolder() {
        guard let dir = currentDirectory else { NSSound.beep(); return }
        do {
            let url = try Ops.newFolder(in: dir)
            push(.create(url: url))
            reload()
            tab.selection = [url.path]
            tab.editing = url.path
            tab.scrollTarget = url.path
        } catch { sheet = .error(error.localizedDescription) }
    }

    func newFile(named name: String, contents: Data = Data()) {
        guard let dir = currentDirectory else { NSSound.beep(); return }
        do {
            let url = try Ops.newFile(in: dir, name: name, contents: contents)
            push(.create(url: url))
            reload()
            tab.selection = [url.path]
            tab.editing = url.path
        } catch { sheet = .error(error.localizedDescription) }
    }

    /// Batch renames land on the undo stack as a single step.
    func recordBatchRename(_ renames: [(from: URL, to: URL)]) {
        guard !renames.isEmpty else { return }
        push(.move(items: renames))
        flash(trp(renames.count, "Renamed %@ item", "Renamed %@ items"))
    }

    func zipSelection() {
        guard let dir = currentDirectory else { return }
        let sel = selectedItems
        guard !sel.isEmpty else { return }
        let urls = sel.map(\.url)
        // Zipping a big folder runs the system's zip to completion, so it
        // belongs on the queue, not on the main thread.
        flash(trp(sel.count, "Zipping %@ item", "Zipping %@ items"))
        DispatchQueue.global(qos: .userInitiated).async {
            let created = Ops.zip(urls, in: dir)
            DispatchQueue.main.async {
                if let created {
                    self.reload()
                    self.flash(tr("Created %@", created.lastPathComponent))
                } else {
                    self.sheet = .error(tr("Could not create the zip archive."))
                }
            }
        }
    }

    func showProperties() {
        let sel = selectedItems
        if sel.isEmpty, let dir = currentDirectory, let item = Loader.item(at: dir) {
            sheet = .properties([item])
        } else if !sel.isEmpty {
            sheet = .properties(sel)
        }
    }

    // MARK: Undo / redo

    private func push(_ a: UndoAction) {
        undoStack.append(a)
        redoStack.removeAll()
        if undoStack.count > 50 { undoStack.removeFirst() }
    }

    func undo() {
        guard let a = undoStack.popLast() else { NSSound.beep(); return }
        var failures = 0
        var redoAction: UndoAction?

        switch a {
        case .rename(let from, let to):
            if (try? Ops.rename(to, to: from.lastPathComponent)) != nil { redoAction = a }
            else { failures += 1 }
        case .move(let items):
            var reverted: [(from: URL, to: URL)] = []
            for m in items.reversed()
                where (try? Ops.fm.moveItem(at: m.to, to: m.from)) != nil {
                reverted.append(m)
            }
            failures = items.count - reverted.count
            if reverted.count == items.count { redoAction = a }
            else if !reverted.isEmpty { redoAction = .move(items: reverted) }
        case .create(let url):
            // Trash the item with everything the user put inside it, so redo
            // restores the same contents rather than recreating it empty.
            let trashed = Ops.trash([url])
            if let pair = trashed.first { redoAction = .trash(items: [pair]) }
            else { failures += 1 }
        case .trash(let items):
            var restored: [(original: URL, trashed: URL)] = []
            for i in items.reversed()
                where (try? Ops.fm.moveItem(at: i.trashed, to: i.original)) != nil {
                restored.append(i)
            }
            failures = items.count - restored.count
            if restored.count == items.count { redoAction = a }
            else if !restored.isEmpty { redoAction = .trash(items: restored) }
        case .copy(let created):
            let trashed = Ops.trash(created)
            failures = created.count - trashed.count
            if !trashed.isEmpty { redoAction = .trash(items: trashed) }
        }

        if let redoAction { redoStack.append(redoAction) }
        if failures > 0 {
            sheet = .error(trp(failures, "%@ item could not be reverted — the original path is occupied or gone.", "%@ items could not be reverted — the original path is occupied or gone."))
        }
        reloadTabsTouchedBy(a)
        flash(tr("Undo %@", a.label))
    }

    func redo() {
        guard let a = redoStack.popLast() else { NSSound.beep(); return }
        var failures = 0
        var undoAction: UndoAction?

        switch a {
        case .rename(let from, let to):
            if (try? Ops.rename(from, to: to.lastPathComponent)) != nil { undoAction = a }
            else { failures += 1 }
        case .move(let items):
            var applied: [(from: URL, to: URL)] = []
            for m in items where (try? Ops.fm.moveItem(at: m.from, to: m.to)) != nil {
                applied.append(m)
            }
            failures = items.count - applied.count
            if applied.count == items.count { undoAction = a }
            else if !applied.isEmpty { undoAction = .move(items: applied) }
        case .create(let url):
            let recreated = url.pathExtension.isEmpty
                ? (try? Ops.fm.createDirectory(at: url, withIntermediateDirectories: true)) != nil
                : Ops.fm.createFile(atPath: url.path, contents: nil)
            if recreated { undoAction = a } else { failures += 1 }
        case .trash(let items):
            let again = Ops.trash(items.map(\.original))
            failures = items.count - again.count
            if !again.isEmpty { undoAction = .trash(items: again) }
        case .copy: break
        }

        if let undoAction { undoStack.append(undoAction) }
        if failures > 0 {
            sheet = .error(trp(failures, "%@ item was not reapplied — something occupies the target now.", "%@ items were not reapplied — something occupies the target now."))
        }
        reloadTabsTouchedBy(a)
    }

    /// Undo and redo change folders the active tab may not even be showing;
    /// refresh every tab of this pane that has one of the touched folders open.
    private func reloadTabsTouchedBy(_ a: UndoAction) {
        var dirs: Set<String> = []
        func touch(_ u: URL) { dirs.insert(u.deletingLastPathComponent().standardizedFileURL.path) }
        switch a {
        case .rename(let from, let to): touch(from); touch(to)
        case .move(let items): for m in items { touch(m.from); touch(m.to) }
        case .create(let url): touch(url)
        case .trash(let items): for i in items { touch(i.original); touch(i.trashed) }
        case .copy(let created): for u in created { touch(u) }
        }
        let activeID = tab.id
        for i in tabs.indices {
            guard tabs[i].id != activeID, let u = tabs[i].location.url,
                  dirs.contains(u.standardizedFileURL.path) else { continue }
            let items = Loader.contents(of: u, showHidden: prefs.showHidden)
            apply(items, toTab: tabs[i].id, expecting: tabs[i].location)
        }
        reload()
    }

    // MARK: Search

    func updateSearch(_ text: String) {
        tab.search = text
        searchWork?.cancel()
        guard !text.isEmpty else {
            tab.searching = false
            reload()
            return
        }
        let root = currentDirectory ?? Places.home
        let showHidden = prefs.showHidden
        let key = prefs.sortKey, asc = prefs.sortAscending
        let work = DispatchWorkItem { [weak self] in
            var found: [FileItem] = []
            let needle = text.lowercased()
            let e = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: Loader.keys,
                options: showHidden ? [] : [.skipsHiddenFiles],
                errorHandler: { _, _ in true })
            var scanned = 0
            while let u = e?.nextObject() as? URL {
                scanned += 1
                if scanned > 40000 { break }
                if u.lastPathComponent.lowercased().contains(needle),
                   let item = Loader.item(at: u) {
                    found.append(item)
                    if found.count >= 1000 { break }
                }
            }
            let sorted = Loader.sort(found, by: key, ascending: asc)
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.tab.search == text else { return }
                self.tab.searching = true
                self.tab.items = sorted
                self.tab.selection = []
            }
        }
        searchWork = work
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    // MARK: Status

    func flash(_ message: String) {
        statusMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            if self?.statusMessage == message { self?.statusMessage = nil }
        }
    }

    var statusText: String {
        if let m = statusMessage { return m }
        var n = tab.items.count
        if case .home = tab.location { n = Places.quickAccess.count + recentFiles.count }
        return trp(n, "%@ item", "%@ items")
    }

    var selectionText: String? {
        let sel = selectedItems
        guard !sel.isEmpty else { return nil }
        let bytes = sel.reduce(Int64(0)) { $0 + $1.size }
        let sizePart = sel.contains(where: { $0.isDirectory }) ? "" : "  \(FileItem.friendlySize(bytes))"
        return trp(sel.count, "%@ item selected", "%@ items selected") + sizePart
    }

    // MARK: Breadcrumbs

    struct Crumb: Identifiable {
        let id = UUID()
        let title: String
        let location: Location
        let icon: Icon?
    }

    var breadcrumbs: [Crumb] {
        switch tab.location {
        case .home: return [Crumb(title: tr("Home"), location: .home, icon: .home)]
        case .thisPC: return [Crumb(title: tr("This PC"), location: .thisPC, icon: .thisPC)]
        case .gallery: return [Crumb(title: tr("Gallery"), location: .gallery, icon: .gallery)]
        case .network: return [Crumb(title: tr("Network"), location: .network, icon: .network)]
        case .networkHost:
            return [Crumb(title: tr("Network"), location: .network, icon: .network),
                    Crumb(title: tab.location.title, location: tab.location, icon: .network)]
        case .recycleBin: return [Crumb(title: tr("Recycle Bin"), location: .recycleBin, icon: .recycleBin)]
        case .archive(let archive, let inner):
            var crumbs = folderCrumbs(archive.deletingLastPathComponent())
            crumbs.append(Crumb(title: archive.lastPathComponent,
                                location: .archive(archive, ""), icon: .compress))
            var accumulated = ""
            for part in inner.split(separator: "/") {
                accumulated = accumulated.isEmpty ? String(part) : accumulated + "/" + part
                crumbs.append(Crumb(title: String(part),
                                    location: .archive(archive, accumulated), icon: nil))
            }
            return crumbs
        case .folder(let url):
            return folderCrumbs(url)
        }
    }

    private func folderCrumbs(_ url: URL) -> [Crumb] {
        var crumbs: [Crumb] = []
        var u = url
        while true {
            crumbs.insert(Crumb(title: Places.displayName(for: u), location: .folder(u),
                                icon: crumbs.isEmpty ? Places.icon(for: u) : nil), at: 0)
            if u.path == "/" || u.path == Places.home.path { break }
            let parent = u.deletingLastPathComponent()
            if parent.path == u.path { break }
            u = parent
        }
        crumbs.insert(Crumb(title: tr("This PC"), location: .thisPC, icon: .thisPC), at: 0)
        return crumbs
    }

    var addressPath: String {
        currentDirectory?.path ?? tab.location.title
    }

    func navigateToTypedPath(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        if text.hasPrefix("~") {
            text = Places.home.path + String(text.dropFirst())
        }
        let url = URL(fileURLWithPath: (text as NSString).expandingTildeInPath)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            if isDir.boolValue { go(to: url) } else { NSWorkspace.shared.open(url) }
        } else {
            sheet = .error(tr("Windows can't find '%@'. Check the spelling and try again.", raw))
        }
    }
}

// MARK: - Live folder watching

final class DirectoryWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1

    init?(url: URL, onChange: @escaping () -> Void) {
        fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let s = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        var pending = false
        s.setEventHandler {
            guard !pending else { return }
            pending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                pending = false
                onChange()
            }
        }
        s.setCancelHandler { [fd] in close(fd) }
        s.resume()
        source = s
    }

    deinit { source?.cancel() }
}
