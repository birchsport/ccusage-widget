# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
swift build                      # debug build
swift run CCUsageWidget          # build + launch the floating panel
swift build -c release           # release build
./build-app.sh                   # assemble ad-hoc signed .app bundle
./build-app-notarized.sh         # signed + notarized .app + .dmg (gitignored; contains Team ID)
```

There is no test target and no linter configured. `swift build` is the only correctness gate.

## Architecture

This is a **SwiftPM executable target** (not an Xcode project) that is run either directly via `swift run` or wrapped into a `.app` bundle by the `build-app*.sh` scripts. `Package.swift` declares a single `.executableTarget` with `path: "CCUsageWidget"` and excludes `Info.plist` from the compiled sources.

The app is a background-only LSUIElement process. There is **no SwiftUI `WindowGroup`** — `CCUsageWidgetApp.swift` declares only `Settings { EmptyView() }` as a scene. The entire UI is manually constructed in `AppDelegate.applicationDidFinishLaunching` by creating an `NSPanel` and setting an `NSHostingView(rootView: ContentView())` as its `contentView`. If you need to change window behavior (level, collection behavior, geometry, alpha), that lives in `AppDelegate.swift`, not in SwiftUI scene modifiers.

**Data flow:** `UsageViewModel` (an `@MainActor ObservableObject`) owns a `Timer.publish(every: 30)` Combine pipeline plus a `Task` that calls `runCommand()`. `runCommand()` spawns `/usr/bin/env npx ccusage@20.0.20 --json` via `Process()`, with `/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin` prepended to `PATH` so it resolves outside a shell session. Output is decoded into `UsageReport` / `DailyUsage` / `ModelBreakdown` from `Models.swift`. Because the app spawns a subprocess, **the bundle must not be sandboxed** — don't add App Sandbox entitlements.

**ccusage is pinned on purpose.** Its JSON shape changes between releases without notice — 20.x renamed each day's `date` key to `period`, which silently broke decoding under `@latest`. `DailyUsage` has a hand-written `init(from:)` that accepts either key. To bump the pin, run `npx ccusage@<new> --json`, diff its keys against `Models.swift`, then update the version string in `UsageViewModel.runCommand()`.

**Settings persistence:** opacity is stored via `@AppStorage("panelAlpha")` in `ContentView`. On change, `ContentView` walks `NSApp.windows` to find the `NSPanel` and updates its `alphaValue` directly — there is no binding from SwiftUI to the panel. `AppDelegate` reads the same `UserDefaults` key at launch to seed the initial alpha. The chart range (7/14/30 days) is `@AppStorage("chartDays")`; the chart and the "N-DAY TOTALS" card both use `chartWindow(report:)`, which counts **calendar** days ending today and zero-fills days ccusage omits (it only emits days with usage). The 7-day mode shows per-bar labels; 14/30 switch to thin bars with an axis row and hover readout, and the card keeps a fixed height so toggling doesn't shift the layout.

**Window moving/resizing:** the panel is `.resizable` (clamped by `contentMinSize`/`contentMaxSize`), and `hosting.sizingOptions = []` stops `NSHostingView` from pinning the window to the SwiftUI content's ideal size. Dragging is a SwiftUI `DragGesture` (`windowDrag` in `ContentView`) that follows `NSEvent.mouseLocation` and calls `setFrameOrigin` — `isMovableByWindowBackground` is deliberately **off** because SwiftUI claims the mouse-down, so AppKit's background drag never fires (and an `NSVisualEffectView` subclass overriding `mouseDown` doesn't receive it either). Size and position persist via `setFrameAutosaveName("CCUsagePanel")`, stored as `NSWindow Frame CCUsagePanel` in the `CCUsageWidget` defaults domain for `swift run`/Xcode builds and `com.birch.ccusagewidget` for the `.app`.

**Naming gotcha:** `ContentView.swift` defines a private color constant named `borderColor` (not `border`) because `border` collides with SwiftUI's `View.border(_:width:)` modifier when used inside `.stroke(...)`.

## Info.plist and bundling

`CCUsageWidget/Info.plist` is **not** processed by SwiftPM — it's only read by the `build-app*.sh` scripts when assembling the `.app` bundle. `CFBundleExecutable` must be the literal string `CCUsageWidget` (not `$(EXECUTABLE_NAME)`, which is an Xcode build variable and won't be substituted when the plist is copied directly). `LSUIElement=YES` is what hides the Dock icon; without a proper bundle (e.g. when running via `swift run`) the binary still works but macOS may show a generic Dock entry.

## Distribution

`build-app-notarized.sh` is gitignored because it hardcodes the Team ID and keychain profile name. It builds a universal (arm64 + x86_64) release binary, assembles the bundle, signs with `Developer ID Application` + hardened runtime, submits to Apple's notary service via a stored `notarytool` keychain profile, staples the ticket, and produces both a `.zip` and a `.dmg`. **Prefer the DMG for sharing** — zips extracted with Archive Utility can materialize AppleDouble `._*` sidecars inside the bundle, which breaks the code signature seal ("sealed resource is missing or invalid"). DMGs preserve xattrs correctly.

**Build output path gotcha:** both `build-app*.sh` scripts get the binary location from `swift build <same args> --show-bin-path` rather than hardcoding it. Newer SwiftPM writes universal builds to `.build/out/Products/Release`, not the old `.build/apple/Products/Release`; a hardcoded path once shipped a stale months-old binary that still passed signing and notarization. To confirm a DMG has the current code, mount it and `strings` the binary for the pinned `ccusage@…` version.
