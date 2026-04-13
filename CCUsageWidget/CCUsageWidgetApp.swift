import AppKit
import SwiftUI

@main
struct CCUsageWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}
