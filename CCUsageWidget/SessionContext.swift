import Foundation

/// Context usage of a Claude Code session, read straight from its transcript.
/// Transcripts are Claude Code's internal JSONL format, not a documented API,
/// so everything here fails soft (skips or returns empty) instead of throwing:
/// a format change should blank the context rows, not break the widget.
struct SessionContext: Identifiable, Equatable, Sendable {
    let id: String       // transcript path
    let project: String  // last path component of the session's cwd
    let model: String?
    let tokens: Int      // input + cache read + cache write of the latest turn
    let updated: Date    // transcript modification time
}

enum SessionContextReader {
    /// Directories that may hold `projects/<project>/<session>.jsonl`. A GUI app
    /// doesn't inherit shell env vars, so `CLAUDE_CONFIG_DIR` only applies under
    /// `swift run`/Xcode; the `claudeConfigDir` default covers the `.app`.
    static func projectRoots() -> [URL] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var dirs: [String] = []
        for source in [UserDefaults.standard.string(forKey: "claudeConfigDir"),
                       ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]] {
            guard let source else { continue }
            dirs += source.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        dirs += [home.appendingPathComponent(".config/claude").path,
                 home.appendingPathComponent(".claude").path]

        var seen = Set<String>()
        return dirs
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).appendingPathComponent("projects") }
            .filter { seen.insert($0.standardizedFileURL.path).inserted && fm.fileExists(atPath: $0.path) }
    }

    /// Sessions whose transcripts changed within `activeWithin`, newest first,
    /// capped at `limit`, so parallel sessions each get a row. If none are that
    /// recent, returns just the newest session so the row shows the last one
    /// instead of vanishing.
    static func recent(limit: Int = 3, activeWithin: TimeInterval = 15 * 60) -> [SessionContext] {
        let cutoff = Date().addingTimeInterval(-activeWithin)
        var results: [SessionContext] = []
        var staleAttempts = 0

        for candidate in transcriptsNewestFirst() {
            let isRecent = candidate.date >= cutoff
            if !isRecent {
                // Past the active window: only look for a fallback, and only
                // through a few files (a brand-new session may have no
                // assistant turn yet).
                if !results.isEmpty { break }
                staleAttempts += 1
                if staleAttempts > 5 { break }
            }
            guard let ctx = parse(candidate.url, updated: candidate.date) else { continue }
            results.append(ctx)
            if !isRecent || results.count >= limit { break }
        }
        return results
    }

    private static func transcriptsNewestFirst() -> [(url: URL, date: Date)] {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        var candidates: [(url: URL, date: Date)] = []

        for root in projectRoots() {
            guard let projects = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            for project in projects {
                // Session transcripts sit directly in the project dir; subagent
                // transcripts live deeper (<session>/subagents/) and are skipped.
                guard let files = try? fm.contentsOfDirectory(at: project, includingPropertiesForKeys: Array(keys)) else { continue }
                for file in files where file.pathExtension == "jsonl" {
                    if let date = try? file.resourceValues(forKeys: keys).contentModificationDate {
                        candidates.append((file, date))
                    }
                }
            }
        }
        return candidates.sorted { $0.date > $1.date }
    }

    /// Scans backwards from the end of the file for the last main-thread
    /// assistant turn that carries usage. Reads only the tail, widening once
    /// in case the final lines are huge (e.g. a large tool result).
    private static func parse(_ url: URL, updated: Date) -> SessionContext? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }

        let marker = Data("\"usage\"".utf8)
        for window: UInt64 in [256 * 1024, 4 * 1024 * 1024] {
            let start = size > window ? size - window : 0
            guard (try? handle.seek(toOffset: start)) != nil,
                  let data = try? handle.readToEnd() else { return nil }
            var lines = data.split(separator: UInt8(ascii: "\n"))
            if start > 0, !lines.isEmpty { lines.removeFirst() }  // probably cut mid-line
            for line in lines.reversed() where line.range(of: marker) != nil {
                if let ctx = context(from: line, url: url, updated: updated) { return ctx }
            }
            if start == 0 { break }
        }
        return nil
    }

    private static func context(from line: Data, url: URL, updated: Date) -> SessionContext? {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              obj["type"] as? String == "assistant",
              (obj["isSidechain"] as? Bool) != true,
              let message = obj["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any] else { return nil }

        let tokens = ["input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"]
            .reduce(0) { $0 + ((usage[$1] as? Int) ?? 0) }
        guard tokens > 0 else { return nil }  // synthetic/error turns report zeros

        let cwd = obj["cwd"] as? String
        return SessionContext(
            id: url.path,
            project: cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "session",
            model: message["model"] as? String,
            tokens: tokens,
            updated: updated
        )
    }
}
