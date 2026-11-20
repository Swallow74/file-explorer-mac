import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension UTType {
    /// Payload of a Quick access entry dragged to a new position in the pane.
    /// A private type, so it never mixes with the file drags that move items
    /// into a folder.
    static let quickAccess = UTType(exportedAs: "com.winexplorer.mac.quick-access",
                                    conformingTo: .data)
}

/// Lets a Quick access entry be dragged to a new position in the pane.
struct QuickAccessDrag: ViewModifier {
    let path: String?

    func body(content: Content) -> some View {
        if let path {
            content.onDrag {
                let provider = NSItemProvider()
                provider.registerDataRepresentation(forTypeIdentifier: UTType.quickAccess.identifier,
                                                   visibility: .ownProcess) { completion in
                    completion(Data(path.utf8), nil)
                    return nil
                }
                return provider
            }
        } else {
            content
        }
    }
}

struct NavNode: Identifiable {
    let id: String
    let title: String
    let icon: Icon
    let accent: PlaceAccent
    let location: Location?
    let url: URL?
    let level: Int
    let expandable: Bool
    let pinned: Bool
    let spacerAbove: Bool
}

/// The navigation pane re-evaluates on every selection or hover change; reading
/// each expanded folder from disk every time made large folders stutter.
/// Short-lived cache, dropped on every reload.
enum NavCache {
    private static var dirs: [String: (at: Date, items: [FileItem])] = [:]
    private static var volumes: (at: Date, items: [FileItem])?
    private static let ttl: TimeInterval = 5

    static func folders(in url: URL, showHidden: Bool) -> [FileItem] {
        let key = "\(showHidden):\(url.path)"
        if let hit = dirs[key], Date().timeIntervalSince(hit.at) < ttl { return hit.items }
        let items = Loader.contents(of: url, showHidden: showHidden).filter { $0.isDirectory && !$0.isPackage }
        dirs[key] = (Date(), items)
        return items
    }

    static func mounted() -> [FileItem] {
        if let v = volumes, Date().timeIntervalSince(v.at) < ttl { return v.items }
        let items = Loader.volumes()
        volumes = (Date(), items)
        return items
    }

    static func clear() { dirs.removeAll(); volumes = nil }
}

struct NavPane: View {
    @ObservedObject var ex: Explorer
    @ObservedObject var menus: MenuController
    @ObservedObject private var settings = Settings.shared   // pins/unpins redraw the list
    @State private var hoverID: String?
    @State private var pinTargeted = false

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(nodes) { node in
                    if node.spacerAbove { Color.clear.frame(height: 10) }
                    NavRow(node: node, ex: ex, menus: menus,
                           selected: isSelected(node),
                           expanded: ex.navExpanded.contains(node.id))
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
        }
        .scrollIndicators(.automatic)
        .frame(maxHeight: .infinity)
        .background(Win.sidebar)
        // Like the Finder: a folder dropped on the pane (not on a row, which
        // moves files into it) is added to the favourites.
        .dropHighlight(pinTargeted)
        .onDrop(of: [.fileURL], isTargeted: $pinTargeted) { providers in
            DropHandler.pinFolders(providers)
        }
    }

    private func isSelected(_ node: NavNode) -> Bool {
        guard let loc = node.location else { return false }
        return loc == ex.tab.location
    }

    private var nodes: [NavNode] {
        var out: [NavNode] = []
        let places = Places.sidebar

        func children(of url: URL, level: Int, parentID: String) {
            let dirs = NavCache.folders(in: url, showHidden: Prefs.shared.showHidden)
            for d in dirs.prefix(60) {
                let id = "\(parentID)/\(d.name)"
                out.append(NavNode(id: id, title: d.name, icon: .folderOutline, accent: .neutral,
                                   location: .folder(d.url), url: d.url, level: level,
                                   expandable: true, pinned: false, spacerAbove: false))
                if ex.navExpanded.contains(id) { children(of: d.url, level: level + 1, parentID: id) }
            }
        }

        for (i, p) in places.enumerated() {
            let loc: Location? = {
                switch p.special {
                case .home: return .home
                case .gallery: return .gallery
                case .thisPC: return .thisPC
                case .network: return .network
                case .recycleBin: return .recycleBin
                case nil: return p.url.map { .folder($0) }
                }
            }()
            // The favourites are separated from Home and Gallery, and This PC
            // from them: the gap belongs to the first favourite, wherever the
            // user dragged it, and to This PC.
            let spacer = p.id == "thispc" || p.id == Places.favouritesHeaderID
            out.append(NavNode(id: p.id, title: p.title, icon: p.icon, accent: p.accent,
                               location: loc, url: p.url, level: 0,
                               expandable: p.special != .home && p.special != .network,
                               pinned: Places.isFavourite(p),
                               spacerAbove: spacer && i > 0))
            if ex.navExpanded.contains(p.id) {
                if p.special == .thisPC {
                    for v in NavCache.mounted() {
                        let id = "thispc/\(v.name)"
                        out.append(NavNode(id: id, title: Places.displayName(for: v.url), icon: .drive,
                                           accent: .neutral, location: .folder(v.url), url: v.url,
                                           level: 1, expandable: true, pinned: false, spacerAbove: false))
                        if ex.navExpanded.contains(id) { children(of: v.url, level: 2, parentID: id) }
                    }
                } else if let u = p.url {
                    children(of: u, level: 1, parentID: p.id)
                }
            }
        }
        return out
    }
}

