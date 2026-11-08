import Foundation
import AppKit
import UniformTypeIdentifiers

// MARK: - File kinds (drive the icon + type-name columns)

enum FileKind {
    case folder, drive, app, image, video, audio, pdf, word, excel, powerpoint
    case text, code, archive, executable, font, disk, shortcut, generic
}

struct FileItem: Identifiable, Hashable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let isPackage: Bool
    let isHidden: Bool
    let isSymlink: Bool
    let size: Int64
    let modified: Date
    let created: Date
    let ext: String

    var id: String { url.path }

    /// A mount point: the startup disk or something mounted under /Volumes.
    var isVolume: Bool { url.path == "/" || url.deletingLastPathComponent().path == "/Volumes" }

    static func == (a: FileItem, b: FileItem) -> Bool { a.url == b.url }
    func hash(into h: inout Hasher) { h.combine(url) }

    /// Windows hides known extensions by default; Explorer shows the stem for files.
    var displayName: String {
        if isDirectory && !isPackage { return name }
        if Prefs.shared.showExtensions { return name }
        let stem = (name as NSString).deletingPathExtension
        return stem.isEmpty ? name : stem
    }

    var kind: FileKind {
        if isDirectory && !isPackage { return .folder }
        switch ext.lowercased() {
        case "app": return .app
        case "png", "jpg", "jpeg", "gif", "bmp", "heic", "webp", "tiff", "tif", "svg", "ico", "raw", "cr2":
            return .image
        case "mp4", "mov", "avi", "mkv", "wmv", "m4v", "webm", "flv", "mpg", "mpeg":
            return .video
        case "mp3", "wav", "flac", "aac", "m4a", "ogg", "wma", "aiff", "mid":
            return .audio
        case "pdf": return .pdf
        case "doc", "docx", "rtf", "odt", "pages": return .word
        case "xls", "xlsx", "csv", "ods", "numbers": return .excel
        case "ppt", "pptx", "odp", "key": return .powerpoint
        case "txt", "log", "md", "ini", "cfg", "conf", "nfo": return .text
        case "swift", "js", "ts", "py", "c", "cpp", "h", "java", "cs", "go", "rs",
             "rb", "php", "html", "css", "json", "xml", "yml", "yaml", "sh", "bat", "ps1":
            return .code
        case "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "cab", "iso":
            return .archive
        case "exe", "msi", "dll", "com", "sys": return .executable
        case "ttf", "otf", "woff", "woff2", "fon": return .font
        case "dmg", "img", "vhd", "vmdk": return .disk
        case "lnk", "url", "webloc", "alias": return .shortcut
        default: return isSymlink ? .shortcut : .generic
        }
    }

    /// Matches the "Type" column wording Windows Explorer uses.
    var typeName: String {
        if isDirectory && !isPackage { return tr("File folder") }
        if ext.isEmpty { return tr("File") }
        if let known = FileItem.knownTypes[ext.lowercased()] { return tr(known) }
        return tr("%@ File", ext.uppercased())
    }

    private static let knownTypes: [String: String] = [
        "txt": "Text Document", "pdf": "Adobe Acrobat Document",
        "doc": "Microsoft Word 97-2003 Document", "docx": "Microsoft Word Document",
        "xls": "Microsoft Excel 97-2003 Worksheet", "xlsx": "Microsoft Excel Worksheet",
        "ppt": "Microsoft PowerPoint 97-2003 Presentation", "pptx": "Microsoft PowerPoint Presentation",
        "zip": "Compressed (zipped) Folder", "exe": "Application", "app": "Application",
        "msi": "Windows Installer Package", "dll": "Application extension",
        "lnk": "Shortcut", "url": "Internet Shortcut", "webloc": "Internet Shortcut",
        "html": "HTML Document", "htm": "HTML Document", "xml": "XML Document",
        "json": "JSON File", "mp3": "MP3 Audio File", "wav": "Wave Sound",
        "mp4": "MP4 Video File", "mov": "QuickTime Movie", "avi": "AVI Video File",
        "png": "PNG File", "jpg": "JPG File", "jpeg": "JPEG File", "gif": "GIF File",
        "heic": "HEIC File", "svg": "SVG Document", "ico": "Icon", "rtf": "Rich Text Document",
        "dmg": "Disk Image", "iso": "Disc Image File", "ttf": "TrueType Font File",
        "otf": "OpenType Font File", "md": "Markdown Source File", "csv": "Microsoft Excel Comma Separated Values File",
        "py": "Python Source File", "js": "JavaScript File", "swift": "Swift Source File",
        "sh": "Shell Script", "bat": "Windows Batch File", "ps1": "Windows PowerShell Script",
    ]

    // MARK: Formatting

    /// Windows Details view reports file size in whole KB, rounded up.
    var sizeText: String {
        guard !isDirectory || isPackage else { return "" }
        let kb = max(1, Int64(ceil(Double(size) / 1024.0)))
        return "\(FileItem.grouped.string(from: NSNumber(value: kb)) ?? "\(kb)") KB"
    }

    var modifiedText: String { FileItem.winDate.string(from: modified) }
    var createdText: String { FileItem.winDate.string(from: created) }

    // The thousands separator and the date layout follow the app language;
    // English keeps the Windows layout (1,234 / 7/11/2026 3:01 PM).
    private static var formatterCode = ""
    private static var groupedFormatter = NumberFormatter()
    private static var dateFormatter = DateFormatter()

    private static func refreshFormatters() {
        guard formatterCode != L10n.code else { return }
        formatterCode = L10n.code
        let n = NumberFormatter(); n.numberStyle = .decimal
        let d = DateFormatter()
        if L10n.code == "en" {
            n.groupingSeparator = ","
            d.dateFormat = "M/d/yyyy h:mm a"
            d.amSymbol = "AM"; d.pmSymbol = "PM"; d.locale = Locale(identifier: "en_US_POSIX")
        } else {
            n.locale = Locale(identifier: L10n.code)
            d.locale = Locale(identifier: L10n.code)
            d.dateStyle = .short; d.timeStyle = .short
        }
        groupedFormatter = n
        dateFormatter = d
    }

    static var grouped: NumberFormatter { refreshFormatters(); return groupedFormatter }
    static var winDate: DateFormatter { refreshFormatters(); return dateFormatter }

    /// Full byte count with grouping, as shown in Properties.
    static func bytesText(_ n: Int64) -> String {
        tr("%@ bytes", grouped.string(from: NSNumber(value: n)) ?? "\(n)")
    }

    /// "1.44 MB" style, as Windows shows above the byte count.
    static func friendlySize(_ n: Int64) -> String {
        let units = ["bytes", "KB", "MB", "GB", "TB"]
        var v = Double(n), i = 0
        while v >= 1024 && i < units.count - 1 { v /= 1024; i += 1 }
        if i == 0 { return tr("%@ bytes", n) }
        return String(format: "%.2f %@", v, units[i])
    }
}

