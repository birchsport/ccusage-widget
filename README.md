# ccusage-widget

A lightweight macOS floating overlay that shows Claude Code token usage at a
glance. It runs `npx ccusage@latest --json` on a 30-second timer and renders
the results as an always-on-top, semi-transparent panel in the top-right of
your primary display.

## Features

- Floating `NSPanel` pinned above regular windows, visible on all Spaces
- Auto-refresh every 30 seconds, plus a manual refresh button
- Daily cost bar chart, today's token breakdown, per-model breakdown, 5-day totals
- Settings panel with an opacity slider and a quit button
- No Dock icon, no menu bar clutter (`LSUIElement`)

## Requirements

- macOS 13 (Ventura) or later
- Swift 5.9+ / Xcode 15+ command line tools
- Node.js with `npx` available on `PATH` at one of:
  `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`, `/bin`

The widget spawns `npx ccusage@latest --json` as a subprocess, so Node must be
reachable from a non-shell environment. If you use `nvm`/`fnm` with a custom
path, symlink `npx` into `/usr/local/bin` or install Node via Homebrew.

## Build and run

The project is a SwiftPM executable target. From the repo root:

```bash
swift build          # debug build
swift run CCUsageWidget
```

For a release build:

```bash
swift build -c release
.build/release/CCUsageWidget
```

Running via `swift run` launches the executable directly without a full `.app`
bundle. The floating panel appears immediately; quit from the gear menu or
with `Ctrl+C` in the terminal.

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
- **Want it somewhere other than top-right** — edit the `x`/`y` calculation
  in `AppDelegate.applicationDidFinishLaunching`.
