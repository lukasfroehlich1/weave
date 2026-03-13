import AppKit

struct Editor: Identifiable, Equatable {
    let id: String
    let name: String
    let bundleID: String
    let iconName: String

    static let all: [Editor] = [
        Editor(id: "vscode", name: "VS Code", bundleID: "com.microsoft.VSCode", iconName: "curlybraces.square"),
        Editor(id: "cursor", name: "Cursor", bundleID: "com.todesktop.230313mzl4w4u92", iconName: "cursorarrow.rays"),
        Editor(id: "zed", name: "Zed", bundleID: "dev.zed.Zed", iconName: "chevron.left.forwardslash.chevron.right"),
        Editor(id: "windsurf", name: "Windsurf", bundleID: "com.exafunction.windsurf", iconName: "wind"),
        Editor(id: "xcode", name: "Xcode", bundleID: "com.apple.dt.Xcode", iconName: "hammer"),
        Editor(id: "sublime", name: "Sublime Text", bundleID: "com.sublimetext.4", iconName: "text.alignleft"),
    ]

    var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    var appIcon: NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    func open(path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-b", bundleID, path]
        try? process.run()
    }
}

enum EditorLauncher {
    static var installed: [Editor] {
        Editor.all.filter(\.isInstalled)
    }

    static func editor(forID id: String?) -> Editor? {
        guard let id else { return nil }
        return Editor.all.first { $0.id == id }
    }

    static var defaultEditor: Editor? {
        installed.first
    }
}
