import AppKit
import SwiftUI

enum DockSide: String {
    case left, right
}

/// Keeps the panel attached to a screen edge. Every frame change (live resize,
/// the slide animation, screen changes) runs through `setFrame`, so pinning
/// there means nothing can pull the panel off the edge.
final class DockPanel: NSPanel {
    weak var dock: DockController?

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(dock?.pinned(frameRect) ?? frameRect, display: flag)
    }
}

/// Owns the docked/expanded state and all panel geometry. Collapsed, the panel
/// is just the tab; expanded, it grows inward from the edge and downward from
/// the top, so the tab never moves and clicking the same spot closes it.
@MainActor
final class DockController: NSObject, ObservableObject, NSWindowDelegate {
    static let tabWidth: CGFloat = 64
    static let tabHeight: CGFloat = 164
    private static let topInset: CGFloat = 12
    // Below ~260pt wide the 7-day bar labels and the header start to collide.
    private static let minContent = NSSize(width: 260, height: 360)
    private static let maxContent = NSSize(width: 720, height: 4000)

    @Published private(set) var expanded: Bool {
        didSet { UserDefaults.standard.set(expanded, forKey: "dockExpanded") }
    }

    @Published var side: DockSide {
        didSet {
            UserDefaults.standard.set(side.rawValue, forKey: "dockSide")
            snap()
        }
    }

    /// Expanded panel size excluding the tab column. Tracks live resizes and
    /// is saved when a resize ends.
    @Published private(set) var contentSize: NSSize

    private weak var panel: DockPanel?

    override init() {
        let d = UserDefaults.standard
        expanded = d.bool(forKey: "dockExpanded")
        side = DockSide(rawValue: d.string(forKey: "dockSide") ?? "") ?? .right
        let w = d.double(forKey: "dockWidth"), h = d.double(forKey: "dockHeight")
        contentSize = NSSize(width: w > 0 ? w : 280, height: h > 0 ? h : 820)
        super.init()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.snap() }
        }
    }

    func attach(_ panel: DockPanel) {
        self.panel = panel
        panel.dock = self
        panel.delegate = self
        applyResizability()
        snap()
    }

    // MARK: Geometry

    /// The menu-bar screen. `NSScreen.main` follows the key window, which
    /// would make the panel hop between displays.
    private var visibleFrame: NSRect {
        (NSScreen.screens.first ?? NSScreen.main)?.visibleFrame ?? .zero
    }

    /// Expanded size including the tab, clamped to fit below the top inset.
    var expandedSize: NSSize {
        NSSize(
            width: contentSize.width + Self.tabWidth,
            height: min(max(contentSize.height, Self.tabHeight), visibleFrame.height - Self.topInset)
        )
    }

    func frame(expanded: Bool) -> NSRect {
        let size = expanded ? expandedSize : NSSize(width: Self.tabWidth, height: Self.tabHeight)
        return pinned(NSRect(origin: .zero, size: size))
    }

    /// Keeps the requested size but moves it so the outer edge sits on the
    /// screen edge and the top sits `topInset` below the menu bar.
    func pinned(_ rect: NSRect) -> NSRect {
        let vis = visibleFrame
        var f = rect
        f.origin.x = side == .right ? vis.maxX - f.width : vis.minX
        f.origin.y = vis.maxY - Self.topInset - f.height
        return f
    }

    func snap() {
        panel?.setFrame(frame(expanded: expanded), display: true)
    }

    // MARK: Expand / collapse

    func toggle() {
        guard let panel else { return }
        expanded.toggle()
        applyResizability()
        let target = frame(expanded: expanded)
        // Go through NSWindow: `animator()` returns a proxy, and on the final
        // DockPanel type Swift calls the override directly with the proxy as
        // `self` (reading `dock` from it crashes). An NSWindow-typed call is an
        // objc message the proxy forwards to the real panel each frame.
        let window: NSWindow = panel
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(target, display: true)
        }, completionHandler: { [weak panel] in
            // A transparent window's shadow is computed from its content and
            // goes stale after a size change.
            Task { @MainActor in panel?.invalidateShadow() }
        })
    }

    /// Resizing only makes sense expanded; the tab has a fixed size.
    private func applyResizability() {
        guard let panel else { return }
        if expanded {
            panel.styleMask.insert(.resizable)
            panel.contentMinSize = NSSize(width: Self.minContent.width + Self.tabWidth,
                                          height: Self.minContent.height)
            panel.contentMaxSize = NSSize(width: Self.maxContent.width + Self.tabWidth,
                                          height: Self.maxContent.height)
        } else {
            panel.styleMask.remove(.resizable)
        }
    }

    // MARK: NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        // Only user drags change the saved size, not the slide animation.
        guard let panel, panel.inLiveResize, expanded else { return }
        contentSize = NSSize(width: panel.frame.width - Self.tabWidth, height: panel.frame.height)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard expanded else { return }
        UserDefaults.standard.set(Double(contentSize.width), forKey: "dockWidth")
        UserDefaults.standard.set(Double(contentSize.height), forKey: "dockHeight")
        panel?.invalidateShadow()
    }
}
