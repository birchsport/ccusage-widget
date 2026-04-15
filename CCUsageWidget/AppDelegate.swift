import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let width: CGFloat = 320
        let height: CGFloat = 720

        let screen = NSScreen.main ?? NSScreen.screens.first!
        let visible = screen.visibleFrame
        let x = visible.maxX - width - 20
        let y = visible.maxY - (height + 20)

        let panel = NSPanel(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
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
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true

        let hosting = NSHostingView(rootView: ContentView())
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        panel.orderFrontRegardless()
        self.panel = panel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
