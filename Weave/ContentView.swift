import SwiftUI

struct ContentView: View {
    @Bindable var appState: AppState
    @State private var sidebarWidth: CGFloat = 300

    private let titleBarHeight: CGFloat = 46

    var body: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                SidebarView(appState: appState)
                    .frame(width: sidebarWidth)
                    .frame(width: appState.isSidebarCollapsed ? 0 : sidebarWidth, alignment: .leading)
                    .clipped()
                    .background(Theme.sidebarBackground)
                    .overlay(alignment: .trailing) {
                        if !appState.isSidebarCollapsed {
                            SidebarDragHandle(sidebarWidth: $sidebarWidth)
                                .offset(x: 5)
                        }
                    }

                Group {
                    if let thread = appState.activeThread {
                        if thread.tabs.isEmpty {
                            threadEmptyState(thread)
                        } else {
                            ZStack(alignment: .top) {
                                VStack(spacing: 0) {
                                    if thread.tabs.count > 1 {
                                        TabBarView(appState: appState, thread: thread)
                                    }
                                    Divider().opacity(0.3)
                                    TerminalView(surfaceView: thread.activeTab?.activePane?.surfaceView)
                                }

                                if appState.search.isActive {
                                    SearchBar(appState: appState, surface: thread.activeTab?.activePane?.surfaceView)
                                        .padding(.top, thread.tabs.count > 1 ? 32 : 4)
                                        .padding(.trailing, 8)
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                }
                            }
                        }
                    } else {
                        emptyState
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.top, titleBarHeight)

            customTitleBar
                .background(WindowDragView())
        }
        .ignoresSafeArea(.all)
        .frame(minWidth: 700, minHeight: 400)
        .background(TrafficLightConfigurator(titleBarHeight: titleBarHeight))
        .fileImporter(
            isPresented: $appState.showRepoPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first {
                Task { await appState.addRepo(path: url.path) }
            }
        }
        .alert("Error", isPresented: .init(
            get: { appState.error != nil },
            set: { if !$0 { appState.error = nil } }
        )) {
            Button("OK") { appState.error = nil }
        } message: {
            Text(appState.error ?? "")
        }
        .alert("Delete Thread?", isPresented: .init(
            get: { appState.threadToDelete != nil },
            set: { if !$0 { appState.threadToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { appState.threadToDelete = nil }
            Button("Delete") {
                if let thread = appState.threadToDelete {
                    appState.threadToDelete = nil
                    Task { await appState.deleteThread(thread) }
                }
            }
            .keyboardShortcut(.defaultAction)
        } message: {
            if let thread = appState.threadToDelete {
                Text("This will remove the worktree and branch '\(thread.branch)'.")
            }
        }
    }

    // MARK: - Title bar

    private var customTitleBar: some View {
        HStack(spacing: 0) {
            HStack(alignment: .center, spacing: 6) {
                Spacer().frame(width: 84)

                IconAccessoryButton(icon: "sidebar.left", size: 14, tooltip: "Toggle Sidebar (⌘B)") {
                    appState.toggleSidebar()
                }

                IconAccessoryButton(icon: "folder.badge.plus", size: 14, tooltip: "Add Repository (⇧⌘O)") {
                    appState.showRepoPicker = true
                }
                .offset(y: -1)
            }
            .frame(width: appState.isSidebarCollapsed ? 170 : sidebarWidth, alignment: .leading)

            if let thread = appState.activeThread {
                ThreadHeaderView(appState: appState, thread: thread)
            }

            Spacer()

            EditorButton(appState: appState)
                .padding(.trailing, Theme.paddingH)
        }
        .frame(height: titleBarHeight)
        .background {
            HStack(spacing: 0) {
                Theme.sidebarBackground
                    .frame(width: appState.isSidebarCollapsed ? 0 : sidebarWidth)
                Color(nsColor: .windowBackgroundColor)
            }
        }
    }

    // MARK: - Empty states

    private func threadEmptyState(_ thread: WeaveThread) -> some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 4) {
                emptyStateAction(icon: "terminal", label: "Open Terminal", shortcut: "⌘T") {
                    appState.addTab(to: thread)
                }
                emptyStateAction(icon: "arrow.up.forward.square", label: "Open Worktree in Editor", shortcut: "⌘O") {
                    appState.openInEditor(thread)
                }
            }
            .frame(maxWidth: 260)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyStateAction(
        icon: String,
        label: String,
        shortcut: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 12))
                        .foregroundStyle(.quaternary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            if appState.repos.isEmpty {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Add a Git Repository")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Click the folder icon to add one")
                    .foregroundStyle(.tertiary)
            } else {
                Image(systemName: "terminal")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("No threads yet")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Press ⌘N to create a new thread")
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension Notification.Name {
    static let weaveRenameThread = Notification.Name("weave.renameThread")
}
