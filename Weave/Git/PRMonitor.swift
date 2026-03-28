import Foundation

enum PRState: String {
    case draft, open, merged, closed
}

struct PRInfo: Equatable {
    let number: Int
    let url: URL
    let state: PRState
}

enum PRMonitor {
    private struct GHPullRequest: Decodable {
        let number: Int
        let url: String
        let state: String
        let isDraft: Bool
    }

    static func fetchPR(repoPath: String, branch: String) -> PRInfo? {
        guard let output = try? run(
            ["gh", "pr", "list", "--head", branch, "--json", "number,url,state,isDraft", "--state", "all", "--limit", "5"],
            in: repoPath
        ) else { return nil }

        guard let data = output.data(using: .utf8),
              let prs = try? JSONDecoder().decode([GHPullRequest].self, from: data),
              !prs.isEmpty else { return nil }

        let best = prs.max { a, b in
            let aPriority = Self.priority(a)
            let bPriority = Self.priority(b)
            if aPriority != bPriority { return aPriority < bPriority }
            return a.number < b.number
        }!

        guard let url = URL(string: best.url) else { return nil }

        let state: PRState = switch best.state {
        case "MERGED": .merged
        case "CLOSED": .closed
        default: best.isDraft ? .draft : .open
        }

        return PRInfo(number: best.number, url: url, state: state)
    }

    private static func priority(_ pr: GHPullRequest) -> Int {
        switch pr.state {
        case "MERGED": return 1
        case "CLOSED": return 0
        default: return 2
        }
    }

    private static var shellPath: String = {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-ilc", "echo $PATH"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
                return path
            }
        } catch {}
        return ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
    }()

    private static func run(_ args: [String], in directory: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: directory)

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = shellPath
        process.environment = env

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NSError(domain: "PRMonitor", code: Int(process.terminationStatus))
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
