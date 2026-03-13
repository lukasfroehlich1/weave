import Cocoa
import SwiftUI

class TooltipWindow: NSWindow {
    static var current: TooltipWindow?

    init(label: String, shortcut: String?) {
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        ignoresMouseEvents = true
        hasShadow = true

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)

        let text = NSTextField(labelWithString: label)
        text.font = .systemFont(ofSize: 12, weight: .medium)
        text.textColor = .white
        stack.addArrangedSubview(text)

        if let shortcut, !shortcut.isEmpty {
            let badge = NSTextField(labelWithString: shortcut)
            badge.font = .systemFont(ofSize: 11, weight: .medium)
            badge.textColor = NSColor.white.withAlphaComponent(0.5)
            badge.wantsLayer = true
            badge.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
            badge.layer?.cornerRadius = CGFloat(Theme.cornerRadiusSmall)
            badge.alignment = .center
            let badgeContainer = NSView()
            badge.translatesAutoresizingMaskIntoConstraints = false
            badgeContainer.addSubview(badge)
            NSLayoutConstraint.activate([
                badge.leadingAnchor.constraint(equalTo: badgeContainer.leadingAnchor),
                badge.trailingAnchor.constraint(equalTo: badgeContainer.trailingAnchor),
                badge.centerYAnchor.constraint(equalTo: badgeContainer.centerYAnchor),
                badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 22),
                badgeContainer.heightAnchor.constraint(equalTo: badge.heightAnchor),
            ])
            stack.addArrangedSubview(badgeContainer)
        }

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = Theme.tooltipBackground.cgColor
        container.layer?.cornerRadius = Theme.tooltipCornerRadius
        container.layer?.borderWidth = 0.5
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        contentView = container
        setContentSize(container.fittingSize)
    }

    static func show(label: String, shortcut: String?, below view: NSView) {
        dismiss()
        guard let window = view.window else { return }
        let viewFrame = view.convert(view.bounds, to: nil)
        let screenPoint = window.convertPoint(toScreen: NSPoint(x: viewFrame.midX, y: viewFrame.minY - 8))
        let tooltip = TooltipWindow(label: label, shortcut: shortcut)
        let size = tooltip.frame.size
        var x = screenPoint.x - size.width / 2
        if let screen = window.screen ?? NSScreen.main {
            let maxX = screen.visibleFrame.maxX - 8
            let minX = screen.visibleFrame.minX + 8
            if x + size.width > maxX { x = maxX - size.width }
            if x < minX { x = minX }
        }
        tooltip.setFrameOrigin(NSPoint(x: x, y: screenPoint.y - size.height))
        tooltip.alphaValue = 0
        tooltip.orderFront(nil)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; tooltip.animator().alphaValue = 1 }
        current = tooltip
    }

    static func dismiss() {
        guard let tooltip = current else { return }
        current = nil
        NSAnimationContext
            .runAnimationGroup({ $0.duration = 0.1; tooltip.animator().alphaValue = 0 }) { tooltip.orderOut(nil) }
    }
}

struct TooltipAnchor: NSViewRepresentable {
    @Binding var anchorView: NSView?
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { anchorView = view }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct TooltipModifier: ViewModifier {
    let label: String
    var shortcut: String?
    @State private var anchorView: NSView?
    @State private var hoverTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .background(TooltipAnchor(anchorView: $anchorView))
            .onHover { hovering in
                hoverTask?.cancel()
                if hovering {
                    hoverTask = Task {
                        try? await Task.sleep(for: .seconds(0.8))
                        guard !Task.isCancelled else { return }
                        if let view = anchorView {
                            TooltipWindow.show(label: label, shortcut: shortcut, below: view)
                        }
                    }
                } else {
                    TooltipWindow.dismiss()
                }
            }
    }
}

extension View {
    func tooltip(_ label: String, shortcut: String? = nil) -> some View {
        modifier(TooltipModifier(label: label, shortcut: shortcut))
    }
}
