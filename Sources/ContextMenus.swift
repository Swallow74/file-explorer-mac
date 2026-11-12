import SwiftUI
import AppKit

enum ContextMenus {

    /// The compact icon strip Windows 11 puts at the top of item context menus.
    static func iconRow(_ ex: Explorer) -> MenuIconRow {
        let hasSel = !ex.tab.selection.isEmpty
        return MenuIconRow(items: [
            (.cut,    tr("Cut"),    hasSel, { ex.cutSelection() }),
            (.copy,   tr("Copy"),   hasSel, { ex.copySelection() }),
            (.rename, tr("Rename"), ex.tab.selection.count == 1, { ex.beginRename() }),
            (.share,  tr("Share"),           hasSel, { share(ex) }),
            (.delete, tr("Delete"), hasSel, { ex.deleteSelection(permanent: false) }),
        ])
    }

    static func item(_ ex: Explorer) -> [MenuEntry] {
        let sel = ex.selectedItems
        let single = sel.count == 1
        let isFolder = single && sel[0].isDirectory && !sel[0].isPackage
        var entries: [MenuEntry] = []

        if ex.tab.location == .recycleBin {
            let urls = sel.map(\.url)
            entries.append(MenuEntry(title: tr("Restore"), icon: .undo,
                                     enabled: urls.contains { TrashLog.original(of: $0) != nil }) {
                if TrashLog.restore(urls) == 0 { NSSound.beep() }
                ex.tab.selection = []
                ex.reload()
            })
            entries.append(.sep())
        }
        entries.append(MenuEntry(title: tr("Open"), icon: .openWith, shortcut: "Enter") { ex.openSelection() })
        if isFolder {
            entries.append(MenuEntry(title: tr("Open in new tab"), icon: .plus) {
                ex.go(to: sel[0].url, newTab: true)
            })
            entries.append(MenuEntry(title: tr("Open in new window")) {
                AppState.shared.openNewWindow(at: .folder(sel[0].url))
            })
        } else if single {
            entries.append(MenuEntry(title: tr("Open with"), icon: .openWith, submenu: openWithMenu(sel[0])))
            if sel[0].isPackage {
                entries.append(MenuEntry(title: tr("Show package contents"), icon: .folderOutline) {
                    ex.go(to: sel[0].url)
                })
            }
        }
        if isFolder {
            let url = sel[0].url
            let settings = Settings.shared
            let pinned = settings.isPinned(url) && !settings.hiddenPlaces.contains(url.path)
            entries.append(.sep())
            entries.append(MenuEntry(title: pinned ? tr("Unpin from Quick access") : tr("Pin to Quick access"),
                                     icon: pinned ? .unpin : .pin) {
                if pinned { settings.unpin(url) } else { settings.pin(url) }
            })
            entries.append(MenuEntry(title: tr("Change icon…"), icon: .palette) {
                ex.sheet = .folderIcon(sel[0])
            })
        }
        if single, Ops.isEjectable(sel[0].url) {
            let url = sel[0].url
            entries.append(.sep())
            entries.append(MenuEntry(title: tr("Eject")) { ex.eject(url) })
        }
        if sel.count > 1 {
            entries.append(.sep())
            entries.append(MenuEntry(title: trp(sel.count, "Rename %@ item…", "Rename %@ items…"), icon: .rename,
                                     shortcut: Settings.shared.display(for: .batchRename)) {
                ex.sheet = .batchRename(sel)
            })
        }
        if sel.contains(where: { Archives.isArchive($0.url) }) || ex.isInsideArchive {
            entries.append(MenuEntry(title: tr("Extract here"), icon: .compress) {
                ex.extractSelection()
            })
        }
        entries.append(.sep())
        entries.append(MenuEntry(title: tr("Add to shelf"), icon: .plus) {
            Shelf.shared.add(sel.map(\.url))
            Prefs.shared.showShelf = true
        })
        if !ex.isInsideArchive, let dir = ex.currentDirectory, !Loader.isRemote(dir) {
            let urls = sel.map(\.url)
            entries.append(MenuEntry(title: tr("Tags"), icon: .palette, submenu: Tags.standard.enumerated().map { i, tag in
                MenuEntry(title: tag.name, checked: sel.allSatisfy { $0.tags.contains { Tags.label($0) == i + 1 } }) {
                    Tags.toggle(label: i + 1, on: urls)
                    ex.reload()
                }
            }))
        }
        if !ex.isInsideArchive, sel.contains(where: { !$0.isDirectory || $0.isPackage }) {
            entries.append(MenuEntry(title: "AirDrop", icon: .share) {
                NSSharingService(named: .sendViaAirDrop)?.perform(withItems: sel.map(\.url))
            })
        }
        if isFolder, !ex.isInsideArchive {
            let dir = sel[0].url
            entries.append(MenuEntry(title: tr("Paste"), icon: .paste,
                                     enabled: !Clipboard.urls.isEmpty) {
                let urls = Clipboard.urls
                guard !urls.isEmpty else { NSSound.beep(); return }
                let cutting = Clipboard.isCut
                ex.transfer(kind: cutting ? .move : .copy, sources: urls, to: dir) { landed in
                    if cutting && landed { Clipboard.clearCut() }
                }
            })
        }
        entries.append(MenuEntry(title: tr("Copy as path"), icon: .copy,
                                 shortcut: Settings.shared.display(for: .copyPath)) { ex.copyPath() })
        entries.append(MenuEntry(title: tr("Compress to ZIP file"), icon: .compress) { ex.zipSelection() })
        entries.append(MenuEntry(title: tr("Create shortcut"), icon: .link) {
            guard let dir = ex.currentDirectory else { return }
            Ops.makeShortcut(for: sel.map(\.url), in: dir); ex.reload()
        })
        entries.append(MenuEntry(title: tr("Delete permanently"), icon: .delete, shortcut: Settings.shared.display(for: .deletePermanent)) {
            ex.deleteSelection(permanent: true)
        })
        entries.append(.sep())
        entries.append(MenuEntry(title: tr("Show in Finder"), icon: .eye) {
            FileViewer.showInFinder(sel.map(\.url))
        })
        entries.append(.sep())
        entries.append(MenuEntry(title: tr("Properties"), icon: .properties, shortcut: Settings.shared.display(for: .properties)) {
            ex.showProperties()
        })
        return entries
    }

