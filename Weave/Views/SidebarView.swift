import SwiftUI
import AppKit

struct SidebarView: View {
    @Bindable var store: ThreadStore
    @State private var newThreadName = ""
    @State private var repoToRemove: Repo?
    @State private var hoveredThreadID: UUID?
    @State private var hoveredRepoID: UUID?

    private let iconWidth: CGFloat = 16

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if store.repos.isEmpty {
                    emptyRepoState
                }

                ForEach(store.repos) { repo in
                    repoSection(repo: repo)
                }
            }
            .padding(.top, 4)
        }
        .alert("Remove Repository?", isPresented: .init(
            get: { repoToRemove != nil },
            set: { if !$0 { repoToRemove = nil } }
        )) {
            Button("Cancel", role: .cancel) { repoToRemove = nil }
            Button("Remove", role: .destructive) {
                if let repo = repoToRemove {
                    store.removeRepo(repo)
                    repoToRemove = nil
                }
            }
        } message: {
            Text("This will remove the repository from Weave. Worktrees on disk are not affected.")
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

            Button {
                store.isCreatingThread = true
                store.creatingThreadRepoID = repo.id
                repo.isExpanded = true

            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("New Thread")
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
                store.isCreatingThread = true
                store.creatingThreadRepoID = repo.id
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
            if repo.threads.isEmpty && !(store.isCreatingThread && store.creatingThreadRepoID == repo.id) {
                Text("No threads")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 12 + iconWidth + 6)
                    .padding(.vertical, 4)
            }

            ForEach(repo.threads) { thread in
                threadRow(thread)
            }

            if store.isCreatingThread && store.creatingThreadRepoID == repo.id {
                newThreadField(repo: repo)
            }

            if let pending = store.pendingCreation, pending.repoID == repo.id {
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
        let isActive = thread.id == store.activeThreadID
        let isHovered = thread.id == hoveredThreadID
        let isDeleting = store.deletingThreadIDs.contains(thread.id)

        return Button {
            if !isDeleting { store.switchTo(thread) }
        } label: {
            HStack(spacing: 6) {
                agentStatusIcon(thread, isDeleting: isDeleting)
                    .frame(width: iconWidth, height: 14)

                Text(thread.name)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary.opacity(isDeleting ? 0.4 : (isActive ? 1 : 0.75)))
                    .lineLimit(1)

                Spacer(minLength: 4)

                if let pr = thread.prInfo {
                    prPill(pr)
                }

                Group {
                    if isDeleting {
                        Color.clear
                    } else if isHovered {
                        Button {
                            store.threadToDelete = thread
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .frame(width: 26)
                                .frame(maxHeight: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Delete thread")
                    } else {
                        Text(thread.lastActiveAt.relativeShort)
                            .font(.system(size: 11))
                            .foregroundStyle(.quaternary)
                    }
                }
                .frame(width: 26, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? Color.primary.opacity(0.08) : (isHovered ? Color.primary.opacity(0.04) : .clear))
                    .padding(.horizontal, 4)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredThreadID = hovering ? thread.id : nil
        }
        .contextMenu {
            if let pr = thread.prInfo {
                Button("Open PR #\(pr.number)") {
                    NSWorkspace.shared.open(pr.url)
                }
                Divider()
            }
            Button("Delete", role: .destructive) {
                store.threadToDelete = thread
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
            Circle()
                .fill(.blue)
                .frame(width: 7, height: 7)
        } else if thread.agentStatus == .review {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.green)
        } else {
            Color.clear
        }
    }

    private func prPill(_ pr: PRInfo) -> some View {
        Button {
            NSWorkspace.shared.open(pr.url)
        } label: {
            Text(verbatim: "#\(pr.number)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(prColor(pr.state).opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }

    private func prColor(_ state: PRState) -> Color {
        switch state {
        case .draft: .gray
        case .open: .green
        case .merged: .purple
        case .closed: .red
        }
    }

    private func newThreadField(repo: Repo) -> some View {
        HStack(spacing: 6) {
            Color.clear.frame(width: iconWidth)
            AutoFocusTextField(
                text: $newThreadName,
                placeholder: "Thread name...",
                onSubmit: {
                    guard !newThreadName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    let name = newThreadName
                    newThreadName = ""
                    store.isCreatingThread = false
                    store.creatingThreadRepoID = nil
                    Task { await store.createThread(name: name, in: repo) }
                },
                onCancel: {
                    newThreadName = ""
                    store.isCreatingThread = false
                    store.creatingThreadRepoID = nil
                }
            )
            .frame(height: 18)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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

// MARK: - Relative date formatting

extension Date {
    var relativeShort: String {
        let now = Date()
        let interval = now.timeIntervalSince(self)

        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        if interval < 604800 { return "\(Int(interval / 86400))d" }
        if interval < 2592000 { return "\(Int(interval / 604800))w" }
        return "\(Int(interval / 2592000))mo"
    }
}
