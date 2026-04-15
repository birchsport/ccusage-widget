import Foundation
import Combine

@MainActor
final class UsageViewModel: ObservableObject {
    @Published var report: CodeburnReport?
    @Published var errorMessage: String?
    @Published var isLoading: Bool = false
    @Published var lastUpdated: Date?

    private var cancellables = Set<AnyCancellable>()
    private var currentTask: Task<Void, Never>?

    init() {
        fetch()
        Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.fetch()
            }
            .store(in: &cancellables)
    }

    func fetch() {
        currentTask?.cancel()
        isLoading = true
        currentTask = Task { [weak self] in
            guard let self else { return }
            do {
                let jsonData = try await self.runCodeburn()
                guard !Task.isCancelled else { return }
                let decoder = JSONDecoder()
                let parsed = try decoder.decode(CodeburnReport.self, from: jsonData)
                self.report = parsed
                self.errorMessage = nil
                self.lastUpdated = Date()
            } catch {
                if !Task.isCancelled {
                    self.errorMessage = error.localizedDescription
                }
            }
            self.isLoading = false
        }
    }

    /// Runs `codeburn export -f json` in a scratch directory, parses the
    /// `Exported (...) to: <path>` line from stdout, and reads that file.
    private func runCodeburn() async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["codeburn", "export", "-f", "json"]

                // codeburn writes its json file to the current working directory,
                // so run it from a temp dir to keep things tidy.
                let tempDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("ccusage-widget", isDirectory: true)
                try? FileManager.default.createDirectory(
                    at: tempDir, withIntermediateDirectories: true
                )
                process.currentDirectoryURL = tempDir

                var env = ProcessInfo.processInfo.environment
                let extra = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
                if let existing = env["PATH"], !existing.isEmpty {
                    env["PATH"] = "\(extra):\(existing)"
                } else {
                    env["PATH"] = extra
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

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                if process.terminationStatus != 0 {
                    let msg = stderr.isEmpty ? stdout : stderr
                    continuation.resume(throwing: NSError(
                        domain: "CCUsage", code: Int(process.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey:
                            "codeburn failed: \(msg.trimmingCharacters(in: .whitespacesAndNewlines))"]
                    ))
                    return
                }

                // Parse the path out of a line like:
                //   "  Exported (...) to: /path/to/file.json"
                let combined = stdout + "\n" + stderr
                let path: String? = combined
                    .split(separator: "\n")
                    .compactMap { line -> String? in
                        guard let range = line.range(of: "to: ") else { return nil }
                        return String(line[range.upperBound...])
                            .trimmingCharacters(in: .whitespaces)
                    }
                    .first(where: { $0.hasSuffix(".json") })

                guard let jsonPath = path else {
                    continuation.resume(throwing: NSError(
                        domain: "CCUsage", code: 2,
                        userInfo: [NSLocalizedDescriptionKey:
                            "Could not find json path in codeburn output"]
                    ))
                    return
                }

                do {
                    let data = try Data(contentsOf: URL(fileURLWithPath: jsonPath))
                    // The file is regenerated on every run; remove it so we don't
                    // accumulate stale exports in the temp dir.
                    try? FileManager.default.removeItem(atPath: jsonPath)
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
