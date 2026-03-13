import Cocoa

class GhosttySurfaceView: NSView, NSTextInputClient {
    private(set) var surface: ghostty_surface_t?
    var title: String = ""
    var onClose: (() -> Void)?
    var onTitleChange: ((String) -> Void)?
    var onInput: (() -> Void)?

    private var markedText = NSMutableAttributedString()
    private var keyTextAccumulator: [String]?

    private static var activeSurfaces: [UnsafeMutableRawPointer: GhosttySurfaceView] = [:]

    init(workingDirectory: String? = nil, command: String? = nil, envVars: [String: String] = [:]) {
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        wantsLayer = true

        guard let app = GhosttyRuntime.shared.app else { return }

        var cfg = ghostty_surface_config_new()
        cfg.platform_tag = GHOSTTY_PLATFORM_MACOS
        cfg.platform.macos.nsview = Unmanaged.passUnretained(self).toOpaque()
        cfg.userdata = Unmanaged.passUnretained(self).toOpaque()
        cfg.context = GHOSTTY_SURFACE_CONTEXT_WINDOW

        let wdCopy: UnsafeMutablePointer<CChar>? = workingDirectory.flatMap { strdup($0) }
        defer { if let wdCopy { free(wdCopy) } }
        cfg.working_directory = wdCopy.map { UnsafePointer($0) } ?? nil

        let cmdCopy: UnsafeMutablePointer<CChar>? = command.flatMap { strdup($0) }
        defer { if let cmdCopy { free(cmdCopy) } }
        cfg.command = cmdCopy.map { UnsafePointer($0) } ?? nil

        var envPtrs: [(UnsafeMutablePointer<CChar>, UnsafeMutablePointer<CChar>)] = []
        let envArray: UnsafeMutablePointer<ghostty_env_var_s>?
        if envVars.isEmpty {
            envArray = nil
        } else {
            envArray = .allocate(capacity: envVars.count)
            for (i, (key, value)) in envVars.enumerated() {
                let k = strdup(key)!
                let v = strdup(value)!
                envPtrs.append((k, v))
                envArray![i] = ghostty_env_var_s(key: UnsafePointer(k), value: UnsafePointer(v))
            }
            cfg.env_vars = envArray
            cfg.env_var_count = envVars.count
        }
        defer {
            envPtrs.forEach { free($0.0); free($0.1) }
            envArray?.deallocate()
        }

        if let window, let screen = window.screen ?? NSScreen.main {
            cfg.scale_factor = Double(screen.backingScaleFactor)
        } else if let screen = NSScreen.main {
            cfg.scale_factor = Double(screen.backingScaleFactor)
        } else {
            cfg.scale_factor = 2.0
        }

        guard let s = ghostty_surface_new(app, &cfg) else { return }
        self.surface = s
        GhosttySurfaceView.activeSurfaces[Unmanaged.passUnretained(self).toOpaque()] = self

        updateTrackingAreas()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    deinit {
        GhosttySurfaceView.activeSurfaces.removeValue(forKey: Unmanaged.passUnretained(self).toOpaque())
        if let surface {
            ghostty_surface_free(surface)
        }
    }

    static func surfaceFromUserdata(_ userdata: UnsafeMutableRawPointer) -> ghostty_surface_t? {
        let view = Unmanaged<GhosttySurfaceView>.fromOpaque(userdata).takeUnretainedValue()
        return view.surface
    }

    static func viewFromSurface(_ surface: ghostty_surface_t) -> GhosttySurfaceView? {
        guard let ud = ghostty_surface_userdata(surface) else { return nil }
        return activeSurfaces[ud]
    }

    func surfaceClosed() {
        onClose?()
    }

    func readScrollback(lineLimit: Int = 4000) -> String? {
        guard let surface else { return nil }
        let topLeft = ghostty_point_s(tag: GHOSTTY_POINT_SCREEN, coord: GHOSTTY_POINT_COORD_TOP_LEFT, x: 0, y: 0)
        let bottomRight = ghostty_point_s(
            tag: GHOSTTY_POINT_SCREEN,
            coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT,
            x: 0,
            y: 0
        )
        let selection = ghostty_selection_s(top_left: topLeft, bottom_right: bottomRight, rectangle: true)
        var text = ghostty_text_s()
        guard ghostty_surface_read_text(surface, selection, &text) else { return nil }
        defer { ghostty_surface_free_text(surface, &text) }
        guard let ptr = text.text, text.text_len > 0 else { return nil }
        var output = String(decoding: Data(bytes: ptr, count: Int(text.text_len)), as: UTF8.self)
        let lines = output.components(separatedBy: "\n")
        if lines.count > lineLimit {
            output = lines.suffix(lineLimit).joined(separator: "\n")
        }
        guard output.contains(where: { !$0.isWhitespace }) else { return nil }
        return output
    }

    // MARK: - View lifecycle

    override var acceptsFirstResponder: Bool {
        true
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result, let surface {
            ghostty_surface_set_focus(surface, true)
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result, let surface {
            ghostty_surface_set_focus(surface, false)
        }
        return result
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let surface, let window else { return }

        if let screen = window.screen ?? NSScreen.main {
            ghostty_surface_set_display_id(surface, screen.displayID)
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contentsScale = window.backingScaleFactor
        CATransaction.commit()

        updateSurfaceSize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        guard let surface else { return }

        if let window {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.contentsScale = window.backingScaleFactor
            CATransaction.commit()
        }

        let fbFrame = convertToBacking(frame)
        let xScale = frame.width > 0 ? fbFrame.width / frame.width : 2.0
        let yScale = frame.height > 0 ? fbFrame.height / frame.height : 2.0
        ghostty_surface_set_content_scale(surface, xScale, yScale)

        updateSurfaceSize()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateSurfaceSize()
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .inVisibleRect, .activeAlways],
            owner: self,
            userInfo: nil
        ))
    }

