import SwiftUI

@main
struct WeaveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        Self.configureGhosttyEnvironment()
        GhosttyRuntime.shared.initialize()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
    }

    private static func configureGhosttyEnvironment() {
        let fm = FileManager.default
        if getenv("GHOSTTY_RESOURCES_DIR") == nil {
            let ghosttyAppResources = "/Applications/Ghostty.app/Contents/Resources/ghostty"
            if fm.fileExists(atPath: ghosttyAppResources) {
                setenv("GHOSTTY_RESOURCES_DIR", ghosttyAppResources, 1)
            }
        }
        if getenv("TERM") == nil {
            setenv("TERM", "xterm-ghostty", 1)
        }
        if getenv("TERM_PROGRAM") == nil {
            setenv("TERM_PROGRAM", "ghostty", 1)
        }
        unsetenv("CLAUDECODE")
    }
}
