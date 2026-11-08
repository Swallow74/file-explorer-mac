import SwiftUI

/// Used and total bytes of the volume mounted at `url`, nil when unreadable or
/// not a local disk (network shares report unreliable figures, e.g. a NAS
/// spanning several disks).
enum VolumeSpace {
    static func of(_ url: URL) -> (free: Int64, total: Int64)? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeIsLocalKey]
        guard let v = try? url.resourceValues(forKeys: keys), v.volumeIsLocal == true,
              let total = v.volumeTotalCapacity, total > 0,
              let free = v.volumeAvailableCapacityForImportantUsage else { return nil }
        return (free, Int64(total))
    }
}

/// This PC: every mounted volume as an Explorer drive tile, icon plus
/// capacity bar plus "x GB free of y GB".
struct ThisPCView: View {
    @ObservedObject var ex: Explorer
    @ObservedObject var menus: MenuController

    var body: some View {
        ScrollView(.vertical) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 270, maximum: 360), spacing: 4, alignment: .top)],
                      alignment: .leading, spacing: 4) {
                ForEach(ex.tab.items) { item in
                    DriveTile(ex: ex, menus: menus, item: item).id(item.id)
                }
            }
            .padding(12)
        }
        .marqueeZone(ex)
    }
}

struct DriveTile: View {
    @ObservedObject var ex: Explorer
    @ObservedObject var menus: MenuController
    let item: FileItem
    @State private var hovering = false

    private var selected: Bool { ex.tab.selection.contains(item.id) }

    var body: some View {
        let space = VolumeSpace.of(item.url)
        HStack(spacing: 12) {
            DriveIcon(size: 52)
            VStack(alignment: .leading, spacing: 5) {
                Text(Places.displayName(for: item.url))
                    .font(Win.body(12)).foregroundStyle(Win.text).lineLimit(1)
                if let space {
                    let used = Double(space.total - space.free) / Double(space.total)
                    CapacityBar(used: used)
                    Text(tr("%1$@ free of %2$@", Self.format(space.free), Self.format(space.total)))
                        .font(Win.body(11)).foregroundStyle(Win.textSecondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 76)
        .background(
            WinRR(radius: 4).fill(
                selected ? (hovering ? Win.selectedHover : Win.selected)
                         : (hovering ? Win.subtleHover : .clear))
        )
        .onHover { hovering = $0 }
        .itemInteraction(ex, menus, item)
    }

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// Explorer's thin capacity bar: accent while there is room, red once the
/// drive is nearly full.
struct CapacityBar: View {
    let used: Double

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().fill(Win.subtleHover)
                Rectangle()
                    .fill(used > 0.9 ? Color(red: 0.85, green: 0.27, blue: 0.24) : Win.accent)
                    .frame(width: g.size.width * min(max(used, 0), 1))
            }
        }
        .frame(height: 12)
        .overlay(Rectangle().stroke(Win.divider, lineWidth: 1))
    }
}
