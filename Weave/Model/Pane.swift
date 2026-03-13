import Foundation

@MainActor
@Observable
class Pane: Identifiable, Codable {
    let id: UUID
    private(set) var surfaceView: GhosttySurfaceView?
    var agentStatus: AgentStatus = .idle

    enum CodingKeys: String, CodingKey {
        case id
    }

    init(id: UUID = UUID()) {
        self.id = id
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
    }

    func attachSurface(
        workingDirectory: String,
        command: String? = nil,
        configure: (GhosttySurfaceView) -> Void
    ) {
        let surface = surfaceView ?? GhosttySurfaceView.create(
            workingDirectory: workingDirectory,
            command: command,
            paneID: id
        )
        configure(surface)
        surfaceView = surface
    }

    func tearDownSurface() {
        surfaceView?.removeFromSuperview()
        surfaceView = nil
    }

    func send(text: String) {
        guard let surface = surfaceView?.surface else { return }
        text.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(text.utf8.count))
        }
    }

    func saveScrollback() {
        guard let text = surfaceView?.readScrollback() else { return }
        let path = Self.scrollbackPath(for: id)
        let dir = (path as NSString).deletingLastPathComponent
        let fm = FileManager.default
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

        var content = text
        let maxCharacters = 400_000
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

    func removeScrollback() {
        try? FileManager.default.removeItem(atPath: Self.scrollbackPath(for: id))
    }

    var replayCommand: String? {
        let path = Self.scrollbackPath(for: id)
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        return "/bin/sh -c 'cat \"\(path)\" 2>/dev/null; rm -f \"\(path)\"; exec \"\(shell)\" -l'"
    }

    private static let scrollbackDir: String = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("dev.weave.app/scrollback").path
    }()

    static func scrollbackPath(for id: UUID) -> String {
        "\(scrollbackDir)/\(id.uuidString).txt"
    }
}
