import SwiftUI
import Network
import Darwin

/// Where a mounted network share comes from, read from the kernel's mount table.
struct NetMount {
    let user: String?
    let address: String   // as the kernel knows it, e.g. DH2300-01E2._smb._tcp.local.
    let share: String

    static func of(_ url: URL) -> NetMount? {
        var s = statfs()
        guard statfs(url.path, &s) == 0 else { return nil }
        let from = withUnsafeBytes(of: &s.f_mntfromname) { raw in
            String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
        }
        guard from.hasPrefix("//") else { return nil }
        let rest = from.dropFirst(2)
        guard let slash = rest.firstIndex(of: "/") else { return nil }
        var authority = String(rest[..<slash])
        let share = String(rest[rest.index(after: slash)...]).removingPercentEncoding ?? ""
        var user: String?
        if let at = authority.lastIndex(of: "@") {
            user = String(authority[..<at]).removingPercentEncoding
            authority = String(authority[authority.index(after: at)...])
        }
        guard !authority.isEmpty, !share.isEmpty else { return nil }
        return NetMount(user: user, address: authority.removingPercentEncoding ?? authority, share: share)
    }
}

/// A machine on the network, whatever way it was found.
struct NetHost: Identifiable {
    let key: String
    var name: String
    var address: String
    var user: String?
    var mounts: [String: URL] = [:]   // lowercased share name -> mount point
    var id: String { key }

    static func key(for host: String) -> String {
        var h = host.lowercased()
        for suffix in ["._smb._tcp.local.", "._afpovertcp._tcp.local.", ".local.", ".local", "."] where h.hasSuffix(suffix) {
            h.removeLast(suffix.count)
            break
        }
        return h.replacingOccurrences(of: " ", with: "-")
    }

    static func displayName(_ host: String) -> String {
        var h = host
        for suffix in ["._smb._tcp.local.", "._afpovertcp._tcp.local.", ".local.", ".local"] where h.lowercased().hasSuffix(suffix) {
            h.removeLast(suffix.count)
            break
        }
        return h
    }
}

/// Finds hosts through Bonjour and lists their shares. Shares of an unmounted
/// host are read with `smbutil view`, which uses the keychain and never prompts.
final class NetworkHosts: ObservableObject {
    static let shared = NetworkHosts()

    @Published private(set) var discovered: [String: String] = [:]   // key -> display name
    @Published private(set) var shares: [String: [String]] = [:]     // key -> share names
    private var browsers: [NWBrowser] = []
    private var listing: Set<String> = []
    private var known: [String: NetHost] = [:]

    func host(forKey key: String) -> NetHost? { known[key] }
    func name(forKey key: String) -> String { known[key]?.name ?? key }

    func start() {
        guard browsers.isEmpty, ProcessInfo.processInfo.environment["WINEXP_NORECENTS"] == nil else { return }
        for type in ["_smb._tcp", "_afpovertcp._tcp"] {
            let b = NWBrowser(for: .bonjour(type: type, domain: nil), using: .tcp)
            b.browseResultsChangedHandler = { [weak self] results, _ in
                var found: [String: String] = [:]
                try? "\(type) results \(results.count)\n".appendLine("/tmp/nwdebug.txt")
                for r in results {
                    if case let .service(name, _, _, _) = r.endpoint { found[NetHost.key(for: name)] = name }
                }
                DispatchQueue.main.async {
                    guard let self else { return }
                    // Merge: the SMB and AFP browsers each report their own subset.
                    self.discovered = self.discovered.merging(found) { a, _ in a }
                }
            }
            b.stateUpdateHandler = { st in try? "\(type) \(st)\n".appendLine("/tmp/nwdebug.txt") }
            b.start(queue: .global(qos: .utility))
            browsers.append(b)
        }
    }

    func listShares(of host: NetHost) {
        guard !listing.contains(host.key), shares[host.key] == nil else { return }
        listing.insert(host.key)
        DispatchQueue.global(qos: .utility).async {
            let names = Self.smbShares(address: host.address, user: host.user)
            DispatchQueue.main.async {
                self.listing.remove(host.key)
                self.shares[host.key] = names
            }
        }
    }

