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
private let hot = Color(red: 1.00, green: 0.35, blue: 0.35)

private func modelColor(_ shortName: String) -> Color {
    switch shortName {
    case "Opus": return opus
    case "Haiku": return haiku
    case "Sonnet": return sonnet
    default: return accent
    }
}

private func durationString(_ seconds: TimeInterval) -> String {
    let minutes = max(Int(seconds / 60), 0)
    if minutes >= 24 * 60 { return "\(minutes / (24 * 60))d" }
    return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
}

/// Rough share of the 5h block used: this block's cost against the costliest
/// past block. Real plan limits aren't visible locally, so it's an estimate,
/// and it can pass 1 once this block outspends every earlier one.
private func blockFractionUsed(_ block: UsageBlock, peak: Double?) -> Double? {
    guard let peak, peak > 0 else { return nil }
    return block.costUSD / peak
}

private func usedColor(_ fraction: Double) -> Color {
    fraction < 0.5 ? accent : (fraction < 0.8 ? sonnet : hot)
}

private func percentUsed(_ fraction: Double) -> String {
    "~\(Int((fraction * 100).rounded()))% used"
}

private func peakHelp(_ peak: Double) -> String {
    "Estimate: this block's cost vs your costliest past 5h block (\(peak.asCost)). "
        + "Real plan limits aren't visible locally."
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
    @ObservedObject var vm: UsageViewModel
    @EnvironmentObject private var dock: DockController
    @AppStorage("panelAlpha") private var panelAlpha: Double = 0.80
    @State private var showSettings = false
    @AppStorage("chartDays") private var chartDays: Int = 7
    @AppStorage("contextWindow") private var contextWindow: Int = 200_000
    @AppStorage("collapsedCards") private var collapsedCards: String = ""  // comma-separated card ids
    @State private var hoveredDay: String?

    /// The panel's background and border live in `DockRootView` so the tab
    /// and this content read as one surface.
    var body: some View {
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
                        nowCard
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
        .onAppear { applyAlphaToPanel(panelAlpha) }
        .onChange(of: panelAlpha) { newValue in
            applyAlphaToPanel(newValue)
        }
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

            // Transcripts don't record whether a session uses the 1M option,
            // so the denominator is a setting (auto-bumped past 200K).
            HStack(spacing: 8) {
                Text("Context window")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(bodyText)
                Spacer()
                segmented([(200_000, "200K"), (1_000_000, "1M")], selection: $contextWindow)
            }

            HStack(spacing: 8) {
                Text("Dock side")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(bodyText)
                Spacer()
                segmented([(DockSide.left, "Left"), (DockSide.right, "Right")], selection: $dock.side)
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

        return card("dailyCost", "DAILY COST", trailing: { rangePicker }) {
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
        segmented(Self.chartRanges.map { ($0, "\($0)D") }, selection: $chartDays)
    }

    /// Small pill-style picker matching the widget's monospaced chrome.
    private func segmented<Value: Hashable>(_ options: [(Value, String)], selection: Binding<Value>) -> some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                let (value, label) = options[i]
                let selected = selection.wrappedValue == value
                Button(action: { selection.wrappedValue = value }) {
                    Text(label)
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundColor(selected ? accent : dimText)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(selected ? barBg : Color.clear)
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Card chrome

    /// Shared card frame. Clicking the title row rolls the card up to just
    /// that row and back; collapsed ids persist in `collapsedCards`. Header
    /// extras (`trailing`) hide while collapsed so only the title remains.
    private func card<Trailing: View, Content: View>(
        _ id: String,
        _ title: String,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let collapsed = isCollapsed(id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button(action: { toggleCollapsed(id) }) {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 7, weight: .bold))
                            .rotationEffect(.degrees(collapsed ? 0 : 90))
                        Text(title)
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .tracking(1.5)
                        Spacer(minLength: 0)
                    }
                    .foregroundColor(dimText)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(collapsed ? "Expand" : "Collapse")

                if !collapsed { trailing() }
            }
            if !collapsed { content() }
        }
        .padding(10)
        .background(surface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(borderColor, lineWidth: 1))
        .cornerRadius(8)
    }

    private func card<Content: View>(
        _ id: String,
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        card(id, title, trailing: { EmptyView() }, content: content)
    }

    private func isCollapsed(_ id: String) -> Bool {
        collapsedCards.split(separator: ",").contains { $0 == id }
    }

    private func toggleCollapsed(_ id: String) {
        var ids = Set(collapsedCards.split(separator: ",").map(String.init))
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        withAnimation(.easeInOut(duration: 0.15)) {
            collapsedCards = ids.sorted().joined(separator: ",")
        }
    }

    // MARK: Now

    /// Current 5-hour block (`ccusage blocks --active`) and the latest
    /// session's context fill (read from its transcript). Both are
    /// best-effort; each row falls back to a one-line note when data is
    /// missing. The timeline keeps countdown and idle text ticking between
    /// data refreshes.
    private var nowCard: some View {
        card("now", "NOW") {
            TimelineView(.periodic(from: Date(), by: 5)) { timeline in
                VStack(alignment: .leading, spacing: 8) {
                    blockRow(now: timeline.date)
                    Divider().background(borderColor)
                    contextRows(now: timeline.date)
                }
            }
        }
    }

    @ViewBuilder
    private func blockRow(now: Date) -> some View {
        if let block = vm.activeBlock, block.endTime > now {
            let span = block.endTime.timeIntervalSince(block.startTime)
            let elapsed = span > 0 ? now.timeIntervalSince(block.startTime) / span : 0
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("5h block · resets \(clockString(block.endTime))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(bodyText)
                    Spacer()
                    Text("\(durationString(block.endTime.timeIntervalSince(now))) left")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(accent)
                }
                meter(fraction: elapsed, color: accent)
                if let peak = vm.peakBlockCost, let used = blockFractionUsed(block, peak: peak) {
                    HStack {
                        Text("Usage")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(bodyText)
                        Text("vs \(peak.asCost) peak")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(dimText)
                        Spacer()
                        Text(percentUsed(used))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(usedColor(used))
                    }
                    .help(peakHelp(peak))
                    meter(fraction: used, color: usedColor(used))
                }
                Text(blockDetail(block))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(dimText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        } else {
            Text("No active 5h block; your next message starts one")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(dimText)
        }
    }

    private func blockDetail(_ block: UsageBlock) -> String {
        var parts = ["\(block.costUSD.asCost) so far"]
        if let rate = block.burnRate { parts.append("\(rate.costPerHour.asCost)/hr") }
        if let projected = block.projection { parts.append("~\(projected.totalCost.asCost) at reset") }
        return parts.joined(separator: " · ")
    }

    /// One row per recently active session (up to 3, newest first), or the
    /// last session alone when nothing is recent; see `SessionContextReader.recent`.
    @ViewBuilder
    private func contextRows(now: Date) -> some View {
        if vm.contexts.isEmpty {
            Text("No Claude Code session transcripts found")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(dimText)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(vm.contexts) { ctx in
                    contextRow(ctx, now: now)
                }
            }
        }
    }

    private func contextRow(_ ctx: SessionContext, now: Date) -> some View {
        // More tokens than the chosen window means the session must be on 1M.
        let window = ctx.tokens > contextWindow ? 1_000_000 : contextWindow
        let fraction = min(Double(ctx.tokens) / Double(window), 1)
        let color = fraction < 0.5 ? accent : (fraction < 0.8 ? sonnet : hot)
        let idle = now.timeIntervalSince(ctx.updated)
        let model = ctx.model.map(shortModelName) ?? "Claude"

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("Context")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(bodyText)
                Text(ctx.project)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(dimText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("\(ctx.tokens.compactTokens) / \(window == 1_000_000 ? "1M" : window.compactTokens)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(color)
            }
            meter(fraction: fraction, color: color)
            Text("\(model) · \(Int((fraction * 100).rounded()))% full · "
                 + (idle < 120 ? "active" : "idle \(durationString(idle))"))
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(dimText)
                .lineLimit(1)
        }
        // An old session's context is history, not "now"; fade it.
        .opacity(idle > 30 * 60 ? 0.55 : 1)
    }

    private func meter(fraction: Double, color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5).fill(barBg)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color)
                    .frame(width: geo.size.width * CGFloat(min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 3)
    }

    private func clockString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    // MARK: Today tokens

    private func todayTokens(report: UsageReport) -> some View {
        let today = report.daily.first(where: { $0.isToday }) ?? report.daily.last

        return card("todayTokens", "TODAY'S TOKENS", trailing: {
            if let t = today {
                Text(t.totalTokens.compactTokens)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(accent)
            }
        }) {
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

        return card("todayByModel", "TODAY BY MODEL") {
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
            id: "windowTotals",  // stable even though the title follows the range
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
            id: "allTime",
            title: "ALL TIME",
            cost: t.totalCost,
            tokens: t.totalTokens,
            output: t.outputTokens,
            cacheCreate: t.cacheCreationTokens
        )
    }

    private func totalsCard(
        id: String,
        title: String,
        cost: Double,
        tokens: Int,
        output: Int,
        cacheCreate: Int
    ) -> some View {
        let cols = [GridItem(.flexible()), GridItem(.flexible())]

        return card(id, title) {
            LazyVGrid(columns: cols, spacing: 10) {
                totalCell(label: "COST", value: cost.asCost, color: accent)
                totalCell(label: "TOKENS", value: tokens.compactTokens, color: bodyText)
                totalCell(label: "OUTPUT", value: output.compactTokens, color: haiku)
                totalCell(label: "CACHE↑", value: cacheCreate.compactTokens, color: opus)
            }
        }
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

// MARK: - Dock

/// Root of the panel: the edge tab plus the full widget beside it. Owns the
/// view model so both share one set of fetch timers.
struct DockRootView: View {
    @ObservedObject var dock: DockController
    @StateObject private var vm = UsageViewModel()

    var body: some View {
        let shape = EdgeDockedShape(side: dock.side, radius: 14)
        HStack(spacing: 0) {
            if dock.side == .left { tabColumn }
            contentColumn
            if dock.side == .right { tabColumn }
        }
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                bg
            }
            .clipShape(shape)
        )
        .overlay(shape.stroke(borderColor, lineWidth: 1))
        .environmentObject(dock)
    }

    /// Laid out at the expanded size and clipped toward the tab, so while the
    /// window animates the widget slides out from behind the tab instead of
    /// being squeezed.
    private var contentColumn: some View {
        ContentView(vm: vm)
            .frame(width: dock.contentSize.width, height: dock.expandedSize.height)
            // minWidth 0: otherwise the frame keeps the child's width and the
            // collapsed panel shows a slice of the widget instead of the tab.
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity,
                   alignment: dock.side == .right ? .topTrailing : .topLeading)
            .clipped()
            .allowsHitTesting(dock.expanded)
    }

    private var tabColumn: some View {
        DockTab(vm: vm, dock: dock)
            .frame(width: DockController.tabWidth, height: DockController.tabHeight)
            .frame(maxHeight: .infinity, alignment: .top)
            .overlay(alignment: dock.side == .right ? .leading : .trailing) {
                if dock.expanded {
                    Rectangle().fill(borderColor).frame(width: 1)
                }
            }
    }
}

