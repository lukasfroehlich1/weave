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
    static func fetchPR(repoPath: String, branch: String) -> PRInfo? {
        guard let remote = parseGitHubRemote(repoPath: repoPath),
              let token = getGitHubToken() else { return nil }

        let urlString = "https://api.github.com/repos/\(remote.owner)/\(remote.repo)/pulls?head=\(remote.owner):\(branch)&state=all&per_page=5"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let semaphore = DispatchSemaphore(value: 0)
        var result: PRInfo?

        URLSession.shared.dataTask(with: request) { data, response, _ in
            defer { semaphore.signal() }
            guard let data,
                  let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  let prs = try? JSONDecoder().decode([GitHubPR].self, from: data),
                  !prs.isEmpty else { return }

            let best = prs.max { priority($0) < priority($1) }!
            guard let prURL = URL(string: best.htmlURL) else { return }

            let state: PRState = switch best.state {
            case "closed": best.mergedAt != nil ? .merged : .closed
            default: best.draft ? .draft : .open
            }

            result = PRInfo(number: best.number, url: prURL, state: state)
        }.resume()

        semaphore.wait()
        return result
    }

    // MARK: - Private

    private struct GitHubPR: Decodable {
        let number: Int
        let htmlURL: String
        let state: String
        let draft: Bool
        let mergedAt: String?

        enum CodingKeys: String, CodingKey {
            case number
            case htmlURL = "html_url"
            case state
            case draft
            case mergedAt = "merged_at"
        }
    }

    private struct GitHubRemote {
        let owner: String
        let repo: String
    }

    private static func parseGitHubRemote(repoPath: String) -> GitHubRemote? {
        guard let output = try? GitWorktree.run(["git", "remote", "get-url", "origin"], in: repoPath)
        else { return nil }
        let url = output.trimmingCharacters(in: .whitespacesAndNewlines)

        if url.contains("github.com") {
            let cleaned = url.replacingOccurrences(of: ".git", with: "")
            if let range = cleaned.range(of: "github.com[:/]", options: .regularExpression) {
                let path = String(cleaned[range.upperBound...])
                let parts = path.split(separator: "/")
                if parts.count >= 2 {
                    return GitHubRemote(owner: String(parts[0]), repo: String(parts[1]))
                }
            }
        }
        return nil
    }

    private static var cachedToken: String?

    private static func getGitHubToken() -> String? {
        if let cached = cachedToken { return cached }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["credential", "fill"]

        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            stdin.fileHandleForWriting.write("protocol=https\nhost=github.com\n\n".data(using: .utf8)!)
            stdin.fileHandleForWriting.closeFile()
            process.waitUntilExit()

            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }

            let match = output.range(of: "password=(.+)", options: .regularExpression)
            if let match {
                let line = output[match]
                let token = String(line.dropFirst("password=".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                cachedToken = token
                return token
            }
        } catch {}

        return nil
    }

    private static func priority(_ pr: GitHubPR) -> Int {
        switch pr.state {
        case "closed": pr.mergedAt != nil ? 1 : 0
        default: 2
        }
    }
}