// MARK: - Sorting / view modes

enum SortKey: String, CaseIterable {
    case name = "Name", modified = "Date modified", type = "Type", size = "Size", created = "Date created"
    var label: String { tr(rawValue) }
}

enum ViewMode: String, CaseIterable {
    case extraLargeIcons = "Extra large icons"
    case largeIcons = "Large icons"
    case mediumIcons = "Medium icons"
    case smallIcons = "Small icons"
    case list = "List"
    case details = "Details"
    case tiles = "Tiles"
    case content = "Content"

    var label: String { tr(rawValue) }

    var isIconGrid: Bool {
        switch self {
        case .extraLargeIcons, .largeIcons, .mediumIcons, .smallIcons: return true
        default: return false
        }
    }

    /// The command that switches to this mode, used for shortcut display.
    /// Tied to the case, not to position in a parallel array, so adding a
    /// view mode cannot index out of bounds.
    var viewCommand: Command {
        switch self {
        case .extraLargeIcons: return .viewExtraLarge
        case .largeIcons: return .viewLarge
        case .mediumIcons: return .viewMedium
        case .smallIcons: return .viewSmall
        case .list: return .viewList
        case .details: return .viewDetails
        case .tiles: return .viewTiles
        case .content: return .viewContent
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .extraLargeIcons: return 96
        case .largeIcons: return 64
        case .mediumIcons: return 48
        case .smallIcons: return 16
        case .tiles: return 48
        case .content: return 32
        default: return 16
        }
    }

    var cellSize: CGSize {
        switch self {
        case .extraLargeIcons: return CGSize(width: 130, height: 148)
        case .largeIcons: return CGSize(width: 106, height: 116)
        case .mediumIcons: return CGSize(width: 94, height: 96)
        case .smallIcons: return CGSize(width: 180, height: 22)
        case .tiles: return CGSize(width: 210, height: 58)
        default: return CGSize(width: 180, height: 22)
        }
    }
}

