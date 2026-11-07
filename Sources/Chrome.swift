import SwiftUI
import AppKit

// MARK: - Title bar: tabs + Windows caption buttons

struct TitleBar: View {
    @ObservedObject var ex: Explorer
    @ObservedObject var menus: MenuController
    @State private var zoomed = false

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(ex.tabs.enumerated()), id: \.element.id) { idx, t in
                    TabChip(title: t.title, icon: t.location.icon,
                            active: idx == ex.active,
                            showClose: ex.tabs.count > 1 || idx == ex.active,
                            onSelect: { ex.selectTab(idx) },
                            onClose: { ex.closeTab(idx) },
                            onContext: { point in
                                menus.show(id: "tab-\(idx)-\(t.id)", anchor: .zero,
                                           entries: tabMenu(idx), width: 220,
                                           iconRow: nil, point: point)
                            },
                            onDropInto: { providers in
                                guard ex.tabs.indices.contains(idx),
                                      case .folder(let dir) = ex.tabs[idx].location else { return false }
                                return DropHandler.handle(providers: providers, into: dir, ex: ex)
                            })
                }
                WinButton(tooltip: tr("New tab (Ctrl+T)"), padding: 8, height: 28, corner: 4) {
                    ex.openTab()
                } content: {
                    Glyph(icon: .plus, size: 12, color: Win.text, weight: 1.4)
                }
                .padding(.leading, 4)
            }
            .padding(.leading, 8)

            WindowDragArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 0) {
                CaptionButton(icon: .minimize) { NSApp.keyWindow?.miniaturize(nil) }
                CaptionButton(icon: zoomed ? .restore : .maximize) {
                    NSApp.keyWindow?.zoom(nil)
                    DispatchQueue.main.async { zoomed = NSApp.keyWindow?.isZoomed ?? false }
                }
                CaptionButton(icon: .close, danger: true) { NSApp.keyWindow?.performClose(nil) }
            }
        }
        .frame(height: Win.M.tabStripHeight)
        .background(Win.tabStrip)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) { _ in
            zoomed = NSApp.keyWindow?.isZoomed ?? false
        }
    }

    /// Windows 11 gives tabs a Duplicate/Close menu; Paste to tab is the
    /// MaXplorer move — drop files into a folder you keep open elsewhere
    /// without leaving this one.
    private func tabMenu(_ i: Int) -> [MenuEntry] {
        let isFolder: Bool
        if case .folder = ex.tabs[i].location { isFolder = true } else { isFolder = false }
        return [
            MenuEntry(title: tr("Duplicate tab"), icon: .copy) { ex.duplicateTab(i) },
            MenuEntry(title: tr("Paste to tab"), icon: .paste,
                      enabled: !Clipboard.urls.isEmpty && isFolder) {
                ex.paste(toTabAt: i)
            },
            .sep(),
            MenuEntry(title: tr("Close tab"), shortcut: "Ctrl+W") { ex.closeTab(i) },
            MenuEntry(title: tr("Reopen closed tab"), shortcut: "Ctrl+Shift+T") { ex.reopenClosedTab() },
        ]
    }
}

struct TabChip: View {
    let title: String
    let icon: Icon
    let active: Bool
    let showClose: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    var onContext: (CGPoint) -> Void = { _ in }
    var onDropInto: ([NSItemProvider]) -> Bool = { _ in false }
    @State private var hovering = false
    @State private var dropTargeted = false

