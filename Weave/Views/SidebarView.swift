import AppKit
import SwiftUI

struct SidebarView: View {
    @Bindable var appState: AppState
    @State private var newThreadName = ""
    @State private var repoToRemove: Repo?
    @State private var hoveredThreadID: UUID?
    @State private var hoveredRepoID: UUID?
    @State private var renamingThreadID: UUID?
    @State private var renameText = ""

    private let iconWidth: CGFloat = 16

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if appState.repos.isEmpty {
                        emptyRepoState
                    }

                    ForEach(appState.repos) { repo in
                        repoSection(repo: repo)
                    }
                }
                .padding(.top, 4)
            }

            Divider().opacity(0.3)

            HStack {
                SettingsLink {
                    Image(systemName: "gear")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .alert("Remove Repository?", isPresented: .init(
            get: { repoToRemove != nil },
            set: { if !$0 { repoToRemove = nil } }
        )) {
            Button("Cancel", role: .cancel) { repoToRemove = nil }
            Button("Remove", role: .destructive) {
                if let repo = repoToRemove {
                    appState.removeRepo(repo)
                    repoToRemove = nil
                }
            }
        } message: {
            Text("This will remove the repository from Weave. Worktrees on disk are not affected.")
        }
        .sheet(isPresented: $appState.isCreatingThread) {
            NewThreadSheet(appState: appState)
        }
        .onReceive(NotificationCenter.default.publisher(for: .weaveRenameThread)) { _ in
            if let thread = appState.activeThread {
                renameText = thread.name
                renamingThreadID = thread.id
            }
        }
    }

    private var emptyRepoState: some View {
        VStack(spacing: 8) {
            Text("No repositories")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
            Text("Click + to add one")
                .font(.system(size: 13))
                .foregroundStyle(.quaternary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    @ViewBuilder
    private func repoSection(repo: Repo) -> some View {
        let isHovered = hoveredRepoID == repo.id

        HStack(spacing: 6) {
            Group {
                if isHovered {
                    Image(systemName: repo.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                } else {
                    Image(systemName: "folder")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: iconWidth)

            Button {
                repo.isExpanded.toggle()
            } label: {
                Text(repo.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.8))
            }
            .buttonStyle(.plain)

            Spacer()

            if isHovered {
                IconAccessoryButton(icon: "plus", size: 11, frameSize: 16, tooltip: "New Thread (⌘N)") {
                    appState.isCreatingThread = true
                    appState.creatingThreadRepoID = repo.id
                    repo.isExpanded = true
                }
                .padding(4)
                .contentShape(Rectangle())
                .padding(-4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { repo.isExpanded.toggle() }
        .onHover { hovering in
            hoveredRepoID = hovering ? repo.id : nil
        }
        .contextMenu {
            Button {
                appState.isCreatingThread = true
                appState.creatingThreadRepoID = repo.id
                repo.isExpanded = true

            } label: {
                Text("New Thread")
            }
            Divider()
            Button("Remove Repository", role: .destructive) {
                repoToRemove = repo
            }
        }

        if repo.isExpanded {
            if repo.threads.isEmpty, !(appState.isCreatingThread && appState.creatingThreadRepoID == repo.id) {
                Text("No threads")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 12 + iconWidth + 6)
                    .padding(.vertical, 4)
            }

            ForEach(repo.threads) { thread in
                threadRow(thread)
            }

            if let pending = appState.pendingCreation, pending.repoID == repo.id {
                pendingRow(name: pending.name)
            }
        }
    }

    private func pendingRow(name: String) -> some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.8)
                .frame(width: iconWidth, height: 14)
            Text(name)
                .font(.system(size: 13))
                .foregroundStyle(.primary.opacity(0.4))
                .lineLimit(1)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func threadRow(_ thread: WeaveThread) -> some View {
        let isActive = thread.id == appState.activeThreadID
        let isHovered = thread.id == hoveredThreadID
        let isDeleting = appState.deletingThreadIDs.contains(thread.id)
        let isRenaming = renamingThreadID == thread.id

        return HStack(spacing: 6) {
            agentStatusIcon(thread, isDeleting: isDeleting)
                .frame(width: iconWidth, height: 14)

            if isRenaming {
                AutoFocusTextField(
                    text: $renameText,
                    placeholder: "Thread name...",
                    onSubmit: {
                        let name = renameText.trimmingCharacters(in: .whitespaces)
                        if !name.isEmpty {
                            appState.renameThread(thread, to: name)
                        }
                        renamingThreadID = nil
                    },
                    onCancel: { renamingThreadID = nil }
                )
                .frame(height: 17)
            } else {
                Text(thread.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary.opacity(isDeleting ? 0.4 : (isActive ? 1 : 0.75)))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(height: 17)
                    .help(thread.name)
            }

            Spacer(minLength: 4)

            if !isRenaming {
                if let pr = thread.prInfo {
                    prPill(pr)
                }

                Group {
                    if isDeleting {
                        Color.clear
                    } else if isHovered, !thread.isMainWorktree {
                        IconAccessoryButton(icon: "xmark", size: 9, frameSize: 18, tooltip: "Delete Thread (⌘D)") {
                            appState.threadToDelete = thread
                        }
                    } else {
                        Text(thread.lastActiveAt.relativeShort)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 26, height: 18, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .fill(isActive ? Color.primary
                    .opacity(Theme.activeOpacity) : (isHovered ? Color.primary.opacity(Theme.hoverOpacity) : .clear))
                .padding(.horizontal, 4)
        )
        .onTapGesture {
            if !isDeleting, !isRenaming { appState.switchTo(thread) }
        }
        .onHover { hovering in
            hoveredThreadID = hovering ? thread.id : nil
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            guard !isDeleting else { return }
            renameText = thread.name
            renamingThreadID = thread.id
        })
        .contextMenu {
            Button("Rename") {
                renameText = thread.name
                renamingThreadID = thread.id
            }
            if let pr = thread.prInfo {
                Button("Open PR #\(String(pr.number))") {
                    NSWorkspace.shared.open(pr.url)
                }
            }
            if !thread.isMainWorktree {
                Divider()
                Button("Delete", role: .destructive) {
                    appState.threadToDelete = thread
                }
            }
        }
    }

    @ViewBuilder
    private func agentStatusIcon(_ thread: WeaveThread, isDeleting: Bool) -> some View {
        if isDeleting {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.8)
        } else if thread.agentStatus == .working {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.8)
        } else if thread.agentStatus == .needsInput {
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
        } else if thread.agentStatus == .review {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.green)
        } else {
            Color.clear
        }
    }

    private func prPill(_ pr: PRInfo) -> some View {
        PRStatusBadge(pr: pr)
    }

}

// MARK: - Icon accessory button

struct IconAccessoryButton: View {
    let icon: String
    var size: CGFloat = 13
    var frameSize: CGFloat = 30
    var tooltipLabel: String?
    var tooltipShortcut: String?
    let action: () -> Void
    @State private var isHovered = false

    init(
        icon: String,
        size: CGFloat = 13,
        frameSize: CGFloat = 30,
        tooltip: String? = nil,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.size = size
        self.frameSize = frameSize
        self.action = action
        if let tooltip {
            let parts = tooltip.components(separatedBy: " (")
            self.tooltipLabel = parts.first
            self.tooltipShortcut = parts.count > 1 ? String(parts[1].dropLast()) : nil
        }
    }

    var body: some View {
        let button = Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(width: frameSize, height: frameSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .onHover { isHovered = $0 }

        if let label = tooltipLabel {
            button.tooltip(label, shortcut: tooltipShortcut)
        } else {
            button
        }
    }
}

// MARK: - Auto-focus text field

struct AutoFocusTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: 13)
        field.isBordered = false
        field.backgroundColor = .clear
        field.focusRingType = .none
        field.delegate = context.coordinator
        field.stringValue = text
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: AutoFocusTextField

        init(_ parent: AutoFocusTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            return false
        }
    }
}

// MARK: - PR pill with hover

struct PRStatusBadge: View {
    let pr: PRInfo
    @State private var isHovered = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(pr.url)
        } label: {
            Image(iconName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 12, height: 12)
                .foregroundStyle(isHovered ? prColor : prColor.opacity(Theme.pillForegroundOpacity))
                .frame(width: 22, height: 17)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                        .fill(prColor.opacity(isHovered ? Theme.pillHoverOpacity : Theme.pillOpacity))
                )
        }
        .buttonStyle(.borderless)
        .onHover { isHovered = $0 }
        .tooltip("Open PR #\(String(pr.number))", shortcut: "⌘P")
    }

    private var iconName: String {
        switch pr.state {
        case .merged: "git-merge"
        case .open: "git-pull-request"
        case .draft: "git-pull-request-draft"
        case .closed: "git-pull-request-closed"
        }
    }

    private var prColor: Color {
        Theme.prColor(for: pr.state)
    }
}