    private func updateSurfaceSize() {
        guard let surface else { return }
        let scaledSize = convertToBacking(bounds.size)
        let w = UInt32(max(1, scaledSize.width))
        let h = UInt32(max(1, scaledSize.height))
        ghostty_surface_set_size(surface, w, h)
    }

    // MARK: - Keyboard input

    override func keyDown(with event: NSEvent) {
        guard let surface else { return }
        onInput?()

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.control) && !flags.contains(.command) && !flags.contains(.option) && !hasMarkedText() {
            let action: ghostty_input_action_e = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
            var keyEvent = ghostty_input_key_s()
            keyEvent.action = action
            keyEvent.keycode = UInt32(event.keyCode)
            keyEvent.mods = Self.ghosttyMods(event.modifierFlags)
            keyEvent.consumed_mods = GHOSTTY_MODS_NONE
            keyEvent.composing = false
            keyEvent.unshifted_codepoint = Self.unshiftedCodepoint(event)

            let text = event.charactersIgnoringModifiers ?? event.characters ?? ""
            if text.isEmpty {
                keyEvent.text = nil
                _ = ghostty_surface_key(surface, keyEvent)
            } else {
                text.withCString { ptr in
                    keyEvent.text = ptr
                    _ = ghostty_surface_key(surface, keyEvent)
                }
            }
            return
        }

        let translationMods = ghostty_surface_key_translation_mods(surface, Self.ghosttyMods(event.modifierFlags))
        let translationFlags = Self.nsEventMods(translationMods)

        let translationEvent: NSEvent = if translationFlags == event.modifierFlags {
            event
        } else {
            NSEvent.keyEvent(
                with: event.type,
                location: event.locationInWindow,
                modifierFlags: translationFlags,
                timestamp: event.timestamp,
                windowNumber: event.windowNumber,
                context: nil,
                characters: event.characters(byApplyingModifiers: translationFlags) ?? event.characters ?? "",
                charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
                isARepeat: event.isARepeat,
                keyCode: event.keyCode
            ) ?? event
        }

        let action: ghostty_input_action_e = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
        let markedBefore = markedText.length > 0

        keyTextAccumulator = []
        defer { keyTextAccumulator = nil }

        interpretKeyEvents([translationEvent])

