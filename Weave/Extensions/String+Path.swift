import Foundation

extension String {
    var expandingTilde: String {
        NSString(string: self).expandingTildeInPath
    }
}

enum WeaveHelpers {
    static func titleFromBranch(_ branch: String, prefix: String) -> String {
        var name = branch
        if !prefix.isEmpty, name.hasPrefix(prefix) {
            name = String(name.dropFirst(prefix.count))
        }
        return name.split(separator: "-").map(\.capitalized).joined(separator: " ")
    }

    static func sanitizeBranch(_ title: String, prefix: String) -> String {
        let slug = title
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .unicodeScalars.filter { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-") }
            .map { String($0) }.joined()
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return prefix + slug
    }

    static func displayTitle(_ title: String, worktreePath: String) -> String {
        guard !title.isEmpty else { return "Terminal" }
        let home = NSHomeDirectory()
        let prefixes = [worktreePath, worktreePath.hasPrefix(home) ? "~" + worktreePath.dropFirst(home.count) : nil]
            .compactMap { $0 }
        for prefix in prefixes {
            if title.hasPrefix(prefix) {
                let remainder = String(title.dropFirst(prefix.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
                return remainder.isEmpty ? "Terminal" : remainder
            }
        }
        return title
    }
}
