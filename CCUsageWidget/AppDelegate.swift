import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let width: CGFloat = 280
        let height: CGFloat = 820  // fits a NOW card with two sessions without scrolling

        let screen = NSScreen.main ?? NSScreen.screens.first!
        let visible = screen.visibleFrame
        let x = visible.maxX - width - 20
        let y = visible.maxY - (height + 20)

        let panel = NSPanel(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        // Drag any edge to resize. Below ~260pt wide the 7-day bar labels and
        // the header start to collide, so clamp there.
        panel.contentMinSize = NSSize(width: 260, height: 360)
        panel.contentMaxSize = NSSize(width: 720, height: 4000)

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
        // Dragging is handled by a SwiftUI gesture in ContentView; AppKit's
        // background-drag can't see clicks through the hosting view, and leaving
        // it on risks double-moving if it ever does.
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true

        let hosting = NSHostingView(rootView: ContentView())
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hosting.autoresizingMask = [.width, .height]
        // Don't let SwiftUI pin the window to the content's ideal size;
        // the panel's own min/max above govern resizing.
        hosting.sizingOptions = []
        panel.contentView = hosting

        // Remember size and position across launches (saved in UserDefaults).
        // The top-right default above applies only until the user moves it.
        let autosaveName = "CCUsagePanel"
        panel.setFrameUsingName(autosaveName)
        panel.setFrameAutosaveName(autosaveName)

        panel.orderFrontRegardless()
        self.panel = panel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
