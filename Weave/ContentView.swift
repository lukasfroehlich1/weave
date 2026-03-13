import SwiftUI

struct ContentView: View {
    @State private var store = ThreadStore()
    @State private var sidebarWidth: CGFloat = 300
    @State private var isSidebarCollapsed = false
    @State private var showRepoPicker = false
    @State private var keyMonitor: Any?

    var body: some View {
        HStack(spacing: 0) {
            if !isSidebarCollapsed {
                SidebarView(store: store)
                    .frame(width: sidebarWidth)
                    .background(.ultraThickMaterial)

                Divider().opacity(0.4)
            }

            Group {
                if let thread = store.activeThread {
                    if thread.tabs.isEmpty {
                        threadEmptyState(thread)
                    } else {
                        VStack(spacing: 0) {
                            if thread.tabs.count > 1 {
                                TabBarView(store: store, thread: thread)
                                Divider().opacity(0.3)
                            }
                            TerminalView(surfaceView: thread.activeTab?.surfaceView)
                        }
                    }
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 700, minHeight: 400)
        .background(WindowConfigurator())
        .fileImporter(
            isPresented: $showRepoPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await store.addRepo(path: url.path) }
            }
        }
        .background {
            Group {
                Button("") {
                    if let repo = store.activeRepo ?? store.repos.first {
                        store.isCreatingThread = true
                        store.creatingThreadRepoID = repo.id
                    }
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("") {
                    withAnimation(.easeInOut(duration: 0.2)) { isSidebarCollapsed.toggle() }
                }
                .keyboardShortcut("\\", modifiers: .command)

                Button("") {
                    if let thread = store.activeThread {
                        store.addTab(to: thread)
                    }
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("") {
                    guard let thread = store.activeThread, let tab = thread.activeTab else { return }
                    store.closeTab(tab, in: thread)
                }
                .keyboardShortcut("w", modifiers: .command)

                Button("") {
                    if let thread = store.activeThread {
                        store.openInEditor(thread)
                    }
                }
                .keyboardShortcut("o", modifiers: .command)

            }
            .hidden()
        }
        .onAppear {
            GhosttyRuntime.shared.store = store
            Task { await store.loadConfig() }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let flags = event.modifierFlags
                let hasOpt = flags.contains(.option)
                let hasShift = flags.contains(.shift)
                let hasCmd = flags.contains(.command)
                let hasCtrl = flags.contains(.control)
                guard hasOpt && !hasCmd && !hasCtrl else { return event }

                if !hasShift && event.keyCode == 13 { // W
                    if let thread = store.activeThread {
                        store.threadToDelete = thread
                    }
                    return nil
                }

                if !hasShift {
                    switch event.keyCode {
                    case 125, 38: // ↓, J
                        store.selectNextThread()
                        return nil
                    case 126, 40: // ↑, K
                        store.selectPreviousThread()
                        return nil
                    default: break
                    }
                } else {
                    switch event.keyCode {
                    case 125, 38: // ↓, J
                        store.selectNextActiveThread()
                        return nil
                    case 126, 40: // ↑, K
                        store.selectPreviousActiveThread()
                        return nil
                    default: break
                    }
                }
                return event
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .weaveToggleSidebar)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { isSidebarCollapsed.toggle() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .weaveAddRepo)) { _ in
            self.showRepoPicker = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .weaveOpenInEditor)) { _ in
            if let thread = store.activeThread {
                store.openInEditor(thread)
            }
        }
        .alert("Error", isPresented: .init(
            get: { store.error != nil },
            set: { if !$0 { store.error = nil } }
        )) {
            Button("OK") { store.error = nil }
        } message: {
            Text(store.error ?? "")
        }
        .alert("Delete Thread?", isPresented: .init(
            get: { store.threadToDelete != nil },
            set: { if !$0 { store.threadToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { store.threadToDelete = nil }
            Button("Delete") {
                if let thread = store.threadToDelete {
                    store.threadToDelete = nil
                    Task { await store.deleteThread(thread) }
                }
            }
            .keyboardShortcut(.defaultAction)
        } message: {
            if let thread = store.threadToDelete {
                Text("This will remove the worktree and branch '\(thread.branch)'.")
            }
        }
    }

    private func threadEmptyState(_ thread: WeaveThread) -> some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 4) {
                emptyStateAction(icon: "terminal", label: "Open Terminal", shortcut: "⌘T") {
                    store.addTab(to: thread)
                }
                emptyStateAction(icon: "arrow.up.forward.square", label: "Open in VSCode", shortcut: nil) {
                    store.openInEditor(thread)
                }
            }
            .frame(maxWidth: 260)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyStateAction(icon: String, label: String, shortcut: String?, action: @escaping () -> Void) -> some View {
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
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            if store.repos.isEmpty {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Add a Git Repository")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Click the folder icon in the toolbar to add one")
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

// MARK: - Window configuration with NSToolbar

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowConfigView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

class WindowConfigView: NSView, NSToolbarDelegate {
    private var didSetup = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, !didSetup else { return }
        didSetup = true

        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)

        let toolbar = NSToolbar(identifier: "WeaveToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        window.toolbarStyle = .unifiedCompact
    }

    // MARK: - NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.weaveSidebarToggle, .weaveAddRepo, .flexibleSpace, .weaveOpenEditor]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.weaveSidebarToggle, .weaveAddRepo, .flexibleSpace, .weaveOpenEditor]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .weaveSidebarToggle:
            let item = NSToolbarItem(itemIdentifier: .weaveSidebarToggle)
            let button = NSButton()
            button.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Toggle Sidebar")
            button.bezelStyle = .toolbar
            button.isBordered = false
            button.target = self
            button.action = #selector(toggleSidebar)
            item.view = button
            item.toolTip = "Toggle Sidebar (⌘\\)"
            return item

        case .weaveAddRepo:
            let item = NSToolbarItem(itemIdentifier: .weaveAddRepo)
            let button = NSButton()
            button.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: "Add Repository")
            button.bezelStyle = .toolbar
            button.isBordered = false
            button.target = self
            button.action = #selector(addRepo)
            item.view = button
            item.toolTip = "Add Repository"
            return item

        case .weaveOpenEditor:
            let item = NSToolbarItem(itemIdentifier: .weaveOpenEditor)
            let currentEditor = EditorLauncher.editor(forID: GhosttyRuntime.shared.store?.config.editor) ?? EditorLauncher.defaultEditor

            let iconSize: CGFloat = 20
            let mainButton = NSButton()
            if let appIcon = currentEditor?.appIcon {
                appIcon.size = NSSize(width: iconSize, height: iconSize)
                mainButton.image = appIcon
            } else {
                mainButton.image = NSImage(systemSymbolName: "chevron.left.forwardslash.chevron.right", accessibilityDescription: "Open in Editor")
            }
            mainButton.imagePosition = .imageOnly
            mainButton.bezelStyle = .toolbar
            mainButton.isBordered = false
            mainButton.target = self
            mainButton.action = #selector(openInEditor)
            mainButton.widthAnchor.constraint(equalToConstant: 36).isActive = true

            let chevronButton = NSButton()
            chevronButton.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Choose Editor")?.withSymbolConfiguration(.init(pointSize: 8, weight: .semibold))
            chevronButton.bezelStyle = .toolbar
            chevronButton.isBordered = false
            chevronButton.target = self
            chevronButton.action = #selector(showEditorMenu(_:))
            chevronButton.widthAnchor.constraint(equalToConstant: 18).isActive = true

            let stack = NSStackView(views: [mainButton, chevronButton])
            stack.spacing = 0
            stack.orientation = .horizontal
            item.view = stack
            item.toolTip = "Open in \(currentEditor?.name ?? "Editor") (⌘O)"
            return item

        default:
            return nil
        }
    }

