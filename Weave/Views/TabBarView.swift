import SwiftUI

struct TabBarView: View {
    @Bindable var store: ThreadStore
    var thread: WeaveThread
    @State private var hoveredTabID: UUID?

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(thread.tabs) { tab in
                        tabItem(tab)
                    }
                }
                .padding(.horizontal, 8)
            }

            Spacer(minLength: 0)

            Button {
                store.addTab(to: thread)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New Tab (⌘T)")
            .padding(.trailing, 8)
        }
        .frame(height: 36)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private func tabItem(_ tab: TerminalTab) -> some View {
        let isActive = tab.id == thread.activeTabID
        let isHovered = tab.id == hoveredTabID

        return Button {
            thread.activeTabID = tab.id
            store.focusActiveSurface()
        } label: {
            HStack(spacing: 6) {
                Text(Self.displayTitle(tab.title, worktreePath: thread.worktreePath))
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(isActive ? 0.9 : 0.5))
                    .lineLimit(1)

                if isHovered && thread.tabs.count > 1 {
                    Button {
                        store.closeTab(tab, in: thread)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? Color.primary.opacity(0.1) : (isHovered ? Color.primary.opacity(0.05) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredTabID = hovering ? tab.id : nil
        }
    }

    private static func displayTitle(_ title: String, worktreePath: String) -> String {
        guard !title.isEmpty else { return "Terminal" }

        let home = NSHomeDirectory()
        let prefixes = [worktreePath, worktreePath.hasPrefix(home) ? "~" + worktreePath.dropFirst(home.count) : nil].compactMap { $0 }

        for prefix in prefixes {
            if title.hasPrefix(prefix) {
                let remainder = String(title.dropFirst(prefix.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
                return remainder.isEmpty ? "Terminal" : remainder
            }
        }

        return title
    }
}
