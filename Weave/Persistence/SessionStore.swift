import Foundation

struct TabSnapshot: Codable, Sendable {
    var title: String
}

struct ThreadSession: Codable, Sendable {
    var branch: String
    var tabs: [TabSnapshot]
    var activeTabIndex: Int?
}

enum SessionStore {
    static let scrollbackDir = "~/.weave/scrollback".expandingTilde
    static let maxCharacters = 400_000

    static func scrollbackPath(branch: String, tabIndex: Int) -> String {
        let safe = branch.replacingOccurrences(of: "/", with: "_")
        return "\(scrollbackDir)/\(safe)/\(tabIndex).txt"
    }

    static func saveScrollback(_ text: String, branch: String, tabIndex: Int) {
        let path = scrollbackPath(branch: branch, tabIndex: tabIndex)
        let dir = (path as NSString).deletingLastPathComponent
        let fm = FileManager.default
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

        var content = text
        if content.count > maxCharacters {
            content = String(content.suffix(maxCharacters))
        }
        let ansiReset = "\u{001B}[0m"
        if content.contains("\u{001B}") {
            if !content.hasPrefix(ansiReset) { content = ansiReset + content }
            if !content.hasSuffix(ansiReset) { content += ansiReset }
        }

        fm.createFile(atPath: path, contents: content.data(using: .utf8))
    }

    static func loadScrollback(branch: String, tabIndex: Int) -> String? {
        let path = scrollbackPath(branch: branch, tabIndex: tabIndex)
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        let text = String(data: data, encoding: .utf8)
        return text?.isEmpty == true ? nil : text
    }

    static func removeScrollback(branch: String) {
        let safe = branch.replacingOccurrences(of: "/", with: "_")
        let dir = "\(scrollbackDir)/\(safe)"
        try? FileManager.default.removeItem(atPath: dir)
    }

    static func replayCommand(scrollbackPath: String) -> String {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        return "/bin/sh -c 'cat \"\(scrollbackPath)\" 2>/dev/null; rm -f \"\(scrollbackPath)\"; exec \"\(shell)\" -l'"
    }
}
