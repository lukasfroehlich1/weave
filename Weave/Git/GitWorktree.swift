import Foundation

enum GitWorktree {
    struct WorktreeInfo {
        let path: String
        let branch: String
        let head: String
        let bare: Bool
    }

    static func list(repoPath: String) throws -> [WorktreeInfo] {
        let output = try run(["git", "-C", repoPath, "worktree", "list", "--porcelain"])
        var worktrees: [WorktreeInfo] = []
        var currentPath: String?
        var currentBranch: String?
        var currentHead: String?
        var currentBare = false

        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("worktree ") {
                if let path = currentPath {
                    worktrees.append(WorktreeInfo(
                        path: path,
                        branch: currentBranch ?? "",
                        head: currentHead ?? "",
                        bare: currentBare
                    ))
                }
                currentPath = String(line.dropFirst("worktree ".count))
                currentBranch = nil
                currentHead = nil
                currentBare = false
            } else if line.hasPrefix("HEAD ") {
                currentHead = String(line.dropFirst("HEAD ".count))
            } else if line.hasPrefix("branch ") {
                let ref = String(line.dropFirst("branch ".count))
                currentBranch = ref.replacingOccurrences(of: "refs/heads/", with: "")
            } else if line == "bare" {
                currentBare = true
            }
        }

        if let path = currentPath {
            worktrees.append(WorktreeInfo(
                path: path,
                branch: currentBranch ?? "",
                head: currentHead ?? "",
                bare: currentBare
            ))
        }

        return worktrees
    }

    static func add(repoPath: String, path: String, branch: String, startPoint: String? = nil) throws {
        var args = ["git", "-C", repoPath, "worktree", "add", path, "-b", branch]
        if let startPoint { args.append(startPoint) }
        _ = try run(args)
        try? run(["git", "-C", path, "config", "--local", "push.autoSetupRemote", "true"])
    }

    static func hasCommits(repoPath: String) -> Bool {
        (try? run(["git", "-C", repoPath, "rev-parse", "--verify", "--quiet", "HEAD"])) != nil
    }

    static func defaultRemoteBranch(repoPath: String) -> String? {
        let candidates = ["main", "master", "develop", "trunk"]
        for name in candidates {
            let ref = "origin/\(name)"
            if (try? run(["git", "-C", repoPath, "rev-parse", "--verify", "--quiet", ref])) != nil {
                return ref
            }
        }
        return nil
    }

    static func remove(repoPath: String, path: String, force: Bool = false) throws {
        var args = ["git", "-C", repoPath, "worktree", "remove", path]
        if force { args.append("--force") }
        _ = try run(args)
    }

    static func deleteBranch(repoPath: String, branch: String) throws {
        _ = try run(["git", "-C", repoPath, "branch", "-D", branch])
    }

    static func isGitRepo(path: String) -> Bool {
        (try? run(["git", "-C", path, "rev-parse", "--git-dir"])) != nil
    }

    static func repoName(path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
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
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty
            {
                return path
            }
        } catch {}
        return ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
    }()

    static func run(_ args: [String], in directory: String? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        if let directory {
            process.currentDirectoryURL = URL(fileURLWithPath: directory)
        }

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = shellPath
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw GitError.commandFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return output
    }

    enum GitError: LocalizedError {
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case let .commandFailed(msg): msg
            }
        }
    }
}