struct NavRow: View {
    let node: NavNode
    @ObservedObject var ex: Explorer
    @ObservedObject var menus: MenuController
    let selected: Bool
    let expanded: Bool
    @State private var hovering = false
    @State private var dropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            // Expander chevron
            Group {
                if node.expandable {
                    Button {
                        if expanded { ex.navExpanded.remove(node.id) }
                        else { ex.navExpanded.insert(node.id) }
                    } label: {
                        Glyph(icon: expanded ? .chevronDown : .chevronRight,
                              size: 11, color: Win.textSecondary, weight: 1.3)
                            .frame(width: 20, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity(hovering || expanded || selected ? 1 : 0.0)
                } else {
                    Color.clear.frame(width: 20, height: 22)
                }
            }
            .padding(.leading, CGFloat(node.level) * 14)

            if let url = node.url, Settings.shared.style(for: url) != nil {
                FolderGlyph(url: url, size: 16)
            } else if node.icon == .folderOutline {
                FolderIcon(size: 16)
            } else {
                PlaceIcon(place: Place(id: node.id, title: node.title, icon: node.icon,
                                       url: node.url, accent: node.accent), size: 16)
            }

            Text(node.title)
                .font(Win.body(12))
                .foregroundStyle(Win.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, 8)

            Spacer(minLength: 4)

            if node.pinned {
                Glyph(icon: .pin, size: 12, color: Win.textTertiary, weight: 1.2)
                    .padding(.trailing, 6)
            }
        }
        .frame(height: 30)
        .padding(.leading, 4)
        .background(
            WinRR(radius: 4)
                .fill(selected ? Win.selected : (hovering ? Win.subtleHover : .clear))
        )
        .overlay(alignment: .leading) {
            if selected {
                Capsule().fill(Win.accent)
                    .frame(width: 3, height: 16)
                    .padding(.leading, 1)
            }
        }
        .dropHighlight(dropTargeted)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            if let loc = node.location { ex.go(to: loc) }
        }
        .modifier(QuickAccessDrag(path: node.pinned ? node.url?.path : nil))
        .onDrop(of: [.fileURL, .quickAccess], isTargeted: node.url != nil ? $dropTargeted : nil) { providers in
            // A Quick access entry dropped on another one takes its place.
            if let p = DropHandler.quickAccessProvider(providers) {
                DropHandler.quickAccessPath(from: p) { from in
                    guard let to = node.url?.path else { return }
                    Settings.shared.moveQuickAccess(from: from, to: to)
                }
                return true
            }
            guard let dest = node.url else { return false }
            dropTargeted = false
            return DropHandler.handle(providers: providers, into: dest, ex: ex)
        }
        .onRightClick { p in
            menus.show(id: "nav-\(node.id)", anchor: .zero, entries: menuEntries(), width: 250, point: p)
        }
    }

    private func menuEntries() -> [MenuEntry] {
        var entries: [MenuEntry] = []
        if let loc = node.location {
            entries.append(MenuEntry(title: tr("Open"), icon: .openWith) { ex.go(to: loc) })
            entries.append(MenuEntry(title: tr("Open in new tab"), icon: .plus) { ex.go(to: loc, newTab: true) })
            entries.append(MenuEntry(title: tr("Open in new window")) { AppState.shared.openNewWindow(at: loc) })
        }
        guard let url = node.url else { return entries }
        if Ops.isEjectable(url) {
            entries.append(MenuEntry(title: tr("Eject")) { ex.eject(url) })
        }
        let settings = Settings.shared
        let pinned = settings.isPinned(url) && !settings.hiddenPlaces.contains(url.path)
        entries.append(.sep())
        entries.append(MenuEntry(title: pinned ? tr("Unpin from Quick access") : tr("Pin to Quick access"),
                                 icon: pinned ? .unpin : .pin) {
            if pinned { settings.unpin(url) } else { settings.pin(url) }
        })
        // Only the Quick access entries can be moved around.
        if node.pinned, let index = Places.quickAccess.firstIndex(where: { $0.url?.path == url.path }) {
            let last = Places.quickAccess.count - 1
            entries.append(.sep())
            entries.append(MenuEntry(title: tr("Move up"), enabled: index > 0) {
                settings.moveQuickAccess(url.path, by: -1)
            })
            entries.append(MenuEntry(title: tr("Move down"), enabled: index < last) {
                settings.moveQuickAccess(url.path, by: 1)
            })
        }
        entries.append(MenuEntry(title: tr("Change icon…"), icon: .palette) {
            if let i = Loader.item(at: url) { ex.sheet = .folderIcon(i) }
        })
        entries.append(.sep())
        entries.append(MenuEntry(title: tr("Copy as path"), icon: .copy) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.path, forType: .string)
        })
        entries.append(MenuEntry(title: tr("Properties"), icon: .properties) {
            if let i = Loader.item(at: url) { ex.sheet = .properties([i]) }
        })
        return entries
    }
}