/// The collapsed tab: a few headline numbers. Clicking it slides the panel
/// open or closed.
private struct DockTab: View {
    @ObservedObject var vm: UsageViewModel
    @ObservedObject var dock: DockController
    @State private var hovering = false
    @State private var pulse = false

    var body: some View {
        Button(action: { dock.toggle() }) {
            TimelineView(.periodic(from: Date(), by: 5)) { timeline in
                VStack(spacing: 7) {
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

                    VStack(spacing: 3) {
                        label("5H LEFT")
                        value(blockLeft(now: timeline.date), color: accent)
                        if let used = usageUsed(now: timeline.date) {
                            value(percentUsed(used), color: usedColor(used))
                        }
                    }
                    .help(vm.peakBlockCost.map(peakHelp) ?? "")

                    Rectangle().fill(borderColor).frame(height: 1)

                    VStack(spacing: 3) {
                        label("TODAY")
                        value(today.map { $0.totalCost.asCost } ?? "—", color: bodyText)
                        value(today.map { $0.totalTokens.compactTokens } ?? "—", color: haiku)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: chevron)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(hovering ? accent : dimText)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(hovering ? Color.white.opacity(0.05) : Color.clear)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(dock.expanded ? "Collapse" : "Expand")
    }

    /// Only today's own row; unlike the cards, don't fall back to the last day.
    private var today: DailyUsage? {
        guard let report = vm.report else { return nil }
        return report.daily.first(where: { $0.isToday })
    }

    private func blockLeft(now: Date) -> String {
        guard let block = vm.activeBlock, block.endTime > now else { return "—" }
        return durationString(block.endTime.timeIntervalSince(now))
    }

    private func usageUsed(now: Date) -> Double? {
        guard let block = vm.activeBlock, block.endTime > now else { return nil }
        return blockFractionUsed(block, peak: vm.peakBlockCost)
    }

    /// Points the way the panel will move when clicked.
    private var chevron: String {
        let opensLeft = dock.side == .right
        return dock.expanded == opensLeft ? "chevron.right" : "chevron.left"
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 7, weight: .semibold, design: .monospaced))
            .tracking(1)
            .foregroundColor(dimText)
            .lineLimit(1)
    }

    private func value(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(color)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

/// Rounded only on the inner side; the outer side is flush with the screen
/// edge. (`UnevenRoundedRectangle` needs macOS 14.)
private struct EdgeDockedShape: Shape {
    let side: DockSide
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.width / 2, rect.height / 2)
        let left = side == .right  // which vertical side gets rounded corners
        let (tl, bl, tr, br) = left ? (r, r, 0, 0) : (0, 0, r, r)

        var p = Path()
        p.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                 tangent2End: CGPoint(x: rect.maxX, y: rect.minY + tr), radius: tr)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                 tangent2End: CGPoint(x: rect.maxX - br, y: rect.maxY), radius: br)
        p.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                 tangent2End: CGPoint(x: rect.minX, y: rect.maxY - bl), radius: bl)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                 tangent2End: CGPoint(x: rect.minX + tl, y: rect.minY), radius: tl)
        p.closeSubpath()
        return p
    }
}
