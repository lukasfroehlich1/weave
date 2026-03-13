import SwiftUI

struct ThreadHeaderView: View {
    @Bindable var appState: AppState
    let thread: WeaveThread
    @State private var worktreeHovered = false
    @State private var menuHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(thread.name)
                .font(.system(size: Theme.fontSize, weight: .semibold))
                .lineLimit(1)

            Text(URL(fileURLWithPath: thread.worktreePath).lastPathComponent)
                .font(.system(size: Theme.fontSizeSmall))
                .foregroundStyle(worktreeHovered ? .primary : .secondary)
                .onTapGesture {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: thread.worktreePath)
                }
                .onHover { worktreeHovered = $0 }
                .help(thread.worktreePath)

            if let pr = thread.prInfo {
                PRPillView(pr: pr)
            }

            Menu {
                Button {
                    NotificationCenter.default.post(name: .weaveRenameThread, object: nil)
                } label: {
                    Label("Rename Thread", systemImage: "pencil")
                }
                Button {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: thread.worktreePath)
                } label: {
                    Label("Open in Finder", systemImage: "folder")
                }
                if let pr = thread.prInfo {
                    Button {
                        NSWorkspace.shared.open(pr.url)
                    } label: {
                        Label("Open PR #\(String(pr.number))", systemImage: "arrow.up.forward.square")
                    }
                }
                if !thread.isMainWorktree {
                    Divider()
                    Button(role: .destructive) {
                        appState.threadToDelete = thread
                    } label: {
                        Label("Delete Thread", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: Theme.iconSize, weight: .medium))
                    .foregroundStyle(menuHovered ? .primary : .tertiary)
            }
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
            .onHover { menuHovered = $0 }
        }
        .padding(.leading, 20)
    }
}

struct EditorButton: View {
    @Bindable var appState: AppState
    @State private var editorHovered = false
    @State private var chevronHovered = false

    private var editor: Editor? {
        EditorLauncher.editor(forID: AppSettings.shared.defaultEditor) ?? EditorLauncher.defaultEditor
    }

    private var isSelected: (Editor) -> Bool {
        { ed in
            ed.id == AppSettings.shared.defaultEditor ||
                (AppSettings.shared.defaultEditor == nil && ed.id == EditorLauncher.defaultEditor?.id)
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            Button {
                if let thread = appState.activeThread {
                    appState.openInEditor(thread)
                }
            } label: {
                Group {
                    if let appIcon = editor?.appIcon {
                        Image(nsImage: {
                            appIcon.size = NSSize(width: 18, height: 18)
                            return appIcon
                        }())
                    } else {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 14))
                    }
                }
                .foregroundStyle(editorHovered ? .primary : .secondary)
                .opacity(editorHovered ? 1.0 : 0.6)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .onHover { editorHovered = $0 }
            .tooltip("Open Worktree in \(editor?.name ?? "Editor")", shortcut: "⌘O")

            Menu {
                ForEach(EditorLauncher.installed) { ed in
                    Button {
                        appState.setEditor(ed)
                    } label: {
                        HStack {
                            if let appIcon = ed.appIcon {
                                Image(nsImage: {
                                    appIcon.size = NSSize(width: 16, height: 16)
                                    return appIcon
                                }())
                            }
                            Text(ed.name)
                            Spacer()
                            if isSelected(ed) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(chevronHovered ? .primary : .secondary)
                    .opacity(chevronHovered ? 1.0 : 0.6)
            }
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .frame(width: 22, height: 30)
            .contentShape(Rectangle())
            .onHover { chevronHovered = $0 }
        }
    }
}
