import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @Bindable var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsTab(appState: appState)
                .tabItem { Label("General", systemImage: "gear") }

            ShortcutsSettingsTab()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .frame(width: 450)
    }
}

struct GeneralSettingsTab: View {
    @Bindable var appState: AppState
    @Bindable var settings = AppSettings.shared
    @State private var worktreeBaseText: String = ""
    @State private var branchPrefixText: String = ""
    @State private var baseBranchText: String = ""

    var body: some View {
        Form {
            Section("Worktrees") {
                TextField("Worktree Base Path", text: $worktreeBaseText, prompt: Text("~/.weave/worktrees"))
                    .onSubmit { save() }

                TextField("Branch Prefix", text: $branchPrefixText, prompt: Text("e.g. lf-"))
                    .onSubmit { save() }

                TextField("Default Base Branch", text: $baseBranchText, prompt: Text("Auto-detect"))
                    .onSubmit { save() }
            }

            Section("Thread Deletion") {
                Toggle("Delete branch when removing thread", isOn: $settings.deleteBranchOnRemove)
                    .onChange(of: AppSettings.shared.deleteBranchOnRemove) { appState.saveState() }

                Toggle(
                    "Force remove worktree (ignore uncommitted changes)",
                    isOn: $settings.forceRemoveWorktree
                )
                .onChange(of: AppSettings.shared.forceRemoveWorktree) { appState.saveState() }
            }

            Section("Editor") {
                let installed = EditorLauncher.installed
                Picker("Preferred Editor", selection: Binding(
                    get: { AppSettings.shared.defaultEditor ?? EditorLauncher.defaultEditor?.id ?? "" },
                    set: { id in
                        if let editor = EditorLauncher.editor(forID: id) {
                            appState.setEditor(editor)
                        }
                    }
                )) {
                    ForEach(installed) { editor in
                        Text(editor.name).tag(editor.id)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            worktreeBaseText = AppSettings.shared.worktreeBase ?? ""
            branchPrefixText = AppSettings.shared.branchPrefix
            baseBranchText = AppSettings.shared.baseBranch ?? ""
        }
    }

    private func save() {
        AppSettings.shared.worktreeBase = worktreeBaseText.isEmpty ? nil : worktreeBaseText
        AppSettings.shared.branchPrefix = branchPrefixText
        AppSettings.shared.baseBranch = baseBranchText.isEmpty ? nil : baseBranchText
        appState.saveState()
    }
}

struct ShortcutsSettingsTab: View {
    var body: some View {
        Form {
            Section("Threads") {
                KeyboardShortcuts.Recorder("New Thread", name: .newThread)
                KeyboardShortcuts.Recorder("Delete Thread", name: .deleteThread)
                KeyboardShortcuts.Recorder("Next Thread", name: .nextThread)
                KeyboardShortcuts.Recorder("Previous Thread", name: .previousThread)
                KeyboardShortcuts.Recorder("Next Active Thread", name: .nextActiveThread)
                KeyboardShortcuts.Recorder("Previous Active Thread", name: .previousActiveThread)
            }

            Section("Tabs") {
                KeyboardShortcuts.Recorder("New Tab", name: .newTab)
                KeyboardShortcuts.Recorder("Close Tab", name: .closeTab)
            }

            Section("App") {
                KeyboardShortcuts.Recorder("Toggle Sidebar", name: .toggleSidebar)
                KeyboardShortcuts.Recorder("Add Repository", name: .addRepo)
                KeyboardShortcuts.Recorder("Open in Editor", name: .openInEditor)
                KeyboardShortcuts.Recorder("Open Pull Request", name: .openPR)
            }

            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    KeyboardShortcuts.reset(
                        .newThread, .newTab, .closeTab, .addRepo,
                        .toggleSidebar, .openInEditor, .openPR, .deleteThread,
                        .nextThread, .previousThread, .nextActiveThread, .previousActiveThread
                    )
                }
            }
        }
        .formStyle(.grouped)
    }
}
