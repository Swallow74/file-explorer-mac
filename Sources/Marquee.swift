import SwiftUI
import AppKit

/// Frames of the visible items, in the window's root coordinate space.
struct ItemFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, b in b })
    }
}

/// Rubber-band selection.
///
/// Handled at the AppKit level rather than with a SwiftUI drag gesture: the
/// list lives inside a ScrollView, which claims drags for scrolling long
/// before a gesture on the background would see them. A window-level monitor
/// takes the press only when it lands on empty space inside a pane, so drags
/// that start on an item still drag the item.
final class MarqueeController: ObservableObject {
    static let shared = MarqueeController()

    struct Zone {
        weak var explorer: Explorer?
        var frame: CGRect = .zero
        var items: [String: CGRect] = [:]
    }

    private var zones: [ObjectIdentifier: Zone] = [:]
    /// Which view last claimed each zone: when a newer view has claimed it,
    /// an older one disappearing must not delete the zone still in use.
    private var generations: [ObjectIdentifier: Int] = [:]

    /// The rectangle being dragged, in root coordinates.
    @Published private(set) var rect: CGRect?
    private var owner: ObjectIdentifier?
    private var origin: CGPoint = .zero
    private var baseSelection: Set<String> = []
    private var moved = false

    var isDragging: Bool { owner != nil }

    // MARK: Registration

    func setZone(_ frame: CGRect, for explorer: Explorer) {
        var zone = zones[ObjectIdentifier(explorer)] ?? Zone()
        zone.explorer = explorer
        zone.frame = frame
        zones[ObjectIdentifier(explorer)] = zone
    }

    /// Marks a zone registration as belonging to this view instance.
    func claimZone(for explorer: Explorer) -> Int {
        let key = ObjectIdentifier(explorer)
        let gen = (generations[key] ?? 0) + 1
        generations[key] = gen
        return gen
    }

    /// The view that registered the zone went away (a folder closed, the
    /// Network page now showing): the zone must go with it, or its stale
    /// frame swallows every click on the page that replaced the list.
    func releaseZone(for explorer: Explorer, generation: Int) {
        let key = ObjectIdentifier(explorer)
        guard generations[key] == generation else { return }
        generations[key] = nil
        zones.removeValue(forKey: key)
        if owner == key { owner = nil; rect = nil; baseSelection = [] }
    }

    func setItems(_ items: [String: CGRect], for explorer: Explorer) {
        var zone = zones[ObjectIdentifier(explorer)] ?? Zone()
        zone.explorer = explorer
        zone.items = items
        zones[ObjectIdentifier(explorer)] = zone
    }

    func zone(for explorer: Explorer) -> Zone? { zones[ObjectIdentifier(explorer)] }

    // MARK: Dragging

    /// Starts a band if the point is on empty space inside a pane.
    /// `window` is the window the press landed in: zone frames are in each
    /// window's own root coordinates, so without the filter a second,
    /// same-sized window can hijack the drag (Dictionary order is random).
    @discardableResult
    func begin(at point: CGPoint, additive: Bool, in window: NSWindow? = nil) -> Bool {
        var match: (ObjectIdentifier, Zone)?
        for (id, zone) in zones {
            guard zone.frame.contains(point), let explorer = zone.explorer else { continue }
            if let window, AppState.shared.window(for: explorer) !== window { continue }
            match = (id, zone)
            break
        }
        guard let (id, zone) = match, let explorer = zone.explorer else { return false }
        // A press on an item belongs to the item, not to a selection band.
        guard !zone.items.values.contains(where: { $0.contains(point) }) else { return false }

        owner = id
        origin = point
        moved = false
        baseSelection = additive ? explorer.tab.selection : []
        rect = CGRect(origin: point, size: .zero)
        return true
    }

    func update(to point: CGPoint) {
        guard let owner, let zone = zones[owner], let explorer = zone.explorer else { return }
        let band = CGRect(x: min(origin.x, point.x), y: min(origin.y, point.y),
                          width: abs(point.x - origin.x), height: abs(point.y - origin.y))
        if band.width > 3 || band.height > 3 { moved = true }
        rect = band.intersection(zone.frame)

        let hits = zone.items.filter { $0.value.intersects(band) }.map(\.key)
        explorer.applyMarquee(Set(hits), base: baseSelection)
    }

    func end() {
        defer {
            owner = nil
            rect = nil
            baseSelection = []
        }
        guard let owner, let zone = zones[owner], let explorer = zone.explorer else { return }
        // A press with no drag is just a click on the background.
        if !moved && baseSelection.isEmpty { explorer.selectNone() }
    }

    // MARK: Event routing

    /// Returns true when the event has been taken over by a selection band.
    func handle(_ event: NSEvent) -> Bool {
        switch event.type {
        case .leftMouseDown:
            guard event.clickCount == 1, !MenuController.anyOpen else { return false }
            // A dialog covers the pane: its buttons must get the click, not a band.
            if AppState.shared.active?.sheet != nil { return false }
            let flags = event.modifierFlags
            let additive = flags.contains(.shift) || flags.contains(.command)
                || flags.contains(.control)
            return begin(at: RightClickRouter.rootPoint(event), additive: additive,
                         in: event.window)
        case .leftMouseDragged:
            guard isDragging else { return false }
            update(to: RightClickRouter.rootPoint(event))
            return true
        case .leftMouseUp:
            guard isDragging else { return false }
            end()
            return true
        default:
            return false
        }
    }
}

// MARK: - View plumbing

extension View {
    /// Marks the scrollable region of a pane as somewhere a band can be drawn.
    /// The zone lives exactly as long as the view that drew it: navigating
    /// away (to the Network page, to a different view mode) must leave no
    /// zone behind, or its old frame captures clicks meant for the new page.
    func marqueeZone(_ explorer: Explorer) -> some View {
        background(MarqueeZoneReader(explorer: explorer))
    }

    /// Reports this item's position so the band knows what it is crossing.
    func marqueeItem(_ id: String) -> some View {
        background(GeometryReader { geo in
            Color.clear.preference(key: ItemFrameKey.self,
                                   value: [id: geo.frame(in: .named("root"))])
        })
    }
}

private struct MarqueeZoneReader: View {
    let explorer: Explorer
    @State private var generation = 0

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear {
                    generation = MarqueeController.shared.claimZone(for: explorer)
                    MarqueeController.shared.setZone(geo.frame(in: .named("root")), for: explorer)
                }
                .onChange(of: geo.frame(in: .named("root"))) { _, frame in
                    MarqueeController.shared.setZone(frame, for: explorer)
                }
                .onDisappear {
                    MarqueeController.shared.releaseZone(for: explorer, generation: generation)
                }
        }
    }
}

/// The band itself, drawn over the window in root coordinates.
struct MarqueeOverlay: View {
    @ObservedObject var controller = MarqueeController.shared

    var body: some View {
        if let rect = controller.rect, rect.width > 1 || rect.height > 1 {
            Rectangle()
                .fill(Win.accent.opacity(0.20))
                .overlay(Rectangle().stroke(Win.accent.opacity(0.85), lineWidth: 1))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .allowsHitTesting(false)
        }
    }
}
