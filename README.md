# ccusage-widget

A lightweight macOS floating overlay that shows Claude Code token usage at a
glance. It runs `npx ccusage@20.0.20 --json` on a 30-second timer and renders
the results as an always-on-top, semi-transparent panel. It starts in the
top-right of your primary display; drag or resize it and it reopens where you
left it.

## Features

- Floating `NSPanel` pinned above regular windows, visible on all Spaces
- Auto-refresh every 30 seconds, plus a manual refresh button
- Daily cost bar chart with a 7 / 14 / 30 day toggle (7 by default); hover a
  bar in the 14/30-day views to see that day's cost
- Today's token breakdown, per-model breakdown, totals for the selected range,
  and all-time totals
- Drag from the header or margins to move; drag any edge to resize; size and
  position are remembered across launches
- Settings panel with an opacity slider and a quit button
- No Dock icon, no menu bar clutter (`LSUIElement`)

## Requirements

- macOS 13 (Ventura) or later
- Swift 5.9+ / Xcode 15+ command line tools
- Node.js with `npx` available on `PATH` at one of:
  `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`, `/bin`

The widget spawns `npx ccusage@20.0.20 --json` as a subprocess, so Node must be
reachable from a non-shell environment. If you use `nvm`/`fnm` with a custom
path, symlink `npx` into `/usr/local/bin` or install Node via Homebrew.

The ccusage version is pinned because its JSON output changes between
releases (20.x renamed each day's `date` field to `period`, which broke the
widget under `@latest`). To upgrade, check the new version's `--json` output
against `Models.swift`, then bump the version in `UsageViewModel.swift`.

## Build and run

The project is a SwiftPM executable target. From the repo root:

```bash
swift build          # debug build
swift run CCUsageWidget
```

For a release build:

```bash
swift build -c release
"$(swift build -c release --show-bin-path)/CCUsageWidget"
```

(Newer SwiftPM puts build output under `.build/out/Products/…` rather than
`.build/release`, so ask it for the path instead of hardcoding one.)

Running via `swift run` launches the executable directly without a full `.app`
bundle. The floating panel appears immediately; quit from the gear menu or
with `Ctrl+C` in the terminal. You can also open `Package.swift` in Xcode and
run the `CCUsageWidget` scheme.

## Packaging

```bash
./build-app.sh
```

Builds a universal (arm64 + x86_64) release binary and assembles an ad-hoc
signed `CCUsageWidget.app` plus a `.zip`. Recipients need to right-click →
Open the first time, or run `xattr -dr com.apple.quarantine CCUsageWidget.app`.
A Developer ID signed and notarized DMG needs your own signing setup (see
`CLAUDE.md`).

## Project layout

```
ccusage-widget/
├── Package.swift
└── CCUsageWidget/
    ├── Info.plist
    ├── CCUsageWidgetApp.swift   # @main entry point
    ├── AppDelegate.swift        # NSPanel setup + window geometry
    ├── ContentView.swift        # SwiftUI view, palette, settings card
    ├── Models.swift             # Codable models for ccusage JSON
    └── UsageViewModel.swift     # fetch loop + subprocess runner
```

## Troubleshooting

- **"No output from npx ccusage"** — `npx` isn't on one of the paths the
  widget prepends. Install Node via Homebrew or symlink `npx` into
  `/usr/local/bin`.
- **Panel doesn't appear** — check that another fullscreen app isn't covering
  it. The panel uses `.floating` level; raise it to `.screenSaver` in
  `AppDelegate.swift` if you need it above more aggressive windows.
- **Panel shows a decode error or nothing after a ccusage release** — the
  JSON shape likely changed. See the pinning note under Requirements.
- **Panel opens off-screen or you want the default spot back** — reset the
  saved frame, then relaunch:
  `defaults delete CCUsageWidget "NSWindow Frame CCUsagePanel"` (for
  `swift run`/Xcode) or `defaults delete com.birch.ccusagewidget
  "NSWindow Frame CCUsagePanel"` (for the `.app`).