    var body: some View {
        HStack(spacing: 8) {
            Glyph(icon: icon, size: 15, color: active ? Win.accent : Win.textSecondary, weight: 1.2)
            Text(title)
                .font(Win.body(12))
                .foregroundStyle(active ? Win.text : Win.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if showClose && (hovering || active) {
                Button(action: onClose) {
                    Glyph(icon: .tabClose, size: 11, color: Win.textSecondary, weight: 1.3)
                        .frame(width: 20, height: 20)
                        .background(WinRR(radius: 4).fill(Win.subtleHover.opacity(0.001)))
                }
                .buttonStyle(.plain)
                .hoverFill()
                .help(tr("Close tab (Ctrl+W)"))
            } else {
                Color.clear.frame(width: 20, height: 20)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(width: 232, height: 34, alignment: .leading)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 0,
                                   bottomTrailingRadius: 0, topTrailingRadius: 8, style: .continuous)
                .fill(active ? Win.tabActive : (hovering ? Win.tabHover : Color.clear))
        )
        .overlay(alignment: .bottom) {
            if active { Rectangle().fill(Win.tabActive).frame(height: 6).offset(y: 3) }
        }
        .overlay(WinRR(radius: 6).stroke(Win.accent.opacity(dropTargeted ? 1 : 0), lineWidth: 2))
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted, perform: onDropInto)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onSelect)
        .onRightClick(perform: onContext)
    }
}

struct CaptionButton: View {
    let icon: Icon
    var danger: Bool = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Rectangle()
            .fill(hovering ? (danger ? Win.closeHover : Win.captionHover) : Color.clear)
            .frame(width: 46, height: Win.M.tabStripHeight)
            .overlay(
                Glyph(icon: icon, size: 10,
                      color: hovering && danger ? .white : Win.text, weight: 1.0)
            )
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
    }
}

// MARK: - Address bar row

struct NavBar: View {
    @ObservedObject var ex: Explorer
    @ObservedObject var menus: MenuController
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 2) {
            WinButton(tooltip: tr("Back (Alt+Left)"), enabled: ex.tab.canGoBack, padding: 9, height: 34) {
                ex.back()
            } content: { Glyph(icon: .back, size: 16, color: Win.text) }

            WinButton(tooltip: tr("Forward (Alt+Right)"), enabled: ex.tab.canGoForward, padding: 9, height: 34) {
                ex.forward()
            } content: { Glyph(icon: .forward, size: 16, color: Win.text) }

            WinButton(tooltip: tr("Up to %@ (Alt+Up)", upTitle), enabled: ex.canGoUp, padding: 9, height: 34) {
                ex.up()
            } content: { Glyph(icon: .up, size: 16, color: Win.text) }

            WinButton(tooltip: tr("Refresh (F5)"), padding: 9, height: 34) {
                ex.reload()
            } content: { Glyph(icon: .refresh, size: 16, color: Win.text) }
                .padding(.trailing, 6)

            AddressBar(ex: ex, menus: menus)

            SearchBox(ex: ex)
                .frame(minWidth: 140, idealWidth: 260, maxWidth: 260)
                .padding(.leading, 8)
        }
        .padding(.horizontal, 8)
        .frame(height: Win.M.navBarHeight)
        .background(Win.chrome)
    }

    private var upTitle: String {
        if case .folder(let u) = ex.tab.location {
            return Places.displayName(for: u.deletingLastPathComponent())
        }
        return tr("Home")
    }
}

struct AddressBar: View {
    @ObservedObject var ex: Explorer
    @ObservedObject var menus: MenuController
    @State private var hovering = false