        syncPreedit(clearIfNeeded: markedBefore)

        if let texts = keyTextAccumulator, !texts.isEmpty {
            for text in texts {
                sendKeyEvent(action, event: event, translationEvent: translationEvent, text: text)
            }
        } else {
            let text = Self.textForKeyEvent(translationEvent)
            sendKeyEvent(action, event: event, translationEvent: translationEvent, text: text)
        }
    }

    override func keyUp(with event: NSEvent) {
        sendKeyEvent(GHOSTTY_ACTION_RELEASE, event: event)
    }

    override func flagsChanged(with event: NSEvent) {
        guard let surface else { return }

        let mod: UInt32
        switch event.keyCode {
        case 0x39: mod = GHOSTTY_MODS_CAPS.rawValue
        case 0x38, 0x3C: mod = GHOSTTY_MODS_SHIFT.rawValue
        case 0x3B, 0x3E: mod = GHOSTTY_MODS_CTRL.rawValue
        case 0x3A, 0x3D: mod = GHOSTTY_MODS_ALT.rawValue
        case 0x37, 0x36: mod = GHOSTTY_MODS_SUPER.rawValue
        default: return
        }

        let mods = Self.ghosttyMods(event.modifierFlags)
        let action: ghostty_input_action_e = (mods.rawValue & mod != 0) ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE

        var keyEvent = ghostty_input_key_s()
        keyEvent.action = action
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.mods = mods
        keyEvent.consumed_mods = GHOSTTY_MODS_NONE
        keyEvent.text = nil
        keyEvent.composing = false
        _ = ghostty_surface_key(surface, keyEvent)
    }

    private func sendKeyEvent(
        _ action: ghostty_input_action_e,
        event: NSEvent,
        translationEvent: NSEvent? = nil,
        text: String? = nil
    ) {
        guard let surface else { return }

        var keyEvent = ghostty_input_key_s()
        keyEvent.action = action
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.mods = Self.ghosttyMods(event.modifierFlags)
        keyEvent.consumed_mods = Self.consumedMods(translationEvent?.modifierFlags ?? event.modifierFlags)
        keyEvent.composing = markedText.length > 0
        keyEvent.unshifted_codepoint = Self.unshiftedCodepoint(event)

        if let text, !text.isEmpty, Self.shouldSendText(text) {
            text.withCString { ptr in
                keyEvent.text = ptr
                _ = ghostty_surface_key(surface, keyEvent)
            }
        } else {
            keyEvent.text = nil
            _ = ghostty_surface_key(surface, keyEvent)
        }
    }

    private func syncPreedit(clearIfNeeded: Bool = true) {
        guard let surface else { return }
        if markedText.length > 0 {
            let str = markedText.string
            str.withCString { ptr in
                ghostty_surface_preedit(surface, ptr, UInt(str.utf8CString.count - 1))
            }
        } else if clearIfNeeded {
            ghostty_surface_preedit(surface, nil, 0)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        guard window?.firstResponder === self else { return false }

        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods.contains(.control), !mods.contains(.command) {
            self.keyDown(with: event)
            return true
        }

        return false
    }

    override func doCommand(by selector: Selector) {}

    override func insertText(_ insertString: Any) {
        insertText(insertString, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    // MARK: - NSTextInputClient

    func insertText(_ string: Any, replacementRange: NSRange) {
        var chars = ""
        switch string {
        case let v as NSAttributedString: chars = v.string
        case let v as String: chars = v
        default: return
        }

        unmarkText()

        if var acc = keyTextAccumulator {
            acc.append(chars)
            keyTextAccumulator = acc
            return
        }

        guard let surface else { return }
        ghostty_surface_text(surface, chars, UInt(chars.utf8.count))
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        switch string {
        case let v as NSAttributedString: markedText = NSMutableAttributedString(attributedString: v)
        case let v as String: markedText = NSMutableAttributedString(string: v)
        default: return
        }
        syncPreedit()
    }

    func unmarkText() {
        markedText = NSMutableAttributedString()
    }

    func selectedRange() -> NSRange {
        NSRange(location: NSNotFound, length: 0)
    }

    func markedRange() -> NSRange {
        guard markedText.length > 0 else { return NSRange(location: NSNotFound, length: 0) }
        return NSRange(location: 0, length: markedText.length)
    }

    func hasMarkedText() -> Bool {
        markedText.length > 0
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        nil
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    func characterIndex(for point: NSPoint) -> Int {
        0
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let surface, let window else { return .zero }
        var x: Double = 0, y: Double = 0, w: Double = 0, h: Double = 0
        ghostty_surface_ime_point(surface, &x, &y, &w, &h)
        let viewRect = NSRect(x: x, y: frame.height - y - h, width: w, height: h)
        let winRect = convert(viewRect, to: nil)
        return window.convertToScreen(winRect)
    }

    func attributedString() -> NSAttributedString {
        NSAttributedString()
    }

    func fractionOfDistanceThroughGlyph(for point: NSPoint) -> CGFloat {
        0
    }

    func baselineDeltaForCharacter(at anIndex: Int) -> CGFloat {
        0
    }

    func windowLevel() -> Int {
        window?.level.rawValue ?? 0
    }

    func drawsVerticallyForCharacter(at charIndex: Int) -> Bool {
        false
    }

    // MARK: - Mouse input

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let surface else { return }
        let mods = Self.ghosttyMods(event.modifierFlags)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, mods)
    }

    override func mouseUp(with event: NSEvent) {
        guard let surface else { return }
        _ = ghostty_surface_mouse_button(
            surface,
            GHOSTTY_MOUSE_RELEASE,
            GHOSTTY_MOUSE_LEFT,
            Self.ghosttyMods(event.modifierFlags)
        )
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let surface else { return super.rightMouseDown(with: event) }
        if !ghostty_surface_mouse_button(
            surface,
            GHOSTTY_MOUSE_PRESS,
            GHOSTTY_MOUSE_RIGHT,
            Self.ghosttyMods(event.modifierFlags)
        ) {
            super.rightMouseDown(with: event)
        }
    }

    override func rightMouseUp(with event: NSEvent) {
        guard let surface else { return }
        _ = ghostty_surface_mouse_button(
            surface,
            GHOSTTY_MOUSE_RELEASE,
            GHOSTTY_MOUSE_RIGHT,
            Self.ghosttyMods(event.modifierFlags)
        )
    }

    override func otherMouseDown(with event: NSEvent) {
        guard let surface else { return }
        _ = ghostty_surface_mouse_button(
            surface,
            GHOSTTY_MOUSE_PRESS,
            mouseButton(event.buttonNumber),
            Self.ghosttyMods(event.modifierFlags)
        )
    }

    override func otherMouseUp(with event: NSEvent) {
        guard let surface else { return }
        _ = ghostty_surface_mouse_button(
            surface,
            GHOSTTY_MOUSE_RELEASE,
            mouseButton(event.buttonNumber),
            Self.ghosttyMods(event.modifierFlags)
        )
    }

    override func mouseMoved(with event: NSEvent) {
        guard let surface else { return }
        let pos = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, pos.x, bounds.height - pos.y, Self.ghosttyMods(event.modifierFlags))
    }

    override func mouseDragged(with event: NSEvent) {
        mouseMoved(with: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        mouseMoved(with: event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        mouseMoved(with: event)
    }

    override func mouseEntered(with event: NSEvent) {
        mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        guard let surface else { return }
        if NSEvent.pressedMouseButtons != 0 { return }
        ghostty_surface_mouse_pos(surface, -1, -1, Self.ghosttyMods(event.modifierFlags))
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }
        var x = event.scrollingDeltaX
        var y = event.scrollingDeltaY

        if event.hasPreciseScrollingDeltas {
            x *= 2
            y *= 2
        }

        var mods: Int32 = 0
        if event.hasPreciseScrollingDeltas {
            mods |= 1
        }
        switch event.momentumPhase {
        case .began: mods |= Int32(GHOSTTY_MOUSE_MOMENTUM_BEGAN.rawValue) << 1
        case .changed: mods |= Int32(GHOSTTY_MOUSE_MOMENTUM_CHANGED.rawValue) << 1
        case .ended: mods |= Int32(GHOSTTY_MOUSE_MOMENTUM_ENDED.rawValue) << 1
        default: break
        }

        ghostty_surface_mouse_scroll(surface, x, y, mods)
    }

    // MARK: - Helpers

    static func ghosttyMods(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var mods: UInt32 = GHOSTTY_MODS_NONE.rawValue
        if flags.contains(.shift) { mods |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.control) { mods |= GHOSTTY_MODS_CTRL.rawValue }
        if flags.contains(.option) { mods |= GHOSTTY_MODS_ALT.rawValue }
        if flags.contains(.command) { mods |= GHOSTTY_MODS_SUPER.rawValue }
        if flags.contains(.capsLock) { mods |= GHOSTTY_MODS_CAPS.rawValue }
        return ghostty_input_mods_e(rawValue: mods)
    }

    static func nsEventMods(_ mods: ghostty_input_mods_e) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if mods.rawValue & GHOSTTY_MODS_SHIFT.rawValue != 0 { flags.insert(.shift) }
        if mods.rawValue & GHOSTTY_MODS_CTRL.rawValue != 0 { flags.insert(.control) }
        if mods.rawValue & GHOSTTY_MODS_ALT.rawValue != 0 { flags.insert(.option) }
        if mods.rawValue & GHOSTTY_MODS_SUPER.rawValue != 0 { flags.insert(.command) }
        if mods.rawValue & GHOSTTY_MODS_CAPS.rawValue != 0 { flags.insert(.capsLock) }
        return flags
    }

    static func consumedMods(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var mods: UInt32 = GHOSTTY_MODS_NONE.rawValue
        if flags.contains(.shift) { mods |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.option) { mods |= GHOSTTY_MODS_ALT.rawValue }
        return ghostty_input_mods_e(rawValue: mods)
    }

    static func textForKeyEvent(_ event: NSEvent) -> String? {
        guard let chars = event.characters, !chars.isEmpty else { return nil }
        if chars.count == 1, let scalar = chars.unicodeScalars.first {
            if scalar.value < 0x20 {
                return event.characters(byApplyingModifiers: event.modifierFlags.subtracting(.control))
            }
            if scalar.value >= 0xF700, scalar.value <= 0xF8FF {
                return nil
            }
        }
        return chars
    }

    private static func shouldSendText(_ text: String) -> Bool {
        guard let first = text.utf8.first else { return false }
        return first >= 0x20
    }

    static func unshiftedCodepoint(_ event: NSEvent) -> UInt32 {
        guard event.type == .keyDown || event.type == .keyUp,
              let chars = event.characters(byApplyingModifiers: []),
              let scalar = chars.unicodeScalars.first,
              scalar.value >= 0x20,
              !(scalar.value >= 0xF700 && scalar.value <= 0xF8FF) else { return 0 }
        return scalar.value
    }

    private func mouseButton(_ buttonNumber: Int) -> ghostty_input_mouse_button_e {
        switch buttonNumber {
        case 0: GHOSTTY_MOUSE_LEFT
        case 1: GHOSTTY_MOUSE_RIGHT
        case 2: GHOSTTY_MOUSE_MIDDLE
        default: GHOSTTY_MOUSE_UNKNOWN
        }
    }
}

extension NSScreen {
    var displayID: UInt32 {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

// MARK: - Convenience factory

extension GhosttySurfaceView {
    static func create(
        workingDirectory: String,
        command: String? = nil,
        paneID: UUID? = nil
    ) -> GhosttySurfaceView {
        var envVars = ["WEAVE": "1"]
        if let paneID {
            envVars["WEAVE_TAB_ID"] = paneID.uuidString
        }
        if let resourcePath = Bundle.main.resourcePath {
            let terminfo = resourcePath + "/ghostty/terminfo"
            if FileManager.default.fileExists(atPath: terminfo) {
                envVars["TERMINFO"] = terminfo
            }
        }
        return GhosttySurfaceView(workingDirectory: workingDirectory, command: command, envVars: envVars)
    }
}
