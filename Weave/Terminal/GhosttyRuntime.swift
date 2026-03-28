import Cocoa

final class GhosttyRuntime {
    static let shared = GhosttyRuntime()

    private(set) var app: ghostty_app_t?
    private(set) var config: ghostty_config_t?
    weak var store: ThreadStore?

    private init() {}

    private var initialized = false

    func initialize() {
        guard !initialized else { return }
        initialized = true

        if getenv("NO_COLOR") != nil {
            unsetenv("NO_COLOR")
        }

        let result = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)
        guard result == GHOSTTY_SUCCESS else { return }

        guard let cfg = ghostty_config_new() else { return }
        ghostty_config_load_default_files(cfg)
        ghostty_config_load_recursive_files(cfg)
        Self.loadWeaveDefaults(cfg)
        ghostty_config_finalize(cfg)

        var runtimeConfig = ghostty_runtime_config_s()
        runtimeConfig.userdata = Unmanaged.passUnretained(self).toOpaque()
        runtimeConfig.supports_selection_clipboard = false

        runtimeConfig.wakeup_cb = { userdata in
            DispatchQueue.main.async {
                guard let ud = userdata else { return }
                let runtime = Unmanaged<GhosttyRuntime>.fromOpaque(ud).takeUnretainedValue()
                runtime.tick()
            }
        }

        runtimeConfig.action_cb = { app, target, action in
            guard let ud = ghostty_app_userdata(app) else { return false }
            let runtime = Unmanaged<GhosttyRuntime>.fromOpaque(ud).takeUnretainedValue()
            return runtime.handleAction(target: target, action: action)
        }

        runtimeConfig.read_clipboard_cb = { userdata, location, state in
            guard let userdata else { return false }
            let surface = GhosttySurfaceView.surfaceFromUserdata(userdata)
            let str = NSPasteboard.general.string(forType: .string) ?? ""
            str.withCString { ptr in
                ghostty_surface_complete_clipboard_request(surface, ptr, state, false)
            }
            return true
        }

        runtimeConfig.confirm_read_clipboard_cb = { userdata, str, state, request in
            guard let userdata else { return }
            let surface = GhosttySurfaceView.surfaceFromUserdata(userdata)
            DispatchQueue.main.async {
                let content = NSPasteboard.general.string(forType: .string) ?? ""
                content.withCString { ptr in
                    ghostty_surface_complete_clipboard_request(surface, ptr, state, false)
                }
            }
        }

        runtimeConfig.write_clipboard_cb = { _, location, content, len, _ in
            guard let content, len > 0 else { return }
            for i in 0..<len {
                let item = content[i]
                guard let mime = item.mime, let data = item.data else { continue }
                let mimeStr = String(cString: mime)
                if mimeStr.hasPrefix("text/plain") {
                    let text = String(cString: data)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    return
                }
            }
        }

        runtimeConfig.close_surface_cb = { userdata, processAlive in
            guard let userdata else { return }
            let view = Unmanaged<GhosttySurfaceView>.fromOpaque(userdata).takeUnretainedValue()
            DispatchQueue.main.async {
                view.surfaceClosed()
            }
        }

        guard let created = ghostty_app_new(&runtimeConfig, cfg) else {
            ghostty_config_free(cfg)
            return
        }

        self.app = created
        self.config = cfg
    }

    func tick() {
        guard let app else { return }
        ghostty_app_tick(app)
    }

    private func handleAction(target: ghostty_target_s, action: ghostty_action_s) -> Bool {
        switch action.tag {
        case GHOSTTY_ACTION_SET_TITLE:
            guard target.tag == GHOSTTY_TARGET_SURFACE,
                  let surface = target.target.surface,
                  let titlePtr = action.action.set_title.title else { return false }
            let title = String(cString: titlePtr)
            if let view = GhosttySurfaceView.viewFromSurface(surface) {
                DispatchQueue.main.async {
                    view.title = title
                    view.onTitleChange?(title)
                }
            }
            return true

        case GHOSTTY_ACTION_MOUSE_SHAPE:
            guard target.tag == GHOSTTY_TARGET_SURFACE else { return false }
            let shape = action.action.mouse_shape
            DispatchQueue.main.async {
                Self.setCursor(shape)
            }
            return true

        case GHOSTTY_ACTION_OPEN_URL:
            guard let urlPtr = action.action.open_url.url else { return false }
            let len = action.action.open_url.len
            let urlStr = String(bytes: UnsafeBufferPointer(start: urlPtr, count: Int(len)).map { UInt8(bitPattern: $0) }, encoding: .utf8) ?? ""
            if let url = URL(string: urlStr) {
                DispatchQueue.main.async {
                    NSWorkspace.shared.open(url)
                }
            }
            return true

        case GHOSTTY_ACTION_SHOW_CHILD_EXITED:
            guard target.tag == GHOSTTY_TARGET_SURFACE,
                  let surface = target.target.surface else { return false }
            if let view = GhosttySurfaceView.viewFromSurface(surface) {
                DispatchQueue.main.async {
                    view.surfaceClosed()
                }
            }
            return true

        case GHOSTTY_ACTION_RING_BELL:
            return true

        case GHOSTTY_ACTION_NEW_TAB:
            DispatchQueue.main.async { [weak self] in
                guard let store = self?.store, let thread = store.activeThread else { return }
                store.addTab(to: thread)
            }
            return true

        case GHOSTTY_ACTION_CLOSE_TAB:
            DispatchQueue.main.async { [weak self] in
                guard let store = self?.store,
                      let thread = store.activeThread,
                      let tab = thread.activeTab else { return }
                store.closeTab(tab, in: thread)
            }
            return true

        case GHOSTTY_ACTION_GOTO_TAB:
            let gotoTab = action.action.goto_tab
            DispatchQueue.main.async { [weak self] in
                guard let store = self?.store, let thread = store.activeThread else { return }
                switch gotoTab {
                case GHOSTTY_GOTO_TAB_PREVIOUS:
                    store.selectPreviousTab()
                case GHOSTTY_GOTO_TAB_NEXT:
                    store.selectNextTab()
                case GHOSTTY_GOTO_TAB_LAST:
                    if let last = thread.tabs.last {
                        thread.activeTabID = last.id
                        store.focusActiveSurface()
                    }
                default:
                    let idx = Int(gotoTab.rawValue) - 1
                    if idx >= 0 && idx < thread.tabs.count {
                        thread.activeTabID = thread.tabs[idx].id
                        store.focusActiveSurface()
                    }
                }
            }
            return true

        default:
            return false
        }
    }

    private static func loadWeaveDefaults(_ cfg: ghostty_config_t) {
        let defaults = "window-padding-balance = true\n"
        let tmpPath = NSTemporaryDirectory() + "weave-ghostty-defaults.conf"
        FileManager.default.createFile(atPath: tmpPath, contents: defaults.data(using: .utf8))
        ghostty_config_load_file(cfg, tmpPath)
        try? FileManager.default.removeItem(atPath: tmpPath)
    }

    private static func setCursor(_ shape: ghostty_action_mouse_shape_e) {
        switch shape {
        case GHOSTTY_MOUSE_SHAPE_DEFAULT:
            NSCursor.arrow.set()
        case GHOSTTY_MOUSE_SHAPE_TEXT:
            NSCursor.iBeam.set()
        case GHOSTTY_MOUSE_SHAPE_POINTER:
            NSCursor.pointingHand.set()
        case GHOSTTY_MOUSE_SHAPE_CROSSHAIR:
            NSCursor.crosshair.set()
        default:
            NSCursor.arrow.set()
        }
    }
}