struct PRPillView: View {
    let pr: PRInfo
    @State private var isHovered = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(pr.url)
        } label: {
            Text(verbatim: "#\(pr.number)")
                .font(.system(size: Theme.fontSizeSmall, weight: .medium))
                .foregroundStyle(isHovered ? prColor : prColor.opacity(Theme.pillForegroundOpacity))
                .padding(.horizontal, Theme.paddingV)
                .frame(height: 17)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                        .fill(prColor.opacity(isHovered ? Theme.pillHoverOpacity : Theme.pillOpacity))
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .tooltip("Open PR #\(String(pr.number))", shortcut: "⌘P")
    }

    private var prColor: Color {
        Theme.prColor(for: pr.state)
    }
}

// MARK: - New thread sheet

struct NewThreadSheet: View {
    @Bindable var appState: AppState
    @State private var name = ""

    private var repo: Repo? {
        guard let id = appState.creatingThreadRepoID else { return nil }
        return appState.repos.first { $0.id == id }
    }

    private var generatedBranch: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }
        return WeaveHelpers.sanitizeBranch(trimmed, prefix: AppSettings.shared.branchPrefix)
    }

    private var worktreePath: String {
        guard !generatedBranch.isEmpty, let repo else { return "" }
        let repoName = GitWorktree.repoName(path: repo.path)
        return "\(AppSettings.shared.resolvedWorktreeBase)/\(repoName)/\(generatedBranch)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Thread")
                .font(.system(size: 13, weight: .semibold))

            AutoFocusTextField(
                text: $name,
                placeholder: "Thread name...",
                onSubmit: create,
                onCancel: dismiss
            )
            .frame(height: 22)

            if !generatedBranch.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("Branch:")
                            .foregroundStyle(.tertiary)
                        Text(generatedBranch)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        Text("Path:")
                            .foregroundStyle(.tertiary)
                        Text(worktreePath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .font(.system(size: 11))
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let repo else { return }
        appState.isCreatingThread = false
        appState.creatingThreadRepoID = nil
        Task { await appState.createThread(name: trimmed, in: repo) }
    }

    private func dismiss() {
        appState.isCreatingThread = false
        appState.creatingThreadRepoID = nil
    }
}

// MARK: - Relative date formatting

extension Date {
    var relativeShort: String {
        let now = Date()
        let interval = now.timeIntervalSince(self)

        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        if interval < 604_800 { return "\(Int(interval / 86400))d" }
        if interval < 2_592_000 { return "\(Int(interval / 604_800))w" }
        return "\(Int(interval / 2_592_000))mo"
    }
}
