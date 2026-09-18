import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: DockPanel?
    var dock: DockController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let dock = DockController()
        let frame = dock.frame(expanded: dock.expanded)

        // Not movable and only resizable while expanded; DockController owns
        // geometry and pins the panel to a screen edge.
        let panel = DockPanel(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        // Use .floating so the panel sits above regular app windows.
        // Note: .screenSaver is a more aggressive level that also sits above
        // menu bar / notification center style elements, at the cost of being
        // harder for users to dismiss.
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        let storedAlpha = UserDefaults.standard.object(forKey: "panelAlpha") as? Double
        panel.alphaValue = CGFloat(storedAlpha ?? 0.80)
        panel.ignoresMouseEvents = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true

        let hosting = NSHostingView(rootView: DockRootView(dock: dock))
        hosting.frame = NSRect(origin: .zero, size: frame.size)
        hosting.autoresizingMask = [.width, .height]
        // Don't let SwiftUI pin the window to the content's ideal size;
        // DockController sets the frame.
        hosting.sizingOptions = []
        panel.contentView = hosting

        dock.attach(panel)
        panel.orderFrontRegardless()
        self.panel = panel
        self.dock = dock
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