    var body: some View {
        Group {
            if ex.addressEditing {
                HStack(spacing: 6) {
                    WinField(text: $ex.addressText, placeholder: tr("Path"),
                             fontSize: 12, selectAll: true,
                             onCommit: { s in
                                 ex.addressEditing = false
                                 ex.navigateToTypedPath(s)
                             },
                             onCancel: { ex.addressEditing = false })
                    .frame(height: 20)
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(WinRR(radius: 4).fill(Win.fieldFocus))
                .overlay(WinRR(radius: 4).stroke(Win.strokeStrong, lineWidth: 1))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Win.accent).frame(height: 2)
                        .padding(.horizontal, 1)
                }
            } else {
                HStack(spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            ForEach(Array(ex.breadcrumbs.enumerated()), id: \.element.id) { i, crumb in
                                CrumbButton(crumb: crumb, isFirst: i == 0, ex: ex, menus: menus)
                                CrumbChevron(crumb: crumb, ex: ex, menus: menus)
                            }
                        }
                        .padding(.leading, 4)
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: 32)
                .background(WinRR(radius: 4).fill(hovering ? Win.fieldHover : Win.field))
                .overlay(WinRR(radius: 4).stroke(Win.stroke, lineWidth: 1))
                .onHover { hovering = $0 }
                .contentShape(Rectangle())
                .onTapGesture {
                    ex.addressText = ex.addressPath
                    ex.addressEditing = true
                }
                .help(tr("Click to type the path (Ctrl+L)"))
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct CrumbButton: View {
    let crumb: Explorer.Crumb
    let isFirst: Bool
    @ObservedObject var ex: Explorer
    @ObservedObject var menus: MenuController

    var body: some View {
        WinButton(padding: 7, height: 26, corner: 3) {
            ex.go(to: crumb.location)
        } content: {
            HStack(spacing: 6) {
                if let icon = crumb.icon {
                    Glyph(icon: icon, size: 15,
                          color: icon == .home ? Color(red: 0.90, green: 0.49, blue: 0.13) : Win.textSecondary,
                          weight: 1.2)
                }
                Text(crumb.title)
                    .font(Win.body(12))
                    .foregroundStyle(Win.text)
                    .lineLimit(1)
            }
        }
    }
}

/// The chevron between crumbs opens that folder's sibling list, as in Explorer.
struct CrumbChevron: View {
    let crumb: Explorer.Crumb
    @ObservedObject var ex: Explorer
    @ObservedObject var menus: MenuController
    @State private var frame: CGRect = .zero

    var body: some View {
        WinButton(padding: 3, height: 26, corner: 3) {
            let children = childFolders()
            guard !children.isEmpty else { NSSound.beep(); return }
            menus.show(id: "crumb-\(crumb.id)", anchor: frame,
                       entries: children.prefix(24).map { url in
                           MenuEntry(title: Places.displayName(for: url), icon: .folderOutline) {
                               ex.go(to: url)
                           }
                       }, width: 260)
        } content: {
            Glyph(icon: .chevronRight, size: 11, color: Win.textTertiary, weight: 1.3)
        }
        .background(GeometryReader { g in
            Color.clear.onAppear { frame = g.frame(in: .named("root")) }
                .onChange(of: g.frame(in: .named("root"))) { _, f in frame = f }
        })
    }

    private func childFolders() -> [URL] {
        guard let url = crumb.location.url else {
            return [Places.desktop, Places.downloads, Places.documents, Places.pictures, Places.music, Places.videos]
        }
        return Loader.contents(of: url, showHidden: false)
            .filter { $0.isDirectory && !$0.isPackage }
            .map(\.url)
    }
}

struct SearchBox: View {
    @ObservedObject var ex: Explorer
    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField(tr("Search %@", ex.tab.location.title), text: Binding(
                get: { ex.tab.search },
                set: { ex.updateSearch($0) }
            ))
            .textFieldStyle(.plain)
            .font(Win.body(12))
            .foregroundStyle(Win.text)
            .focused($focused)
            .onSubmit { ex.updateSearch(ex.tab.search) }

            if !ex.tab.search.isEmpty {
                Button {
                    ex.updateSearch("")
                } label: {
                    Glyph(icon: .tabClose, size: 11, color: Win.textSecondary, weight: 1.2)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .hoverFill()
            }
            Glyph(icon: .search, size: 15, color: Win.textSecondary, weight: 1.2)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(WinRR(radius: 4).fill(focused ? Win.fieldFocus : (hovering ? Win.fieldHover : Win.field)))
        .overlay(WinRR(radius: 4).stroke(focused ? Win.strokeStrong : Win.stroke, lineWidth: 1))
        .overlay(alignment: .bottom) {
            if focused { Rectangle().fill(Win.accent).frame(height: 2).padding(.horizontal, 1) }
        }
        .onHover { hovering = $0 }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in focused = true }
    }
}

extension Notification.Name {
    static let focusSearch = Notification.Name("winexp.focusSearch")
}

// MARK: - Command bar

struct CommandBar: View {
    @ObservedObject var ex: Explorer
    @ObservedObject var model: WindowModel
    @ObservedObject var menus: MenuController
    @ObservedObject var prefs = Prefs.shared
    @State private var frames: [String: CGRect] = [:]