// MARK: - Known folders (Windows shell folders mapped to their macOS equivalents)

struct Place: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: Icon
    let url: URL?
    var pinned: Bool = true
    var accent: PlaceAccent = .neutral
    var indent: CGFloat = 0
    var special: Special? = nil

    enum Special: Hashable { case home, gallery, thisPC, network, recycleBin }
}

enum PlaceAccent { case neutral, blue, green, teal, purple, orange, pink, red }

enum Places {
    static let home = FileManager.default.homeDirectoryForCurrentUser

    static func url(_ name: String) -> URL { home.appendingPathComponent(name) }

    static var oneDrive: URL? {
        let cloud = home.appendingPathComponent("Library/CloudStorage")
        if let items = try? FileManager.default.contentsOfDirectory(atPath: cloud.path),
           let od = items.first(where: { $0.hasPrefix("OneDrive") }) {
            return cloud.appendingPathComponent(od)
        }
        let direct = home.appendingPathComponent("OneDrive")
        return FileManager.default.fileExists(atPath: direct.path) ? direct : nil
    }

    /// iCloud Drive plus every File Provider root in ~/Library/CloudStorage
    /// (OneDrive, Google Drive accounts, Dropbox...), one sidebar entry each.
    static var cloudPlaces: [Place] {
        let fm = FileManager.default
        var out: [Place] = []
        let icloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        if fm.fileExists(atPath: icloud.path) {
            out.append(Place(id: "cloud:icloud", title: "iCloud Drive", icon: .cloud, url: icloud, accent: .blue))
        }
        let root = home.appendingPathComponent("Library/CloudStorage")
        let names = ((try? fm.contentsOfDirectory(atPath: root.path)) ?? [])
            .filter { !$0.hasPrefix(".") }.sorted()
        for name in names {
            let title: String
            if name.hasPrefix("GoogleDrive-") { title = "Drive · \(name.dropFirst("GoogleDrive-".count).split(separator: "@").first ?? "")" }
            else if name.hasPrefix("OneDrive") { title = "OneDrive" }
            else { title = name }
            out.append(Place(id: "cloud:\(name)", title: title, icon: .cloud,
                             url: root.appendingPathComponent(name), accent: .blue))
        }
        if names.first(where: { $0.hasPrefix("OneDrive") }) == nil, let od = oneDrive {
            out.append(Place(id: "cloud:onedrive", title: "OneDrive", icon: .cloud, url: od, accent: .blue))
        }
        return out
    }

    /// System-reported location (honours relocated folders), symlinks resolved; falls back to ~/<name>.
    private static func std(_ dir: FileManager.SearchPathDirectory, _ fallback: String) -> URL {
        let u = FileManager.default.urls(for: dir, in: .userDomainMask).first ?? url(fallback)
        let r = u.resolvingSymlinksInPath()
        return FileManager.default.fileExists(atPath: r.path) ? r : url(fallback).resolvingSymlinksInPath()
    }

    static let desktop   = std(.desktopDirectory, "Desktop")
    static let downloads = std(.downloadsDirectory, "Downloads")
    static let documents = std(.documentDirectory, "Documents")
    static let pictures  = std(.picturesDirectory, "Pictures")
    static let music     = std(.musicDirectory, "Music")
    static let videos    = std(.moviesDirectory, "Movies")
    static let trash     = url(".Trash")

    /// The folders Windows pins to Quick access out of the box.
    static var defaultPinned: [Place] {
        [
            Place(id: "desktop", title: tr("Desktop"), icon: .desktop, url: desktop, accent: .blue),
            Place(id: "downloads", title: tr("Downloads"), icon: .download, url: downloads, accent: .green),
            Place(id: "documents", title: tr("Documents"), icon: .document, url: documents, accent: .teal),
            Place(id: "pictures", title: tr("Pictures"), icon: .picture, url: pictures, accent: .blue),
            Place(id: "music", title: tr("Music"), icon: .music, url: music, accent: .orange),
            Place(id: "videos", title: tr("Videos"), icon: .video, url: videos, accent: .purple),
        ]
    }

    static var defaultPinnedPaths: Set<String> {
        Set(defaultPinned.compactMap { $0.url?.path })
    }

