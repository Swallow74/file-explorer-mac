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
    @Published private(set) var mounts: [MountInfo] = []
    @Published private(set) var scanned: [String: (name: String, ip: String)] = [:]
    /// Background jobs in flight; the page shows a spinner while it is above zero.
    @Published private(set) var busy = 0
    private var lastScan = Date.distantPast

    struct MountInfo {
        let url: URL
        let name: String
        let mount: NetMount?
    }

    private func track(_ work: @escaping () -> Void, done: @escaping () -> Void) {
        busy += 1
        DispatchQueue.global(qos: .utility).async {
            work()
            DispatchQueue.main.async { done(); self.busy -= 1 }
        }
    }

    /// Mounted network shares, read off the main thread: statfs on a sleeping NAS can block.
    func refreshMounts() {
        var result: [MountInfo] = []
        track({
            let urls = FileManager.default.mountedVolumeURLs(
                includingResourceValuesForKeys: [.volumeIsLocalKey], options: [.skipHiddenVolumes]) ?? []
            result = urls.filter { (try? $0.resourceValues(forKeys: [.volumeIsLocalKey]))?.volumeIsLocal == false }
                .map { MountInfo(url: $0, name: $0.lastPathComponent, mount: NetMount.of($0)) }
        }, done: { self.mounts = result })
    }

    /// Looks for SMB servers on the local subnets (port 445) and asks each for
    /// its NetBIOS name, the way Finder finds machines that never announce
    /// themselves over Bonjour.
    func scanLAN() {
        guard Date().timeIntervalSince(lastScan) > 60,
              ProcessInfo.processInfo.environment["WINEXP_NORECENTS"] == nil else { return }
        lastScan = Date()
        var found: [String: (name: String, ip: String)] = [:]
        track({ found = LANScan.run() }, done: { self.scanned = found })
    }

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
        var names: [String] = []
        track({ names = Self.smbShares(address: host.address, user: host.user) },
              done: { self.listing.remove(host.key); self.shares[host.key] = names })
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
    func hosts() -> [NetHost] {
        var map: [String: NetHost] = [:]
        for item in mounts {
            guard let m = item.mount else {
                // Not an //host/share mount (NFS, WebDAV...): a one-share host of its own.
                let key = "vol:" + item.url.path
                map[key] = NetHost(key: key, name: item.name, address: "",
                                   mounts: [item.name.lowercased(): item.url])
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
        let knownAddresses = Set(map.values.map(\.address))
        for (key, found) in scanned where map[key] == nil && !knownAddresses.contains(found.ip) {
            map[key] = NetHost(key: key, name: found.name, address: found.ip)
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
        let hosts = net.hosts()
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
        .overlay(alignment: .topTrailing) {
            if net.busy > 0 { ProgressView().controlSize(.small).padding(14) }
        }
        .onAppear { net.start(); net.refreshMounts(); net.scanLAN() }
        .onReceive(tick) { _ in net.refreshMounts() }
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
    @State private var mounting = false

    var body: some View {
        HStack(spacing: 12) {
            DriveIcon(size: 40).opacity(mount == nil ? 0.55 : 1)
            Text(share.isEmpty ? host.name : share)
                .font(Win.body(12)).foregroundStyle(Win.text).lineLimit(1)
            Spacer(minLength: 0)
            if mounting { ProgressView().controlSize(.small) }
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
        guard !mounting else { return }
        mounting = true
        RemoteServers.connect("smb://\(who)\(host.address)/\(path)") { url in
            mounting = false
            if let url { ex.go(to: url) }
        }
    }
}

extension String { func appendLine(_ p: String) throws {
    if let h = FileHandle(forWritingAtPath: p) { h.seekToEndOfFile(); h.write(data(using: .utf8)!); h.closeFile() }
    else { try write(toFile: p, atomically: true, encoding: .utf8) } } }

/// Finds SMB servers on the directly connected IPv4 subnets.
enum LANScan {
    static func run() -> [String: (name: String, ip: String)] {
        var own: Set<UInt32> = []
        var targets: [UInt32] = []
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return [:] }
        defer { freeifaddrs(ifap) }
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let i = p {
            defer { p = i.pointee.ifa_next }
            let name = String(cString: i.pointee.ifa_name)
            let flags = Int32(i.pointee.ifa_flags)
            guard name.hasPrefix("en"), flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  let a = i.pointee.ifa_addr, a.pointee.sa_family == sa_family_t(AF_INET),
                  let m = i.pointee.ifa_netmask else { continue }
            let ip = a.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            let mask = m.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            let private10 = ip >> 24 == 10, private192 = ip >> 16 == 0xC0A8, private172 = ip >> 20 == 0xAC1
            guard private10 || private192 || private172 else { continue }
            own.insert(ip)
            // Never wider than the /24 around us: 254 probes, not thousands.
            let effective = mask < 0xFFFFFF00 ? 0xFFFFFF00 : mask
            let net = ip & effective
            let count = ~effective
            for host in 1..<count where net | host != ip { targets.append(net | host) }
        }
        var found: [String: (name: String, ip: String)] = [:]
        let lock = NSLock()
        let group = DispatchGroup()
        for ip in Set(targets) where !own.contains(ip) {
            DispatchQueue.global(qos: .utility).async(group: group) {
                guard portOpen(ip, port: 445, timeoutMs: 700) else { return }
                let text = dotted(ip)
                let name = netbiosName(ip) ?? reverseName(ip) ?? text
                lock.lock(); found[NetHost.key(for: name)] = (name, text); lock.unlock()
            }
        }
        group.wait()
        return found
    }

    private static func dotted(_ ip: UInt32) -> String {
        "\(ip >> 24).\((ip >> 16) & 255).\((ip >> 8) & 255).\(ip & 255)"
    }

    private static func sockaddr(_ ip: UInt32, _ port: UInt16) -> sockaddr_in {
        var a = sockaddr_in()
        a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        a.sin_family = sa_family_t(AF_INET)
        a.sin_port = port.bigEndian
        a.sin_addr.s_addr = ip.bigEndian
        return a
    }

    private static func portOpen(_ ip: UInt32, port: UInt16, timeoutMs: Int32) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        var addr = sockaddr(ip, port)
        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: Darwin.sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if r == 0 { return true }
        guard errno == EINPROGRESS else { return false }
        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        guard poll(&pfd, 1, timeoutMs) > 0 else { return false }
        var err: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len)
        return err == 0
    }

    /// NetBIOS node status request (UDP 137): the host answers with its names.
    private static func netbiosName(_ ip: UInt32) -> String? {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var tv = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var q: [UInt8] = [0x13, 0x37, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0x20, 0x43, 0x4B]
        q += [UInt8](repeating: 0x41, count: 30)
        q += [0, 0, 0x21, 0, 1]
        var addr = sockaddr(ip, 137)
        let sent = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: Darwin.sockaddr.self, capacity: 1) {
                sendto(fd, q, q.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard sent == q.count else { return nil }
        var buf = [UInt8](repeating: 0, count: 1024)
        let n = recv(fd, &buf, buf.count, 0)
        // Header 12 + echoed question 38 + answer header 12 (name pointer, type, class, ttl, length) + count.
        guard n > 57 else { return nil }
        let names = Int(buf[56])
        var o = 57
        for _ in 0..<names where o + 18 <= n {
            let raw = buf[o..<(o + 15)]
            let suffix = buf[o + 15], flags = UInt16(buf[o + 16]) << 8 | UInt16(buf[o + 17])
            o += 18
            if suffix == 0, flags & 0x8000 == 0 {   // unique workstation name
                let name = String(decoding: raw, as: UTF8.self).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { return name }
            }
        }
        return nil
    }

    private static func reverseName(_ ip: UInt32) -> String? {
        var addr = sockaddr(ip, 0)
        var host = [CChar](repeating: 0, count: 256)
        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: Darwin.sockaddr.self, capacity: 1) {
                getnameinfo($0, socklen_t(MemoryLayout<sockaddr_in>.size), &host, socklen_t(host.count), nil, 0, NI_NAMEREQD)
            }
        }
        guard r == 0 else { return nil }
        let name = String(cString: host)
        return name.split(separator: ".").first.map(String.init)
    }
}
