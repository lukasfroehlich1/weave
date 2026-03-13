import SwiftUI

struct SearchBar: View {
    @Bindable var appState: AppState
    var surface: GhosttySurfaceView?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            SearchTextField(
                text: $appState.search.query,
                onSubmit: { navigate("navigate_search:next") },
                onShiftSubmit: { navigate("navigate_search:previous") },
                onCancel: { endSearch() }
            )
            .frame(maxWidth: .infinity, maxHeight: 18)
            .onChange(of: appState.search.query) { search() }

            Text(searchCountText)
                .font(.system(size: Theme.fontSizeSmall))
                .foregroundStyle(.tertiary)
                .frame(width: 60)

            SearchIconButton(icon: "chevron.up") { navigate("navigate_search:previous") }
            SearchIconButton(icon: "chevron.down") { navigate("navigate_search:next") }
            SearchIconButton(icon: "xmark.circle.fill", size: 12) { endSearch() }
                .keyboardShortcut(.escape, modifiers: [])
        }
        .frame(width: 360)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { focusSearchField() }
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .fill(Color(nsColor: Theme.tooltipBackground))
                .shadow(color: .black.opacity(0.3), radius: Theme.cornerRadius)
        )
        .onChange(of: appState.search.focusTrigger) {
            focusSearchField()
        }
    }

    private var searchCountText: String {
        if appState.search.query.isEmpty { return "" }
        if appState.search.total == 0 { return "No results" }
        if appState.search.selected < 0 { return "-/\(appState.search.total)" }
        return "\(appState.search.selected + 1)/\(appState.search.total)"
    }

    private func focusSearchField() {
        guard let window = surface?.window else { return }
        if let field = findSearchField(in: window.contentView) {
            window.makeFirstResponder(field)
        }
    }

    private func findSearchField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField, field.placeholderString == "Search..." {
            return field
        }
        for subview in view.subviews {
            if let found = findSearchField(in: subview) { return found }
        }
        return nil
    }

    private func search() {
        guard let s = surface?.surface else { return }
        let action = "search:\(appState.search.query)"
        action.withCString { ptr in
            ghostty_surface_binding_action(s, ptr, UInt(action.utf8.count))
        }
    }

    private func navigate(_ action: String) {
        guard let s = surface?.surface else { return }
        action.withCString { ptr in
            ghostty_surface_binding_action(s, ptr, UInt(action.utf8.count))
        }
    }

    private func endSearch() {
        if let s = surface?.surface {
            let action = "end_search"
            action.withCString { ptr in
                ghostty_surface_binding_action(s, ptr, UInt(action.utf8.count))
            }
        }
        appState.search.isActive = false
        appState.search.query = ""
        appState.focusActiveSurface()
    }
}

struct SearchIconButton: View {
    let icon: String
    var size: CGFloat = 10
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

struct SearchTextField: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void
    var onShiftSubmit: () -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = "Search..."
        field.font = .systemFont(ofSize: 13)
        field.isBordered = false
        field.backgroundColor = .clear
        field.focusRingType = .none
        field.delegate = context.coordinator
        field.stringValue = text

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard let window = field.window else { return }
            window.makeFirstResponder(field)
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
        let parent: SearchTextField
        init(_ parent: SearchTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                    parent.onShiftSubmit()
                } else {
                    parent.onSubmit()
                }
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