    private var hasSelection: Bool { !ex.tab.selection.isEmpty }
    private var canWrite: Bool { ex.currentDirectory != nil }

    var body: some View {
        GeometryReader { geo in
            bar(width: geo.size.width)
        }
        .frame(height: Win.M.commandBarHeight)
    }

    private func bar(width: CGFloat) -> some View {
        let roomy = width > 940
        let veryRoomy = width > 1080
        return HStack(spacing: 2) {
            WinButton(id: "cb.new", tooltip: tr("New item"), enabled: canWrite, padding: 10, height: 32) {
                menus.show(id: "new", anchor: frames["cb.new"] ?? .zero, entries: newMenu(), width: 250)
            } content: {
                HStack(spacing: 8) {
                    Glyph(icon: .newItem, size: 16, color: Win.text, weight: 1.2)
                    if roomy { Text(tr("New")).font(Win.body(12)).foregroundStyle(Win.text) }
                    Glyph(icon: .chevronDown, size: 10, color: Win.textSecondary, weight: 1.3)
                }
            }

            Sep()

            WinButton(tooltip: tr("Cut (%@)", Settings.shared.display(for: .cut) ?? ""), enabled: hasSelection, padding: 9, height: 32) {
                ex.cutSelection()
            } content: { Glyph(icon: .cut, size: 16, color: Win.text) }

            WinButton(tooltip: tr("Copy (%@)", Settings.shared.display(for: .copy) ?? ""), enabled: hasSelection, padding: 9, height: 32) {
                ex.copySelection()
            } content: { Glyph(icon: .copy, size: 16, color: Win.text) }

            WinButton(tooltip: tr("Paste (%@)", Settings.shared.display(for: .paste) ?? ""), enabled: Clipboard.hasFiles && canWrite, padding: 9, height: 32) {
                ex.paste()
            } content: { Glyph(icon: .paste, size: 16, color: Win.text) }

            WinButton(tooltip: tr("Rename (%@)", Settings.shared.display(for: .rename) ?? ""), enabled: ex.tab.selection.count == 1, padding: 9, height: 32) {
                ex.beginRename()
            } content: { Glyph(icon: .rename, size: 16, color: Win.text) }

            WinButton(tooltip: tr("Share"), enabled: hasSelection, padding: 9, height: 32) {
                shareSelection()
            } content: { Glyph(icon: .share, size: 16, color: Win.text) }

            WinButton(tooltip: tr("Delete (%@)", Settings.shared.display(for: .delete) ?? ""), enabled: hasSelection, padding: 9, height: 32) {
                ex.deleteSelection(permanent: false)
            } content: { Glyph(icon: .delete, size: 16, color: Win.text) }

            if ex.isInsideArchive || ex.selectedItems.contains(where: { Archives.isArchive($0.url) }) {
                WinButton(tooltip: tr("Extract"), padding: 9, height: 32) {
                    ex.extractSelection()
                } content: {
                    HStack(spacing: 8) {
                        Glyph(icon: .compress, size: 16, color: Win.text, weight: 1.15)
                        if roomy { Text(tr("Extract")).font(Win.body(12)).foregroundStyle(Win.text) }
                    }
                }
            }

            Sep()

            WinButton(id: "cb.sort", tooltip: tr("Sort"), padding: 10, height: 32) {
                menus.show(id: "sort", anchor: frames["cb.sort"] ?? .zero, entries: sortMenu(), width: 230)
            } content: {
                LabeledGlyph(icon: .sort, title: tr("Sort"), showLabel: roomy)
            }

            WinButton(id: "cb.view", tooltip: tr("View"), padding: 10, height: 32) {
                menus.show(id: "view", anchor: frames["cb.view"] ?? .zero, entries: viewMenu(), width: 250)
            } content: {
                LabeledGlyph(icon: .view, title: tr("View"), showLabel: roomy)
            }

            WinButton(id: "cb.filter", tooltip: tr("Filter"), padding: 10, height: 32) {
                menus.show(id: "filter", anchor: frames["cb.filter"] ?? .zero, entries: filterMenu(), width: 220)
            } content: {
                LabeledGlyph(icon: .filter, title: tr("Filter"), showLabel: roomy)
            }

            WinButton(id: "cb.more", tooltip: tr("See more"), padding: 10, height: 32) {
                menus.show(id: "more", anchor: frames["cb.more"] ?? .zero, entries: moreMenu(), width: 270)
            } content: {
                Glyph(icon: .more, size: 16, color: Win.text)
            }

            Spacer(minLength: 8)

            if prefs.showAccountStatus && veryRoomy {
                WinButton(id: "cb.account", tooltip: tr("Cloud storage status"), padding: 10, height: 32) {
                    menus.show(id: "account", anchor: frames["cb.account"] ?? .zero,
                               entries: accountMenu(), width: 300)
                } content: {
                    HStack(spacing: 8) {
                        Glyph(icon: cloudFolder == nil ? .info : .cloud, size: 16,
                              color: Win.textSecondary, weight: 1.2)
                        Text(accountLabel).font(Win.body(12)).foregroundStyle(Win.text).lineLimit(1)
                    }
                }
            }

            WinButton(tooltip: tr("Details pane (%@)", Settings.shared.display(for: .toggleDetailsPane) ?? ""),
                      active: prefs.showDetailsPane, padding: 10, height: 32) {
                prefs.showDetailsPane.toggle()
            } content: {
                HStack(spacing: 8) {
                    Glyph(icon: .detailsPane, size: 16, color: Win.text, weight: 1.15)
                    if roomy { Text(tr("Details")).font(Win.body(12)).foregroundStyle(Win.text) }
                }
            }

            WinButton(tooltip: tr("Dual pane (%@)", Settings.shared.display(for: .toggleDualPane) ?? ""),
                      active: model.dual, padding: 8, height: 32) {
                model.toggleDual()
            } content: {
                Glyph(icon: .detailsPane, size: 16, color: Win.text, weight: 1.15)
                    .rotationEffect(.degrees(180))
            }

            WinButton(id: "cb.settings", tooltip: tr("Settings"), padding: 8, height: 32) {
                ex.sheet = .settings
            } content: {
                Glyph(icon: .settings, size: 16, color: Win.textTertiary, weight: 1.1)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: Win.M.commandBarHeight)
        .background(Win.chrome)
        .overlay(alignment: .bottom) { Rectangle().fill(Win.divider).frame(height: 1) }
        .onPreferenceChange(FrameKey.self) { frames.merge($0, uniquingKeysWith: { _, b in b }) }
    }

    private func shareSelection() {
        let urls = ex.selectedItems.map(\.url)
        guard !urls.isEmpty, let window = NSApp.keyWindow else { return }
        let picker = NSSharingServicePicker(items: urls)
        let view = window.contentView ?? NSView()
        picker.show(relativeTo: NSRect(x: view.bounds.midX, y: view.bounds.maxY - 120, width: 1, height: 1),
                    of: view, preferredEdge: .minY)
    }

    // MARK: Menu definitions

    private func newMenu() -> [MenuEntry] {
        [
            MenuEntry(title: tr("Folder"), icon: .newFolder, shortcut: Settings.shared.display(for: .newFolder)) { ex.newFolder() },
            MenuEntry(title: tr("Shortcut"), icon: .link) {
                guard let dir = ex.currentDirectory else { return }
                Ops.makeShortcut(for: ex.selectedItems.map(\.url), in: dir); ex.reload()
            },
            .sep(),
            MenuEntry(title: tr("Text Document"), icon: .document) { ex.newFile(named: "New Text Document.txt") },
            MenuEntry(title: tr("Rich Text Document"), icon: .document) { ex.newFile(named: "New Rich Text Document.rtf") },
            MenuEntry(title: tr("Microsoft Word Document"), icon: .document) { ex.newFile(named: "New Microsoft Word Document.docx") },
            MenuEntry(title: tr("Microsoft Excel Worksheet"), icon: .document) { ex.newFile(named: "New Microsoft Excel Worksheet.xlsx") },
            .sep(),
            MenuEntry(title: tr("Compressed (zipped) Folder"), icon: .compress) { ex.zipSelection() },
        ]
    }

    private func sortMenu() -> [MenuEntry] {
        var entries = SortKey.allCases.map { key in
            MenuEntry(title: key.label, radio: prefs.sortKey == key) {
                prefs.sortKey = key; ex.resort()
            }
        }
        entries.append(.sep())
        entries.append(MenuEntry(title: tr("Ascending"), radio: prefs.sortAscending) {
            prefs.sortAscending = true; ex.resort()
        })
        entries.append(MenuEntry(title: tr("Descending"), radio: !prefs.sortAscending) {
            prefs.sortAscending = false; ex.resort()
        })
        entries.append(.sep())
        entries.append(MenuEntry(title: tr("Group by"), submenu: ["(None)", "Name", "Type", "Date modified", "Size"].map { key in
            MenuEntry(title: tr(key), radio: prefs.groupBy == key) {
                prefs.groupBy = key; ex.collapsedGroups.removeAll()
            }
        }))
        return entries
    }

    private func viewMenu() -> [MenuEntry] {
        var entries: [MenuEntry] = ViewMode.allCases.map { mode in
            MenuEntry(title: mode.label,
                      shortcut: Settings.shared.display(for: mode.viewCommand),
                      radio: prefs.viewMode == mode) {
                prefs.viewMode = mode
            }
        }
        entries.append(.sep())
        entries.append(MenuEntry(title: tr("Compact view"), checked: prefs.compactMode) {
            prefs.compactMode.toggle()
        })
        entries.append(.sep())
        entries.append(MenuEntry(title: tr("Show"), icon: .eye, submenu: [
            MenuEntry(title: tr("Navigation pane"), checked: prefs.showNavPane) { prefs.showNavPane.toggle() },
            MenuEntry(title: tr("Details pane"), shortcut: Settings.shared.display(for: .toggleDetailsPane), checked: prefs.showDetailsPane) { prefs.showDetailsPane.toggle() },
            MenuEntry(title: tr("Preview pane"), shortcut: Settings.shared.display(for: .togglePreviewPane), checked: prefs.showPreviewPane) { prefs.showPreviewPane.toggle() },
            .sep(),
            MenuEntry(title: tr("Item check boxes"), checked: prefs.itemCheckBoxes) { prefs.itemCheckBoxes.toggle() },
            MenuEntry(title: tr("File name extensions"), checked: prefs.showExtensions) { prefs.showExtensions.toggle() },
            MenuEntry(title: tr("Hidden items"), shortcut: Settings.shared.display(for: .toggleHidden), checked: prefs.showHidden) {
                prefs.showHidden.toggle(); ex.reload()
            },
        ]))
        return entries
    }

    private func filterMenu() -> [MenuEntry] {
        let options: [(String, String?)] = [
            (tr("All"), nil), (tr("Folders"), "folder"), (tr("Documents"), "document"),
            (tr("Images"), "image"), (tr("Videos"), "video"), (tr("Audio"), "audio"),
            (tr("Archives"), "archive"), (tr("Applications"), "app"),
        ]
        return options.map { title, key in
            MenuEntry(title: title, radio: ex.filterKind == key) {
                ex.filterKind = key; ex.reload()
            }
        }
    }

    private func moreMenu() -> [MenuEntry] {
        [
            MenuEntry(title: tr("Undo"), icon: .undo, shortcut: Settings.shared.display(for: .undo), enabled: !ex.undoStack.isEmpty) { ex.undo() },
            MenuEntry(title: tr("Redo"), icon: .redo, shortcut: Settings.shared.display(for: .redo), enabled: !ex.redoStack.isEmpty) { ex.redo() },
            .sep(),
            MenuEntry(title: tr("Select all"), icon: .selectAll, shortcut: Settings.shared.display(for: .selectAll)) { ex.selectAll() },
            MenuEntry(title: tr("Select none"), shortcut: Settings.shared.display(for: .selectNone)) { ex.selectNone() },
            MenuEntry(title: tr("Invert selection")) { ex.invertSelection() },
            .sep(),
            MenuEntry(title: tr("Show desktop"), icon: .desktop,
                      shortcut: Settings.shared.display(for: .showDesktop)) { DesktopReveal.toggle() },
            MenuEntry(title: tr("Panes"), icon: .detailsPane, submenu: [
                MenuEntry(title: tr("Dual pane"), shortcut: Settings.shared.display(for: .toggleDualPane),
                          checked: model.dual) { model.toggleDual() },
                MenuEntry(title: tr("Switch pane"), shortcut: Settings.shared.display(for: .switchPane),
                          enabled: model.dual) { model.switchPane() },
                MenuEntry(title: tr("Swap panes"), shortcut: Settings.shared.display(for: .swapPanes),
                          enabled: model.dual) { model.swapPanes() },
                .sep(),
                MenuEntry(title: tr("Copy to the other pane"), icon: .copy,
                          shortcut: Settings.shared.display(for: .copyToOtherPane),
                          enabled: model.dual) { model.sendSelection(kind: .copy) },
                MenuEntry(title: tr("Move to the other pane"), icon: .cut,
                          shortcut: Settings.shared.display(for: .moveToOtherPane),
                          enabled: model.dual) { model.sendSelection(kind: .move) },
            ]),
            MenuEntry(title: tr("Tools"), icon: .terminal, submenu: [
                MenuEntry(title: tr("Rename many items"), icon: .rename,
                          shortcut: Settings.shared.display(for: .batchRename),
                          enabled: !ex.tab.selection.isEmpty) {
                    ex.sheet = .batchRename(ex.selectedItems)
                },
                MenuEntry(title: tr("Compare and sync folders"), icon: .view) { ex.sheet = .compare },
                MenuEntry(title: tr("Extract archive"), icon: .compress,
                          enabled: ex.isInsideArchive
                              || ex.selectedItems.contains { Archives.isArchive($0.url) }) {
                    ex.extractSelection()
                },
                .sep(),
                MenuEntry(title: tr("Shelf"), icon: .compress,
                          shortcut: Settings.shared.display(for: .toggleShelf),
                          checked: prefs.showShelf) { prefs.showShelf.toggle() },
                MenuEntry(title: tr("Workspaces"), icon: .gridView) { ex.sheet = .workspaces },
                MenuEntry(title: tr("Connect to server"), icon: .network,
                          shortcut: Settings.shared.display(for: .connectServer)) {
                    ex.sheet = .connectServer
                },
            ]),
            .sep(),
            MenuEntry(title: tr("Go to"), icon: .home, submenu: [
                goEntry(tr("Home"), .goHome, .home, .home),
                .sep(),
                goEntry(tr("Desktop folder"), .goDesktop, .desktop, .folder(Places.desktop)),
                goEntry(tr("Downloads"), .goDownloads, .download, .folder(Places.downloads)),
                goEntry(tr("Documents"), .goDocuments, .document, .folder(Places.documents)),
                goEntry(tr("Pictures"), .goPictures, .picture, .folder(Places.pictures)),
                goEntry(tr("Music"), .goMusic, .music, .folder(Places.music)),
                goEntry(tr("Videos"), .goVideos, .video, .folder(Places.videos)),
                .sep(),
                goEntry(tr("This PC"), .goThisPC, .thisPC, .thisPC),
            ]),
            .sep(),
            MenuEntry(title: tr("Copy path"), icon: .copy, shortcut: Settings.shared.display(for: .copyPath)) { ex.copyPath() },
            MenuEntry(title: tr("Open in Terminal"), icon: .terminal) { openTerminal() },
            .sep(),
            MenuEntry(title: tr("Properties"), icon: .properties, shortcut: Settings.shared.display(for: .properties)) { ex.showProperties() },
            .sep(),
            MenuEntry(title: tr("Settings"), icon: .settings,
                      shortcut: Settings.shared.display(for: .openSettings)) { ex.sheet = .settings },
        ]
    }

    private func goEntry(_ title: String, _ command: Command, _ icon: Icon, _ location: Location) -> MenuEntry {
        MenuEntry(title: title, icon: icon, shortcut: Settings.shared.display(for: command)) {
            ex.go(to: location)
        }
    }

    private var cloudFolder: URL? {
        if let od = Places.oneDrive { return od }
        let iCloud = Places.home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        return FileManager.default.fileExists(atPath: iCloud.path) ? iCloud : nil
    }

    private var accountLabel: String {
        guard let cloud = cloudFolder else { return tr("Account disconnected") }
        return cloud.path.contains("CloudDocs") ? "iCloud Drive" : "OneDrive"
    }

    private func accountMenu() -> [MenuEntry] {
        var entries: [MenuEntry] = [.head(tr("Cloud storage"))]
        if let cloud = cloudFolder {
            entries.append(MenuEntry(title: tr("Open %@", accountLabel), icon: .cloud) { ex.go(to: cloud) })
            entries.append(MenuEntry(title: tr("Pin to Quick access"), icon: .pin) {
                Settings.shared.pin(cloud)
            })
        } else {
            entries.append(MenuEntry(title: tr("No cloud account is connected."), enabled: false))
            entries.append(MenuEntry(title: tr("Windows shows your Microsoft account here."), enabled: false))
            entries.append(MenuEntry(title: tr("Everything works on your local files."), enabled: false))
            entries.append(MenuEntry(title: tr("Pin a folder to Quick access…"), icon: .pin) { pinFolder() })
        }
        entries.append(.sep())
        entries.append(MenuEntry(title: tr("Hide this button"), icon: .hidden) {
            Prefs.shared.showAccountStatus = false
        })
        return entries
    }

    private func pinFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = tr("Pin")
        panel.begin { r in
            guard r == .OK, let url = panel.url else { return }
            Settings.shared.pin(url)
        }
    }

    private func openTerminal() {
        guard let dir = ex.currentDirectory else { return }
        let term = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open([dir], withApplicationAt: term,
                                configuration: NSWorkspace.OpenConfiguration())
    }
}

struct LabeledGlyph: View {
    let icon: Icon
    let title: String
    var showLabel: Bool = true
    var body: some View {
        HStack(spacing: 8) {
            Glyph(icon: icon, size: 16, color: Win.text, weight: 1.15)
            if showLabel { Text(title).font(Win.body(12)).foregroundStyle(Win.text) }
            Glyph(icon: .chevronDown, size: 10, color: Win.textSecondary, weight: 1.3)
        }
    }
}

struct Sep: View {
    var body: some View {
        Rectangle().fill(Win.divider).frame(width: 1, height: 20).padding(.horizontal, 5)
    }
}