    /// Default pins minus the ones the user removed, plus the ones they added.
    static var quickAccess: [Place] {
        let settings = Settings.shared
        var list = defaultPinned.filter { p in
            guard let path = p.url?.path else { return true }
            return !settings.hiddenPlaces.contains(path)
        }
        for path in settings.pinned {
            let url = URL(fileURLWithPath: path)
            guard !list.contains(where: { $0.url?.path == path }) else { continue }
            list.append(Place(id: "pin:\(path)", title: displayName(for: url),
                              icon: icon(for: url), url: url, accent: accentFor(url)))
        }
        return list
    }

    private static func accentFor(_ url: URL) -> PlaceAccent {
        switch icon(for: url) {
        case .desktop: return .blue
        case .download: return .green
        case .document: return .teal
        case .picture: return .blue
        case .music: return .orange
        case .video: return .purple
        default: return .neutral
        }
    }

    static var sidebar: [Place] {
        var list: [Place] = [
            Place(id: "home", title: tr("Home"), icon: .home, url: nil, accent: .orange, special: .home),
            Place(id: "gallery", title: tr("Gallery"), icon: .gallery, url: pictures, accent: .blue, special: .gallery),
        ]
        list.append(contentsOf: cloudPlaces)
        list.append(contentsOf: quickAccess)
        list.append(Place(id: "thispc", title: tr("This PC"), icon: .thisPC, url: nil, accent: .blue, special: .thisPC))
        list.append(Place(id: "network", title: tr("Network"), icon: .network, url: URL(fileURLWithPath: "/Volumes"), accent: .neutral, special: .network))
        return list
    }

    static func displayName(for url: URL) -> String {
        if url.path == home.path { return NSUserName() }
        if url.path == "/" { return tr("Local Disk (C:)") }
        if url.path == trash.path { return tr("Recycle Bin") }
        if url.resolvingSymlinksInPath().path == videos.path { return tr("Videos") }
        return url.lastPathComponent
    }

    static func icon(for url: URL) -> Icon {
        switch url.resolvingSymlinksInPath().path {
        case desktop.path: return .desktop
        case downloads.path: return .download
        case documents.path: return .document
        case pictures.path: return .picture
        case music.path: return .music
        case videos.path: return .video
        case trash.path: return .recycleBin
        case home.path: return .home
        default: return .folderOutline
        }
    }
}

// MARK: - Directory loading

enum Loader {
    static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .isHiddenKey, .isSymbolicLinkKey,
        .fileSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey, .creationDateKey, .nameKey,
    ]

    static func item(at url: URL) -> FileItem? {
        let v = try? url.resourceValues(forKeys: Set(keys))
        let name = v?.name ?? url.lastPathComponent
        return FileItem(
            url: url,
            name: name,
            isDirectory: v?.isDirectory ?? false,
            isPackage: v?.isPackage ?? false,
            isHidden: (v?.isHidden ?? false) || name.hasPrefix("."),
            isSymlink: v?.isSymbolicLink ?? false,
            size: Int64(v?.fileSize ?? v?.totalFileAllocatedSize ?? 0),
            modified: v?.contentModificationDate ?? .distantPast,
            created: v?.creationDate ?? .distantPast,
            ext: url.pathExtension
        )
    }

    static func contents(of url: URL, showHidden: Bool) -> [FileItem] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: url, includingPropertiesForKeys: keys,
            options: showHidden ? [] : [.skipsHiddenFiles]
        ) else { return [] }
        return urls.compactMap { item(at: $0) }.filter { showHidden || !$0.isHidden }
    }

    /// Mounted local volumes. Network shares are listed under Network only.
    static func volumes() -> [FileItem] {
        let fm = FileManager.default
        var out: [FileItem] = []
        if let root = item(at: URL(fileURLWithPath: "/")) { out.append(root) }
        let mounted = fm.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        for u in mounted where u.path != "/" {
            if (try? u.resourceValues(forKeys: [.volumeIsLocalKey]))?.volumeIsLocal == false { continue }
            if let i = item(at: u) { out.append(i) }
        }
        return out
    }

    /// Whether the volume holding `url` is mounted over the network (SMB,
    /// AFP, NFS, WebDAV...). The kernel's mount table answers instantly —
    /// unlike the share itself, which may take minutes to wake up.
    static func isRemote(_ url: URL) -> Bool {
        var s = statfs()
        guard statfs(url.path, &s) == 0 else { return false }
        return s.f_flags & UInt32(MNT_LOCAL) == 0
    }

    /// Windows-style natural sort: folders first, then numeric-aware name comparison.
    static func sort(_ items: [FileItem], by key: SortKey, ascending: Bool) -> [FileItem] {
        let sorted = items.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            let result: Bool
            switch key {
            case .name:
                result = naturalLess(a.name, b.name)
            case .modified:
                result = a.modified == b.modified ? naturalLess(a.name, b.name) : a.modified < b.modified
            case .created:
                result = a.created == b.created ? naturalLess(a.name, b.name) : a.created < b.created
            case .type:
                result = a.typeName == b.typeName ? naturalLess(a.name, b.name) : a.typeName.localizedCompare(b.typeName) == .orderedAscending
            case .size:
                result = a.size == b.size ? naturalLess(a.name, b.name) : a.size < b.size
            }
            return ascending ? result : !result
        }
        return sorted
    }

    static func naturalLess(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.numeric, .caseInsensitive, .widthInsensitive], range: nil, locale: .current) == .orderedAscending
    }
}