    static func background(_ ex: Explorer) -> [MenuEntry] {
        let prefs = Prefs.shared
        return [
            MenuEntry(title: tr("View"), icon: .view, submenu: ViewMode.allCases.map { m in
                MenuEntry(title: m.label, radio: prefs.viewMode == m) { prefs.viewMode = m }
            }),
            MenuEntry(title: tr("Sort by"), icon: .sort, submenu: SortKey.allCases.map { k in
                MenuEntry(title: k.label, radio: prefs.sortKey == k) {
                    prefs.sortKey = k; ex.resort()
                }
            } + [.sep(),
                 MenuEntry(title: tr("Ascending"), radio: prefs.sortAscending) { prefs.sortAscending = true; ex.resort() },
                 MenuEntry(title: tr("Descending"), radio: !prefs.sortAscending) { prefs.sortAscending = false; ex.resort() }]),
            MenuEntry(title: tr("Refresh"), icon: .refresh, shortcut: Settings.shared.display(for: .refresh)) { ex.reload() },
        ] + (ex.tab.location == .recycleBin ? [
            MenuEntry(title: tr("Empty Recycle Bin"), icon: .recycleBin, enabled: !ex.tab.items.isEmpty) {
                ex.selectAll()
                ex.deleteSelection(permanent: true)
            },
        ] : []) + [
            .sep(),
            MenuEntry(title: tr("Paste"), icon: .paste, shortcut: Settings.shared.display(for: .paste),
                      enabled: Clipboard.hasFiles && ex.currentDirectory != nil) { ex.paste() },
            MenuEntry(title: tr("Paste shortcut"), icon: .link,
                      enabled: Clipboard.hasFiles && ex.currentDirectory != nil) { ex.pasteShortcut() },
            MenuEntry(title: tr("Undo"), icon: .undo, shortcut: Settings.shared.display(for: .undo), enabled: !ex.undoStack.isEmpty) { ex.undo() },
            .sep(),
            MenuEntry(title: tr("Open in Terminal"), icon: .terminal, enabled: ex.currentDirectory != nil) {
                guard let dir = ex.currentDirectory else { return }
                NSWorkspace.shared.open([dir],
                    withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
                    configuration: NSWorkspace.OpenConfiguration())
            },
            .sep(),
            MenuEntry(title: tr("New"), icon: .newItem, enabled: ex.currentDirectory != nil, submenu: [
                MenuEntry(title: tr("Folder"), icon: .newFolder, shortcut: Settings.shared.display(for: .newFolder)) { ex.newFolder() },
                .sep(),
                MenuEntry(title: tr("Text Document"), icon: .document) { ex.newFile(named: "New Text Document.txt") },
                MenuEntry(title: tr("Rich Text Document"), icon: .document) { ex.newFile(named: "New Rich Text Document.rtf") },
            ]),
            .sep(),
            MenuEntry(title: tr("Properties"), icon: .properties,
                      shortcut: Settings.shared.display(for: .properties)) { ex.showProperties() },
            MenuEntry(title: tr("Settings"), icon: .settings,
                      shortcut: Settings.shared.display(for: .openSettings)) { ex.sheet = .settings },
        ]
    }

    private static func openWithMenu(_ item: FileItem) -> [MenuEntry] {
        let apps = NSWorkspace.shared.urlsForApplications(toOpen: item.url)
        var entries = apps.prefix(8).map { app in
            MenuEntry(title: FileManager.default.displayName(atPath: app.path)) {
                NSWorkspace.shared.open([item.url], withApplicationAt: app,
                                        configuration: NSWorkspace.OpenConfiguration())
            }
        }
        if entries.isEmpty { entries = [MenuEntry(title: tr("No apps available"), enabled: false)] }
        return entries
    }

    private static func share(_ ex: Explorer) {
        let urls = ex.selectedItems.map(\.url)
        guard !urls.isEmpty, let window = NSApp.keyWindow, let view = window.contentView else { return }
        NSSharingServicePicker(items: urls)
            .show(relativeTo: NSRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1),
                  of: view, preferredEdge: .minY)
    }
}
