import SwiftUI
import AppKit

// MARK: - Palette

private let bg = Color.black.opacity(0.55)
private let surface = Color.white.opacity(0.04)
private let borderColor = Color.white.opacity(0.08)
private let dimText = Color.white.opacity(0.35)
private let bodyText = Color.white.opacity(0.75)
private let accent = Color(red: 0.25, green: 0.95, blue: 0.65)
private let opus = Color(red: 0.55, green: 0.40, blue: 1.00)
private let haiku = Color(red: 0.25, green: 0.75, blue: 1.00)
private let sonnet = Color(red: 1.00, green: 0.60, blue: 0.25)
private let barBg = Color.white.opacity(0.07)

private func modelColor(_ shortName: String) -> Color {
    switch shortName {
    case "Opus": return opus
    case "Haiku": return haiku
    case "Sonnet": return sonnet
    default: return accent
    }
}

// MARK: - Visual effect background

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var vm = UsageViewModel()
    @AppStorage("panelAlpha") private var panelAlpha: Double = 0.80
    @State private var showSettings = false
    @AppStorage("chartDays") private var chartDays: Int = 7
    @State private var hoveredDay: String?
    @State private var dragStart: (mouse: NSPoint, origin: NSPoint)?

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .cornerRadius(14)
            bg.cornerRadius(14)

            VStack(spacing: 10) {
                header
                Divider().background(borderColor)

                if showSettings {
                    settingsCard
                }

                if vm.report == nil && vm.isLoading {
                    Spacer()
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Fetching…")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(dimText)
                    }
                    Spacer()
                } else if let error = vm.errorMessage, vm.report == nil {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(sonnet)
                        Text(error)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(bodyText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                    }
                    Spacer()
                } else if let report = vm.report {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 10) {
                            dailyCostChart(report: report)
                            todayTokens(report: report)
                            todayByModel(report: report)
                            windowTotals(report: report)
                            allTimeTotals(report: report)
                        }
                        .padding(.bottom, 4)
                    }
                } else {
                    Spacer()
                }
            }
            .padding(12)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(borderColor, lineWidth: 1)
        )
        .gesture(windowDrag)
        .onAppear { applyAlphaToPanel(panelAlpha) }
        .onChange(of: panelAlpha) { newValue in
            applyAlphaToPanel(newValue)
        }
    }

    /// Moves the panel by following the cursor in screen coordinates (the
    /// gesture's own translation is useless here: the view moves with the
    /// window mid-drag). AppKit's background-drag never fires because SwiftUI
    /// claims the mouse-down. Buttons, the slider and the scroll area keep their
    /// own input, so this only catches drags that start on empty chrome.
    private var windowDrag: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { _ in
                guard let panel = NSApp.windows.first(where: { $0 is NSPanel }) else { return }
                let mouse = NSEvent.mouseLocation
                let start = dragStart ?? (mouse, panel.frame.origin)
                dragStart = start
                panel.setFrameOrigin(NSPoint(
                    x: start.origin.x + mouse.x - start.mouse.x,
                    y: start.origin.y + mouse.y - start.mouse.y
                ))
            }
            .onEnded { _ in dragStart = nil }
    }

    private func applyAlphaToPanel(_ value: Double) {
        for window in NSApp.windows where window is NSPanel {
            window.alphaValue = CGFloat(value)
        }
    }

    // MARK: Settings

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SETTINGS")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(dimText)

            HStack(spacing: 8) {
                Text("Opacity")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(bodyText)
                Slider(value: $panelAlpha, in: 0.2...1.0)
                    .controlSize(.small)
                Text("\(Int(panelAlpha * 100))%")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(dimText)
                    .frame(width: 32, alignment: .trailing)
            }

            Button(action: { NSApp.terminate(nil) }) {
                HStack(spacing: 5) {
                    Image(systemName: "power")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Quit")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                }
                .foregroundColor(sonnet)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(barBg)
                .cornerRadius(4)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(surface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(borderColor, lineWidth: 1))
        .cornerRadius(8)
    }

    // MARK: Header

    @State private var pulse = false

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(vm.isLoading ? dimText : accent)
                .frame(width: 6, height: 6)
                .opacity(vm.isLoading ? (pulse ? 0.3 : 1.0) : 1.0)
                .animation(
                    vm.isLoading
                        ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                        : .default,
                    value: pulse
                )
                .onAppear { pulse = true }

            Text("CC USAGE")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(2)
                .foregroundColor(accent)

            Spacer()

            if let updated = vm.lastUpdated {
                Text(timeString(updated))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(dimText)
            }

            Button(action: { vm.fetch() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(dimText)
            }
            .buttonStyle(.plain)

            Button(action: { showSettings.toggle() }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(showSettings ? accent : dimText)
            }
            .buttonStyle(.plain)
        }
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }

    // MARK: Daily cost chart

    private static let chartRanges = [7, 14, 30]

    private struct ChartDay: Identifiable {
        let id: String  // yyyy-MM-dd
        let cost: Double
        let isToday: Bool
    }

    /// The last `chartDays` calendar days ending today. ccusage omits days with
    /// no usage entirely, so those are filled in as zero-cost days.
    private func chartWindow(report: UsageReport) -> [ChartDay] {
        let costByDay = Dictionary(report.daily.map { ($0.date, $0.totalCost) }, uniquingKeysWith: +)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<chartDays).reversed().compactMap { offset in
            guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let key = DayKey.string(from: d)
            return ChartDay(id: key, cost: costByDay[key] ?? 0, isToday: offset == 0)
        }
    }

    /// 7 days fits per-bar cost/date labels in the 280pt panel; 14 and 30 don't,
    /// so those drop to thin bars with an axis row and a hover readout. The card
    /// keeps the same height in every mode so toggling doesn't shift the layout.
    private func dailyCostChart(report: UsageReport) -> some View {
        let days = chartWindow(report: report)
        let maxCost = max(days.map { $0.cost }.max() ?? 0, 0.01)
        let dense = days.count > 7
        let spacing: CGFloat = days.count > 14 ? 1.5 : (dense ? 3 : 4)
        // In 7-day mode 12pt of the 64pt plot goes to the cost label above each bar.
        let barMax: CGFloat = dense ? 64 : 52

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("DAILY COST")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(dimText)
                Spacer()
                rangePicker
            }

            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(days) { day in
                    let lit = day.isToday || day.id == hoveredDay
                    VStack(spacing: 3) {
                        if !dense {
                            Text(day.cost.asShortCost)
                                .font(.system(size: 7, design: .monospaced))
                                .foregroundColor(day.isToday ? accent : dimText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        RoundedRectangle(cornerRadius: dense ? 1 : 2)
                            .fill(day.cost == 0 ? barBg : (lit ? accent : accent.opacity(0.35)))
                            .frame(height: max(CGFloat(day.cost / maxCost) * barMax, 3))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside {
                            hoveredDay = day.id
                        } else if hoveredDay == day.id {
                            hoveredDay = nil
                        }
                    }
                }
            }
            .frame(height: 64)

            if dense {
                HStack {
                    Text(days.first.map { DayKey.shortLabel($0.id) } ?? "")
                    Spacer()
                    Text(chartReadout(days))
                        .foregroundColor(hoveredDay == nil ? dimText : accent)
                    Spacer()
                    Text("Today")
                }
                .font(.system(size: 7, design: .monospaced))
                .foregroundColor(dimText)
            } else {
                HStack(spacing: spacing) {
                    ForEach(days) { day in
                        Text(DayKey.shortLabel(day.id))
                            .font(.system(size: 7, design: .monospaced))
                            .foregroundColor(day.isToday ? accent : dimText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(10)
        .background(surface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(borderColor, lineWidth: 1))
        .cornerRadius(8)
    }

    /// Hovered day's cost, or the window's daily average when nothing is hovered.
    private func chartReadout(_ days: [ChartDay]) -> String {
        if let key = hoveredDay, let day = days.first(where: { $0.id == key }) {
            return "\(DayKey.shortLabel(day.id)) · \(day.cost.asCost)"
        }
        let avg = days.reduce(0) { $0 + $1.cost } / Double(max(days.count, 1))
        return "avg \(avg.asCost)/day"
    }

    private var rangePicker: some View {
        HStack(spacing: 2) {
            ForEach(Self.chartRanges, id: \.self) { n in
                Button(action: { chartDays = n }) {
                    Text("\(n)D")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundColor(chartDays == n ? accent : dimText)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(chartDays == n ? barBg : Color.clear)
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Today tokens

    private func todayTokens(report: UsageReport) -> some View {
        let today = report.daily.first(where: { $0.isToday }) ?? report.daily.last

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TODAY'S TOKENS")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(dimText)
                Spacer()
                if let t = today {
                    Text(t.totalTokens.compactTokens)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(accent)
                }
            }

            if let t = today {
                let total = max(t.totalTokens, 1)
                let segments: [(Int, Color)] = [
                    (t.cacheReadTokens, accent.opacity(0.8)),
                    (t.cacheCreationTokens, opus.opacity(0.8)),
                    (t.outputTokens, haiku.opacity(0.8)),
                    (t.inputTokens, sonnet.opacity(0.8))
                ]

                GeometryReader { geo in
                    HStack(spacing: 0) {
                        ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                            Rectangle()
                                .fill(seg.1)
                                .frame(width: geo.size.width * CGFloat(seg.0) / CGFloat(total))
                        }
                    }
                    .cornerRadius(3)
                }
                .frame(height: 6)

                VStack(spacing: 4) {
                    legendRow(color: accent.opacity(0.8), label: "Cache Read", value: t.cacheReadTokens)
                    legendRow(color: opus.opacity(0.8), label: "Cache Write", value: t.cacheCreationTokens)
                    legendRow(color: haiku.opacity(0.8), label: "Output", value: t.outputTokens)
                    legendRow(color: sonnet.opacity(0.8), label: "Input", value: t.inputTokens)
                }
            }
        }
        .padding(10)
        .background(surface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(borderColor, lineWidth: 1))
        .cornerRadius(8)
    }

    private func legendRow(color: Color, label: String, value: Int) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(bodyText)
            Spacer()
            Text(value.compactTokens)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(bodyText)
        }
    }

    // MARK: Today by model

    private func todayByModel(report: UsageReport) -> some View {
        let today = report.daily.first(where: { $0.isToday }) ?? report.daily.last
        let breakdowns = today?.modelBreakdowns ?? []
        let maxCost = max(breakdowns.map { $0.cost }.max() ?? 1, 0.01)

        return VStack(alignment: .leading, spacing: 8) {
            Text("TODAY BY MODEL")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(dimText)

            ForEach(Array(breakdowns.enumerated()), id: \.offset) { idx, m in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(m.shortName)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(modelColor(m.shortName))
                        Spacer()
                        Text(m.cost.asCost)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(bodyText)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1.5).fill(barBg)
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(modelColor(m.shortName))
                                .frame(width: geo.size.width * CGFloat(m.cost / maxCost))
                        }
                    }
                    .frame(height: 3)

                    HStack(spacing: 6) {
                        statPill(label: "in", value: m.inputTokens)
                        statPill(label: "out", value: m.outputTokens)
                        statPill(label: "cr", value: m.cacheReadTokens)
                    }
                }

                if idx < breakdowns.count - 1 {
                    Divider().background(borderColor)
                }
            }
        }
        .padding(10)
        .background(surface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(borderColor, lineWidth: 1))
        .cornerRadius(8)
    }

    private func statPill(label: String, value: Int) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(dimText)
            Text(value.compactTokens)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundColor(bodyText)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(barBg)
        .cornerRadius(3)
    }

    // MARK: Totals

    /// Sum of the same calendar window the daily chart shows, so the
    /// "N-DAY TOTALS" label stays truthful and matches the bars above.
    private func windowTotals(report: UsageReport) -> some View {
        let start = chartWindow(report: report).first?.id ?? ""
        let days = report.daily.filter { $0.date >= start }
        let cost = days.reduce(0) { $0 + $1.totalCost }
        let tokens = days.reduce(0) { $0 + $1.totalTokens }
        let output = days.reduce(0) { $0 + $1.outputTokens }
        let cacheCreate = days.reduce(0) { $0 + $1.cacheCreationTokens }

        return totalsCard(
            title: "\(chartDays)-DAY TOTALS",
            cost: cost,
            tokens: tokens,
            output: output,
            cacheCreate: cacheCreate
        )
    }

    /// ccusage's grand total across the full history it reports.
    private func allTimeTotals(report: UsageReport) -> some View {
        let t = report.totals
        return totalsCard(
            title: "ALL TIME",
            cost: t.totalCost,
            tokens: t.totalTokens,
            output: t.outputTokens,
            cacheCreate: t.cacheCreationTokens
        )
    }

    private func totalsCard(
        title: String,
        cost: Double,
        tokens: Int,
        output: Int,
        cacheCreate: Int
    ) -> some View {
        let cols = [GridItem(.flexible()), GridItem(.flexible())]

        return VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(dimText)

            LazyVGrid(columns: cols, spacing: 10) {
                totalCell(label: "COST", value: cost.asCost, color: accent)
                totalCell(label: "TOKENS", value: tokens.compactTokens, color: bodyText)
                totalCell(label: "OUTPUT", value: output.compactTokens, color: haiku)
                totalCell(label: "CACHE↑", value: cacheCreate.compactTokens, color: opus)
            }
        }
        .padding(10)
        .background(surface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(borderColor, lineWidth: 1))
        .cornerRadius(8)
    }

    private func totalCell(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 7, weight: .semibold, design: .monospaced))
                .tracking(1)
                .foregroundColor(dimText)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
