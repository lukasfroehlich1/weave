import KeyboardShortcuts
import SwiftUI

@main
struct WeaveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()

    init() {
        Self.configureGhosttyEnvironment()
        GhosttyRuntime.shared.initialize()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState)
                .onAppear {
                    GhosttyRuntime.shared.appState = appState
                    Task { await appState.loadConfig() }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    (NSApp.delegate as? AppDelegate)?.updater.checkForUpdates()
                }
                .disabled(!((NSApp.delegate as? AppDelegate)?.updater.canCheckForUpdates ?? false))

                Toggle("Beta Updates", isOn: Binding(
                    get: { (NSApp.delegate as? AppDelegate)?.updater.betaUpdates ?? false },
                    set: { (NSApp.delegate as? AppDelegate)?.updater.betaUpdates = $0 }
                ))
            }

            CommandGroup(replacing: .newItem) {
                Button("New Thread") {
                    if let repo = appState.activeRepo ?? appState.repos.first {
                        appState.isCreatingThread = true
                        appState.creatingThreadRepoID = repo.id
                    }
                }
                .keyboardShortcut(for: .newThread)

                Button("New Tab") {
                    if let thread = appState.activeThread { appState.addTab(to: thread) }
                }
                .keyboardShortcut(for: .newTab)

                Button("Add Repository...") {
                    appState.showRepoPicker = true
                }
                .keyboardShortcut(for: .addRepo)

                Divider()

                Button("Close Tab") {
                    guard let thread = appState.activeThread, let tab = thread.activeTab else { return }
                    appState.closeTab(tab, in: thread)
                }
                .keyboardShortcut(for: .closeTab)
            }

            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") {
                    appState.toggleSidebar()
                }
                .keyboardShortcut(for: .toggleSidebar)
            }

            CommandMenu("Navigate") {
                Button("Next Thread") { appState.selectNextThread() }
                    .keyboardShortcut(for: .nextThread)
                Button("Previous Thread") { appState.selectPreviousThread() }
                    .keyboardShortcut(for: .previousThread)
                Divider()
                Button("Next Active Thread") { appState.selectNextActiveThread() }
                    .keyboardShortcut(for: .nextActiveThread)
                Button("Previous Active Thread") { appState.selectPreviousActiveThread() }
                    .keyboardShortcut(for: .previousActiveThread)
            }

            CommandMenu("Tabs") {
                ForEach(1 ..< 10, id: \.self) { n in
                    Button("Tab \(n)") { appState.selectTab(at: n - 1) }
                        .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
                }
                Button("Last Tab") { appState.selectLastTab() }
                    .keyboardShortcut("0", modifiers: .command)
            }

            CommandMenu("Thread") {
                Button("Open Worktree in Editor") {
                    if let thread = appState.activeThread { appState.openInEditor(thread) }
                }
                .keyboardShortcut(for: .openInEditor)

                Button("Open Pull Request") {
                    if let url = appState.activeThread?.prInfo?.url { NSWorkspace.shared.open(url) }
                }
                .keyboardShortcut(for: .openPR)
                .disabled(appState.activeThread?.prInfo == nil)

                Divider()

                Button("Delete Thread...") {
                    if let thread = appState.activeThread, !thread.isMainWorktree {
                        appState.threadToDelete = thread
                    }
                }
                .keyboardShortcut(for: .deleteThread)
                .disabled(appState.activeThread?.isMainWorktree == true)
            }
        }

        Settings {
            SettingsView(appState: appState)
        }
    }

    private static func configureGhosttyEnvironment() {
        if let resourcePath = Bundle.main.resourcePath {
            let ghosttyPath = resourcePath + "/ghostty"
            setenv("GHOSTTY_RESOURCES_DIR", ghosttyPath, 1)
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
