import SwiftUI

struct TrafficLightConfigurator: NSViewRepresentable {
    let titleBarHeight: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = TrafficLightConfigView()
        view.titleBarHeight = titleBarHeight
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

class TrafficLightConfigView: NSView {
    var titleBarHeight: CGFloat = 38
    private var didSetup = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, !didSetup else { return }
        didSetup = true
        repositionTrafficLights(in: window)
    }

    override func layout() {
        super.layout()
        if let window { repositionTrafficLights(in: window) }
    }

    private var defaultPositions: [NSWindow.ButtonType: CGPoint]?

    private func repositionTrafficLights(in window: NSWindow) {
        guard let closeButton = window.standardWindowButton(.closeButton) else { return }

        if defaultPositions == nil {
            var positions: [NSWindow.ButtonType: CGPoint] = [:]
            for t: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
                if let b = window.standardWindowButton(t) {
                    positions[t] = b.frame.origin
                }
            }
            defaultPositions = positions
        }

        let containerHeight = closeButton.superview?.frame.height ?? 32
        let buttonHeight = closeButton.frame.height
        let visualCenter = titleBarHeight / 2
        let offsetFromTop = visualCenter - buttonHeight / 2
        let targetY = containerHeight - offsetFromTop - buttonHeight
        let xShift: CGFloat = 6

        for buttonType: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window.standardWindowButton(buttonType),
                  let defaultOrigin = defaultPositions?[buttonType] else { continue }
            var frame = button.frame
            frame.origin.x = defaultOrigin.x + xShift
            frame.origin.y = targetY
            button.frame = frame
        }
    }
}

struct WindowDragView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DraggingView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

class DraggingView: NSView {
    override var mouseDownCanMoveWindow: Bool {
        true
    }
}

struct SidebarDragHandle: View {
    @Binding var sidebarWidth: CGFloat
    @State private var isHovered = false

    var body: some View {
        Rectangle()
            .fill(
                isHovered
                    ? LinearGradient(
                        colors: [.clear, .white.opacity(0.2), .white.opacity(0.2), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    : LinearGradient(
                        colors: [.clear, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
            )
            .frame(width: 2)
            .padding(.horizontal, 4)
            .frame(width: 10)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let newWidth = sidebarWidth + value.translation.width
                        sidebarWidth = min(max(newWidth, 180), 500)
                    }
            )
    }
}
