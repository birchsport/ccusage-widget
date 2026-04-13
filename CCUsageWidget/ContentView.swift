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
                            fiveDayTotals(report: report)
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

    private func dailyCostChart(report: UsageReport) -> some View {
        let days = report.daily
        let maxCost = max(days.map { $0.totalCost }.max() ?? 1, 0.01)

        return VStack(alignment: .leading, spacing: 8) {
            Text("DAILY COST")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(dimText)

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(days) { day in
                    VStack(spacing: 3) {
                        Text(day.totalCost.asCost)
                            .font(.system(size: 7, design: .monospaced))
                            .foregroundColor(day.isToday ? accent : dimText)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(day.isToday ? accent : accent.opacity(0.35))
                            .frame(
                                height: max(CGFloat(day.totalCost / maxCost) * 52, 3)
                            )
                        Text(day.shortDate)
                            .font(.system(size: 7, design: .monospaced))
                            .foregroundColor(day.isToday ? accent : dimText)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(10)
        .background(surface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(borderColor, lineWidth: 1))
        .cornerRadius(8)
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

    // MARK: 5-day totals

    private func fiveDayTotals(report: UsageReport) -> some View {
        let t = report.totals
        let cols = [GridItem(.flexible()), GridItem(.flexible())]

        return VStack(alignment: .leading, spacing: 8) {
            Text("5-DAY TOTALS")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(dimText)

            LazyVGrid(columns: cols, spacing: 10) {
                totalCell(label: "COST", value: t.totalCost.asCost, color: accent)
                totalCell(label: "TOKENS", value: t.totalTokens.compactTokens, color: bodyText)
                totalCell(label: "OUTPUT", value: t.outputTokens.compactTokens, color: haiku)
                totalCell(label: "CACHE↑", value: t.cacheCreationTokens.compactTokens, color: opus)
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