    private static func smbShares(address: String, user: String?) -> [String] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/smbutil")
        let who = user.map { ($0.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? $0) + "@" } ?? ""
        p.arguments = ["view", "-N", "//\(who)\(address)"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 8, execute: killer)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { line in
            guard let r = line.range(of: #"\s{2,}Disk\b"#, options: .regularExpression) else { return nil }
            let name = line[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
            return name.isEmpty || name.hasSuffix("$") ? nil : name
        }
    }

    /// Every host we know about: the ones with a mounted share, the saved
    /// server bookmarks and whatever Bonjour currently sees.
    func hosts(mounted: [FileItem]) -> [NetHost] {
        var map: [String: NetHost] = [:]
        for item in mounted {
            guard let m = NetMount.of(item.url) else {
                // Not an //host/share mount (NFS, WebDAV...): a one-share host of its own.
                let key = "vol:" + item.url.path
                map[key] = NetHost(key: key, name: item.displayName, address: "",
                                   mounts: [item.displayName.lowercased(): item.url])
                continue
            }
            let key = NetHost.key(for: m.address)
            var h = map[key] ?? NetHost(key: key, name: NetHost.displayName(m.address), address: m.address, user: m.user)
            h.mounts[m.share.lowercased()] = item.url
            map[key] = h
        }
        for b in RemoteServers.recent {
            guard let u = URL(string: b.address), let host = u.host, ["smb", "afp"].contains(u.scheme) else { continue }
            let key = NetHost.key(for: host)
            if map[key] == nil { map[key] = NetHost(key: key, name: NetHost.displayName(host), address: host, user: u.user) }
        }
        for (key, name) in discovered where map[key] == nil && name != Host.current().localizedName {
            map[key] = NetHost(key: key, name: name,
                               address: name.replacingOccurrences(of: " ", with: "-") + ".local")
        }
        known = map
        return map.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// Network lists the hosts; opening one shows the shares it offers.
struct NetworkView: View {
    @ObservedObject var ex: Explorer
    @ObservedObject private var net = NetworkHosts.shared
    private let tick = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    var body: some View {
        let hosts = net.hosts(mounted: ex.tab.items)
        ScrollView(.vertical) {
            if case .networkHost(let key) = ex.tab.location {
                if let host = hosts.first(where: { $0.key == key }) {
                    HostShares(ex: ex, host: host, listed: net.shares[key] ?? [])
                        .onAppear { net.listShares(of: host) }
                } else {
                    Text(tr("No network hosts found."))
                        .font(Win.body(12)).foregroundStyle(Win.textTertiary)
                        .padding(.horizontal, 12).padding(.top, 14)
                }
            } else if hosts.isEmpty {
                Text(tr("No network hosts found."))
                    .font(Win.body(12)).foregroundStyle(Win.textTertiary)
                    .padding(.horizontal, 12).padding(.top, 14)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: 340), spacing: 4, alignment: .top)],
                          alignment: .leading, spacing: 4) {
                    ForEach(hosts) { host in HostTile(ex: ex, host: host) }
                }
                .padding(12)
            }
        }
        .onAppear { net.start() }
        .onReceive(tick) { _ in switch ex.tab.location { case .network, .networkHost: ex.reload(); default: break } }
    }
}

struct HostTile: View {
    @ObservedObject var ex: Explorer
    let host: NetHost
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Glyph(icon: .thisPC, size: 36, color: Color(red: 0.25, green: 0.55, blue: 0.90), weight: 1.1)
                .frame(width: 40, height: 40)
            Text(host.name).font(Win.body(12)).foregroundStyle(Win.text).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 56)
        .background(WinRR(radius: 4).fill(hovering ? Win.subtleHover : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { ex.go(to: .networkHost(host.key)) }
    }
}

struct HostShares: View {
    @ObservedObject var ex: Explorer
    let host: NetHost
    let listed: [String]

    /// Listed shares plus mounted ones the listing did not mention.
    private var shareNames: [String] {
        var names = listed
        for (key, url) in host.mounts.sorted(by: { $0.key < $1.key })
        where !names.contains(where: { $0.lowercased() == key }) {
            names.append(url.lastPathComponent)
        }
        return names
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: 340), spacing: 4, alignment: .top)],
                  alignment: .leading, spacing: 4) {
            ForEach(shareNames, id: \.self) { name in
                ShareTile(ex: ex, host: host, share: name, mount: host.mounts[name.lowercased()])
            }
            if shareNames.isEmpty && !host.address.isEmpty {
                ShareTile(ex: ex, host: host, share: "", mount: nil)
            }
        }
        .padding(12)
    }
}

struct ShareTile: View {
    @ObservedObject var ex: Explorer
    let host: NetHost
    let share: String       // empty: the host itself, share still to be chosen
    let mount: URL?
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            DriveIcon(size: 40).opacity(mount == nil ? 0.55 : 1)
            Text(share.isEmpty ? host.name : share)
                .font(Win.body(12)).foregroundStyle(Win.text).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 56)
        .background(WinRR(radius: 4).fill(hovering ? Win.subtleHover : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: open)
    }

    private func open() {
        if let mount { ex.go(to: mount); return }
        let who = host.user.map { ($0.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? $0) + "@" } ?? ""
        let path = share.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? share
        RemoteServers.connect("smb://\(who)\(host.address)/\(path)") { url in
            if let url { ex.go(to: url) }
        }
    }
}

extension String { func appendLine(_ p: String) throws {
    if let h = FileHandle(forWritingAtPath: p) { h.seekToEndOfFile(); h.write(data(using: .utf8)!); h.closeFile() }
    else { try write(toFile: p, atomically: true, encoding: .utf8) } } }
