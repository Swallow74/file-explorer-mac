import AppKit
import QuickLookUI

/// Finder-style Quick Look: Space opens a preview of the selection, Space or
/// Escape closes it, and the arrow keys move the preview along the selection.
final class QuickLook: NSObject, QLPreviewPanelDataSource {
    static let shared = QuickLook()
    private var urls: [URL] = []

    var isVisible: Bool { QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible }

    /// Space: closes the panel if it is open, otherwise previews the selection.
    func toggle(_ ex: Explorer) {
        if isVisible { close(); return }
        refresh(ex)
        guard !urls.isEmpty else { NSSound.beep(); return }
        let panel = QLPreviewPanel.shared()!
        panel.dataSource = self
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        if isVisible { QLPreviewPanel.shared().close() }
    }

    /// Re-reads the selection after it changed under an open panel.
    func refresh(_ ex: Explorer) {
        urls = ex.selectedItems.map(\.url)
        if isVisible { QLPreviewPanel.shared().reloadData() }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        urls.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        urls[index] as NSURL
    }
}