// MARK: - Shared drop handling

enum DropHandler {
    /// Adds the dropped folders to Quick access (the sidebar favourites).
    static func pinFolders(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for p in providers where p.canLoadObject(ofClass: URL.self) {
            accepted = true
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { pinIfFolder(url) }
            }
        }
        return accepted
    }

    static func pinIfFolder(_ url: URL) {
        guard url.isFileURL,
              (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        else { return }
        Settings.shared.pin(url)
    }

    /// True when the drag carries a Quick access entry rather than files.
    static func isQuickAccessDrag(_ providers: [NSItemProvider]) -> Bool {
        quickAccessProvider(providers) != nil
    }

    /// The Quick access entry carried by a drag, if there is one.
    static func quickAccessProvider(_ providers: [NSItemProvider]) -> NSItemProvider? {
        providers.first { $0.hasItemConformingToTypeIdentifier(UTType.quickAccess.identifier) }
    }

    /// Hands the dragged path back on the main queue, ready to reorder the list.
    static func quickAccessPath(from provider: NSItemProvider, _ body: @escaping (String) -> Void) {
        provider.loadDataRepresentation(forTypeIdentifier: UTType.quickAccess.identifier) { data, _ in
            guard let data, let path = quickAccessPath(from: data) else { return }
            DispatchQueue.main.async { body(path) }
        }
    }

    /// The path carried by a Quick access drag payload.
    static func quickAccessPath(from data: Data) -> String? {
        String(data: data, encoding: .utf8)
    }

    static func handle(providers: [NSItemProvider], into dest: URL, ex: Explorer) -> Bool {
        let group = DispatchGroup()
        var urls: [URL] = []
        // The loadObject completions arrive on arbitrary background queues,
        // possibly at the same time, so appends go through a lock.
        let collect = NSLock()
        for p in providers where p.canLoadObject(ofClass: URL.self) {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.isFileURL { collect.withLock { urls.append(url) } }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            guard !urls.isEmpty else { return }
            // Dropping a folder onto itself or into its own subtree would loop.
            let valid = urls.filter { !dest.path.hasPrefix($0.path + "/") && $0.path != dest.path }
            guard !valid.isEmpty else { NSSound.beep(); return }
            let flags = NSEvent.modifierFlags
            // Windows: Ctrl forces copy, Shift forces move; otherwise move within a
            // volume and copy across volumes.
            let forceCopy = flags.contains(.control) || flags.contains(.option)
            let forceMove = flags.contains(.shift) || flags.contains(.command)
            let sameVolume = valid.allSatisfy { volumeID(of: $0) == volumeID(of: dest) }
            let kind: TransferJob.Kind =
                (forceCopy || (!forceMove && !sameVolume)) ? .copy : .move
            ex.transfer(kind: kind, sources: valid, to: dest)
        }
        return true
    }

    private static func volumeID(of url: URL) -> String {
        (try? url.resourceValues(forKeys: [.volumeIdentifierKey]))
            .flatMap { $0.volumeIdentifier as? NSObject }?.description ?? ""
    }
}
