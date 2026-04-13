import Foundation
import Combine

@MainActor
final class UsageViewModel: ObservableObject {
    @Published var report: UsageReport?
    @Published var errorMessage: String?
    @Published var isLoading: Bool = false
    @Published var lastUpdated: Date?

    private var cancellables = Set<AnyCancellable>()
    private var currentTask: Task<Void, Never>?

    init() {
        fetch()
        Timer.publish(every: 30, on: .main, in: .common)
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
                let output = try await self.runCommand()
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
            } catch {
                if !Task.isCancelled {
                    self.errorMessage = error.localizedDescription
                }
            }
            self.isLoading = false
        }
    }

    private func runCommand() async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["npx", "ccusage@latest", "--json"]

                // Prepend common install locations so npx resolves outside a shell.
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