// MARK: - Preferences

/// Where preferences live. Test and demo runs get their own scratch domain so
/// they can never disturb the settings of a real install.
enum Store {
    static let defaults: UserDefaults = {
        let env = ProcessInfo.processInfo.environment
        guard env["WINEXP_SELFTEST"] != nil || env["WINEXP_DEMO"] != nil else {
            return .standard
        }
        let suite = "com.winexplorer.mac.scratch"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }()
}

final class Prefs: ObservableObject {
    static let shared = Prefs()
    private let d = Store.defaults

    @Published var showHidden: Bool { didSet { d.set(showHidden, forKey: "showHidden") } }
    @Published var showExtensions: Bool { didSet { d.set(showExtensions, forKey: "showExtensions") } }
    @Published var showDetailsPane: Bool { didSet { d.set(showDetailsPane, forKey: "showDetailsPane") } }
    @Published var showNavPane: Bool { didSet { d.set(showNavPane, forKey: "showNavPane") } }
    @Published var showPreviewPane: Bool { didSet { d.set(showPreviewPane, forKey: "showPreviewPane") } }
    @Published var viewMode: ViewMode { didSet { d.set(viewMode.rawValue, forKey: "viewMode") } }
    @Published var sortKey: SortKey { didSet { d.set(sortKey.rawValue, forKey: "sortKey") } }
    @Published var sortAscending: Bool { didSet { d.set(sortAscending, forKey: "sortAscending") } }
    @Published var groupBy: String { didSet { d.set(groupBy, forKey: "groupBy") } }
    @Published var itemCheckBoxes: Bool { didSet { d.set(itemCheckBoxes, forKey: "itemCheckBoxes") } }
    @Published var compactMode: Bool { didSet { d.set(compactMode, forKey: "compactMode") } }
    @Published var showAccountStatus: Bool { didSet { d.set(showAccountStatus, forKey: "showAccountStatus") } }
    @Published var dualPane: Bool { didSet { d.set(dualPane, forKey: "dualPane") } }
    @Published var showShelf: Bool { didSet { d.set(showShelf, forKey: "showShelf") } }

    private init() {
        d.register(defaults: [
            "showHidden": false, "showExtensions": true, "showDetailsPane": false,
            "showNavPane": true, "showPreviewPane": false, "viewMode": ViewMode.details.rawValue,
            "sortKey": SortKey.name.rawValue, "sortAscending": true, "groupBy": "(None)",
            "itemCheckBoxes": false, "compactMode": false, "showAccountStatus": true,
            "dualPane": false, "showShelf": false,
        ])
        showHidden = d.bool(forKey: "showHidden")
        showExtensions = d.bool(forKey: "showExtensions")
        showDetailsPane = d.bool(forKey: "showDetailsPane")
        showNavPane = d.bool(forKey: "showNavPane")
        showPreviewPane = d.bool(forKey: "showPreviewPane")
        viewMode = ViewMode(rawValue: d.string(forKey: "viewMode") ?? "") ?? .details
        sortKey = SortKey(rawValue: d.string(forKey: "sortKey") ?? "") ?? .name
        sortAscending = d.bool(forKey: "sortAscending")
        groupBy = d.string(forKey: "groupBy") ?? "(None)"
        itemCheckBoxes = d.bool(forKey: "itemCheckBoxes")
        compactMode = d.bool(forKey: "compactMode")
        showAccountStatus = d.bool(forKey: "showAccountStatus")
        dualPane = d.bool(forKey: "dualPane")
        showShelf = d.bool(forKey: "showShelf")
    }
}
