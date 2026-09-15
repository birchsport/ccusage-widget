import Foundation
import Combine

@MainActor
final class UsageViewModel: ObservableObject {
    @Published var report: UsageReport?
    @Published var errorMessage: String?
    @Published var isLoading: Bool = false
    @Published var lastUpdated: Date?
    @Published var activeBlock: UsageBlock?
    @Published var contexts: [SessionContext] = []

    private var cancellables = Set<AnyCancellable>()
    private var currentTask: Task<Void, Never>?

    init() {
        fetch()
        refreshContext()
        Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.fetch()
            }
            .store(in: &cancellables)
        // Transcript reads are local and cheap, so context can track a live
        // session much more closely than the npx-based fetch.
        Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshContext()
            }
            .store(in: &cancellables)
    }

    func refreshContext() {
        Task { [weak self] in
            let recent = await Task.detached(priority: .utility) { SessionContextReader.recent() }.value
            if self?.contexts != recent { self?.contexts = recent }
        }
    }

    func fetch() {
        currentTask?.cancel()
        isLoading = true
        currentTask = Task { [weak self] in
            guard let self else { return }
            do {
                // Runs alongside the daily report. Best-effort: a failure here
                // leaves the last block in place rather than blanking the panel.
                async let blocksOutput = try? self.runCommand(["blocks", "--active", "--json"])
                let output = try await self.runCommand(["--json"])
                guard !Task.isCancelled else { return }
                guard let data = output.data(using: .utf8) else {
                    throw NSError(domain: "CCUsage", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "Invalid UTF-8 output"])
                }
                let decoder = JSONDecoder()
                let parsed = try decoder.decode(UsageReport.self, from: data)
                self.report = parsed
                self.errorMessage = nil
                self.lastUpdated = Date()

                if let out = await blocksOutput, !Task.isCancelled,
                   let blocksData = out.data(using: .utf8),
                   let blocks = try? UsageBlock.decoder.decode(BlocksReport.self, from: blocksData) {
                    self.activeBlock = blocks.blocks.first { $0.isActive }
                }
            } catch {
                if !Task.isCancelled {
                    self.errorMessage = error.localizedDescription
                }
            }
            self.isLoading = false
        }
    }

    // Pinned: ccusage's JSON shape changes between releases (e.g. 20.x
    // renamed `date` -> `period`). Bump deliberately after checking output.
    nonisolated private static let ccusage = "ccusage@20.0.20"

    private func runCommand(_ args: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["npx", Self.ccusage] + args

                // Prepend common install locations so npx resolves outside a shell.
                var env = ProcessInfo.processInfo.environment
                let extra = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
                if let existing = env["PATH"], !existing.isEmpty {
                    env["PATH"] = "\(extra):\(existing)"
                } else {
                    env["PATH"] = extra
                }
                // Point ccusage where the context reader looks: a Finder-launched
                // .app never sees a shell's CLAUDE_CONFIG_DIR, and ccusage reads
                // only that dir when it's set.
                if let dir = UserDefaults.standard.string(forKey: "claudeConfigDir"), !dir.isEmpty {
                    env["CLAUDE_CONFIG_DIR"] = dir
                }
                process.environment = env

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                _ = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                let output = String(data: data, encoding: .utf8) ?? ""
                if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    continuation.resume(throwing: NSError(
                        domain: "CCUsage",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "No output from npx ccusage. Is npx on PATH?"]
                    ))
                    return
                }
                continuation.resume(returning: output)
            }
        }
    }
}
