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
private let pink = Color(red: 1.00, green: 0.45, blue: 0.75)
private let barBg = Color.white.opacity(0.07)

private func modelColor(_ shortName: String) -> Color {
    switch shortName {
    case "Opus": return opus
    case "Haiku": return haiku
    case "Sonnet": return sonnet
    default: return accent
    }
}

private let activityPalette: [Color] = [accent, opus, haiku, sonnet, pink,
                                        accent.opacity(0.6), opus.opacity(0.6),
                                        haiku.opacity(0.6)]

private func activityColor(_ index: Int) -> Color {
    activityPalette[index % activityPalette.count]
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
    @AppStorage("selectedPeriod") private var selectedPeriodRaw: String = PeriodKey.today.rawValue
    @State private var showSettings = false

    private var selectedPeriod: PeriodKey {
        get { PeriodKey(rawValue: selectedPeriodRaw) ?? .today }
    }

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
                    let period = report.periods.period(for: selectedPeriod)

                    periodPicker

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 10) {
                            summaryCard(period: period)
                            dailyCostChart(period: period)
                            activityCard(period: period)
                            modelsCard(period: period)
                            projectsCard(report.projects)
                            toolsCard(report.tools)
                            shellCard(report.shellCommands)
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

            Text("CODEBURN")
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

    // MARK: Period picker

    private var periodPicker: some View {
        HStack(spacing: 4) {
            ForEach(PeriodKey.allCases) { key in
                let isSelected = key == selectedPeriod
                Button(action: { selectedPeriodRaw = key.rawValue }) {
                    Text(key.short)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(isSelected ? .black : bodyText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(isSelected ? accent : barBg)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Summary

    private func summaryCard(period: Period) -> some View {
        let s = period.summary
        let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

        return VStack(alignment: .leading, spacing: 8) {
            Text(s.period.uppercased())
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(dimText)

            LazyVGrid(columns: cols, spacing: 6) {
                totalCell(label: "COST", value: s.cost.asCost, color: accent)
                totalCell(label: "CALLS", value: s.apiCalls.compact, color: haiku)
                totalCell(label: "SESSIONS", value: "\(s.sessions)", color: opus)
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
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Daily cost chart

    private func dailyCostChart(period: Period) -> some View {
        let days = period.daily
        let maxCost = max(days.map { $0.cost }.max() ?? 1, 0.01)

        return VStack(alignment: .leading, spacing: 8) {
            Text("DAILY COST")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(dimText)

            if days.isEmpty {
                Text("no data")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(dimText)
            } else {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(days) { day in
                        VStack(spacing: 3) {
                            Text(day.cost.asCost)
                                .font(.system(size: 7, design: .monospaced))
                                .foregroundColor(day.isToday ? accent : dimText)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(day.isToday ? accent : accent.opacity(0.35))
                                .frame(
                                    height: max(CGFloat(day.cost / maxCost) * 52, 3)
                                )
                            Text(day.shortDate)
                                .font(.system(size: 7, design: .monospaced))
                                .foregroundColor(day.isToday ? accent : dimText)
                        }
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

    // MARK: Activity

    private func activityCard(period: Period) -> some View {
        let items = period.activity
        let maxCost = max(items.map { $0.cost }.max() ?? 1, 0.01)

        return VStack(alignment: .leading, spacing: 8) {
            Text("ACTIVITY")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(dimText)

            ForEach(Array(items.enumerated()), id: \.offset) { idx, a in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(a.activity)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(bodyText)
                        Spacer()
                        Text("\(a.turns)t")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(dimText)
                        Text(a.cost.asCost)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(bodyText)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1.5).fill(barBg)
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(activityColor(idx))
                                .frame(width: geo.size.width * CGFloat(a.cost / maxCost))
                        }
                    }
                    .frame(height: 3)
                }
            }
        }
        .padding(10)
        .background(surface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(borderColor, lineWidth: 1))
        .cornerRadius(8)
    }

    // MARK: Models

    private func modelsCard(period: Period) -> some View {
        let items = period.models
        let maxCost = max(items.map { $0.cost }.max() ?? 1, 0.01)

        return VStack(alignment: .leading, spacing: 8) {
            Text("MODELS")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(dimText)

            ForEach(Array(items.enumerated()), id: \.offset) { idx, m in
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
                        statPill(label: "calls", value: m.apiCalls)
                        statPill(label: "in", value: m.inputTokens)
                        statPill(label: "out", value: m.outputTokens)
                    }
                }

                if idx < items.count - 1 {
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
            Text(value.compact)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundColor(bodyText)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(barBg)
        .cornerRadius(3)
    }

    // MARK: Projects

    private func projectsCard(_ all: [ProjectStat]) -> some View {
        let items = Array(all.prefix(5))
        let maxCost = max(items.map { $0.cost }.max() ?? 1, 0.01)

        return VStack(alignment: .leading, spacing: 8) {
            Text("PROJECTS")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(dimText)

            ForEach(Array(items.enumerated()), id: \.offset) { idx, p in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(p.displayName)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(bodyText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(p.cost.asCost)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(bodyText)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1.5).fill(barBg)
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(accent.opacity(0.7))
                                .frame(width: geo.size.width * CGFloat(p.cost / maxCost))
                        }
                    }
                    .frame(height: 3)
                    HStack(spacing: 6) {
                        statPill(label: "calls", value: p.apiCalls)
                        statPill(label: "sess", value: p.sessions)
                    }
                }
                if idx < items.count - 1 {
                    Divider().background(borderColor)
                }
            }
        }
        .padding(10)
        .background(surface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(borderColor, lineWidth: 1))
        .cornerRadius(8)
    }

    // MARK: Tools

    private func toolsCard(_ all: [ToolStat]) -> some View {
        let items = Array(all.prefix(8))
        let maxCalls = max(items.map { $0.calls }.max() ?? 1, 1)

        return VStack(alignment: .leading, spacing: 8) {
            Text("TOOLS")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(dimText)

            ForEach(Array(items.enumerated()), id: \.offset) { _, t in
                HStack(spacing: 8) {
                    Text(t.tool)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(bodyText)
                        .frame(width: 72, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1.5).fill(barBg)
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(haiku.opacity(0.8))
                                .frame(width: geo.size.width * CGFloat(t.calls) / CGFloat(maxCalls))
                        }
                    }
                    .frame(height: 3)
                    Text("\(t.calls)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(bodyText)
                        .frame(width: 32, alignment: .trailing)
                }
            }
        }
        .padding(10)
        .background(surface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(borderColor, lineWidth: 1))
        .cornerRadius(8)
    }

    // MARK: Shell commands

    private func shellCard(_ all: [ShellCommandStat]) -> some View {
        let items = Array(all.prefix(8))
        let maxCalls = max(items.map { $0.calls }.max() ?? 1, 1)

        return VStack(alignment: .leading, spacing: 8) {
            Text("SHELL COMMANDS")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(dimText)

            ForEach(Array(items.enumerated()), id: \.offset) { _, c in
                HStack(spacing: 8) {
                    Text(c.command)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(bodyText)
                        .frame(width: 72, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1.5).fill(barBg)
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(sonnet.opacity(0.8))
                                .frame(width: geo.size.width * CGFloat(c.calls) / CGFloat(maxCalls))
                        }
                    }
                    .frame(height: 3)
                    Text("\(c.calls)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(bodyText)
                        .frame(width: 32, alignment: .trailing)
                }
            }
        }
        .padding(10)
        .background(surface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(borderColor, lineWidth: 1))
        .cornerRadius(8)
    }
}