    @objc private func toggleSidebar() {
        NotificationCenter.default.post(name: .weaveToggleSidebar, object: nil)
    }

    @objc private func addRepo() {
        NotificationCenter.default.post(name: .weaveAddRepo, object: nil)
    }

    @objc private func openInEditor() {
        NotificationCenter.default.post(name: .weaveOpenInEditor, object: nil)
    }

    @objc private func showEditorMenu(_ sender: NSButton) {
        let menu = NSMenu()
        let installed = EditorLauncher.installed
        let currentID = GhosttyRuntime.shared.store?.config.editor

        for editor in installed {
            let menuItem = NSMenuItem(title: editor.name, action: #selector(selectEditor(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = editor.id
            if let appIcon = editor.appIcon {
                appIcon.size = NSSize(width: 16, height: 16)
                menuItem.image = appIcon
            }
            if editor.id == currentID || (currentID == nil && editor.id == EditorLauncher.defaultEditor?.id) {
                menuItem.state = .on
            }
            menu.addItem(menuItem)
        }

        if installed.isEmpty {
            let noEditors = NSMenuItem(title: "No editors found", action: nil, keyEquivalent: "")
            noEditors.isEnabled = false
            menu.addItem(noEditors)
        }

        let point = NSPoint(x: 0, y: sender.bounds.height + 4)
        menu.popUp(positioning: nil, at: point, in: sender)
    }

    @objc private func selectEditor(_ sender: NSMenuItem) {
        guard let editorID = sender.representedObject as? String,
              let editor = EditorLauncher.editor(forID: editorID) else { return }
        GhosttyRuntime.shared.store?.setEditor(editor)
        NotificationCenter.default.post(name: .weaveOpenInEditor, object: nil)
        if let toolbar = window?.toolbar {
            toolbar.delegate = self
            window?.toolbar = nil
            window?.toolbar = toolbar
        }
    }
}

extension NSToolbarItem.Identifier {
    static let weaveSidebarToggle = NSToolbarItem.Identifier("weaveSidebarToggle")
    static let weaveAddRepo = NSToolbarItem.Identifier("weaveAddRepo")
    static let weaveOpenEditor = NSToolbarItem.Identifier("weaveOpenEditor")
}

extension Notification.Name {
    static let weaveToggleSidebar = Notification.Name("weave.toggleSidebar")
    static let weaveAddRepo = Notification.Name("weave.addRepo")
    static let weaveOpenInEditor = Notification.Name("weave.openInEditor")
}
