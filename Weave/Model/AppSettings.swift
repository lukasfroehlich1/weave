import Foundation

@Observable
final class AppSettings: Codable {
    static var shared = AppSettings()

    var defaultEditor: String?
    var worktreeBase: String?
    var branchPrefix: String = ""
    var baseBranch: String?
    var deleteBranchOnRemove: Bool = true
    var forceRemoveWorktree: Bool = true

    var resolvedWorktreeBase: String {
        (worktreeBase ?? "~/.weave/worktrees").expandingTilde
    }

    enum CodingKeys: String, CodingKey {
        case defaultEditor, worktreeBase, branchPrefix, baseBranch
        case deleteBranchOnRemove, forceRemoveWorktree
    }

    init() {}

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        defaultEditor = try c.decodeIfPresent(String.self, forKey: .defaultEditor)
        worktreeBase = try c.decodeIfPresent(String.self, forKey: .worktreeBase)
        branchPrefix = try c.decodeIfPresent(String.self, forKey: .branchPrefix) ?? ""
        baseBranch = try c.decodeIfPresent(String.self, forKey: .baseBranch)
        deleteBranchOnRemove = try c.decodeIfPresent(Bool.self, forKey: .deleteBranchOnRemove) ?? true
        forceRemoveWorktree = try c.decodeIfPresent(Bool.self, forKey: .forceRemoveWorktree) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(defaultEditor, forKey: .defaultEditor)
        try c.encodeIfPresent(worktreeBase, forKey: .worktreeBase)
        try c.encode(branchPrefix, forKey: .branchPrefix)
        try c.encodeIfPresent(baseBranch, forKey: .baseBranch)
        try c.encode(deleteBranchOnRemove, forKey: .deleteBranchOnRemove)
        try c.encode(forceRemoveWorktree, forKey: .forceRemoveWorktree)
    }
}
