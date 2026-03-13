import SwiftUI

struct TabBarView: View {
    @Bindable var appState: AppState
    var thread: WeaveThread
    @State private var hoveredTabID: UUID?

    var body: some View {
        HStack(spacing: 1) {
            ForEach(thread.tabs) { tab in
                tabItem(tab)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 1)
        .frame(height: 28)
        .background(Theme.tabBarBackground)
    }

    private func tabItem(_ tab: Tab) -> some View {
        let isActive = tab.id == thread.activeTabID
        let isHovered = tab.id == hoveredTabID

        return HStack(spacing: 0) {
            Text(tab.title)
                .font(.system(size: Theme.fontSizeSmall))
                .foregroundStyle(.primary.opacity(isActive ? 0.9 : 0.4))
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            Group {
                if isHovered, thread.tabs.count > 1 {
                    IconAccessoryButton(icon: "xmark.circle.fill", size: Theme.iconSize, tooltip: "Close Tab (⌘W)") {
                        appState.closeTab(tab, in: thread)
                    }
                } else {
                    Color.clear
                }
            }
            .frame(width: 26)
        }
        .padding(.horizontal, Theme.cornerRadiusSmall)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                .fill(isActive ? Color.white
                    .opacity(Theme.activeOpacity) : (isHovered ? Color.white.opacity(Theme.hoverOpacity) : .clear))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            thread.activeTabID = tab.id
            appState.focusActiveSurface()
        }
        .onHover { hovering in
            hoveredTabID = hovering ? tab.id : nil
        }
    }
}
