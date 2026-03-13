import SwiftUI

struct TerminalView: NSViewRepresentable {
    var surfaceView: GhosttySurfaceView?

    func makeNSView(context: Context) -> TerminalContainerView {
        let container = TerminalContainerView()
        if let surfaceView {
            container.showSurface(surfaceView)
        }
        return container
    }

    func updateNSView(_ container: TerminalContainerView, context: Context) {
        container.showSurface(surfaceView)
    }
}

class TerminalContainerView: NSView {
    private weak var currentSurface: GhosttySurfaceView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func showSurface(_ surface: GhosttySurfaceView?) {
        guard surface !== currentSurface else { return }

        currentSurface?.removeFromSuperview()
        currentSurface = surface

        guard let surface else { return }

        surface.frame = bounds
        surface.autoresizingMask = [.width, .height]
        addSubview(surface)

        DispatchQueue.main.async {
            self.window?.makeFirstResponder(surface)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let surface = currentSurface {
            DispatchQueue.main.async {
                self.window?.makeFirstResponder(surface)
            }
        }
    }
}
