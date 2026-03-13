import Foundation

enum HookSetup {
    static let hooksDir = "~/.weave/hooks".expandingTilde
    static let notifyPath = "~/.weave/hooks/notify.sh".expandingTilde
    private static let claudeSettingsPath = NSHomeDirectory() + "/.claude/settings.json"

    static func install() {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: hooksDir, withIntermediateDirectories: true)

        writeNotifyScript()
        installClaudeHooks()
    }

    private static func writeNotifyScript() {
        let fm = FileManager.default
        let content = notifyScript
        if let existing = fm.contents(atPath: notifyPath),
           String(data: existing, encoding: .utf8) == content
        {
            return
        }
        fm.createFile(
            atPath: notifyPath,
            contents: content.data(using: .utf8),
            attributes: [.posixPermissions: 0o755]
        )
    }

    private static func installClaudeHooks() {
        var settings: [String: Any] = [:]
        if let data = FileManager.default.contents(atPath: claudeSettingsPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            settings = json
        }

        let hookEntry: [String: Any] = ["type": "command", "command": notifyPath]
        let withMatcher: [String: Any] = ["matcher": "*", "hooks": [hookEntry]]
        let withoutMatcher: [String: Any] = ["hooks": [hookEntry]]

        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        let events: [(String, Bool)] = [
            ("UserPromptSubmit", false),
            ("Stop", false),
            ("PostToolUse", true),
            ("PostToolUseFailure", true),
            ("PermissionRequest", true),
        ]

        var changed = false
        for (event, needsMatcher) in events {
            var entries = hooks[event] as? [[String: Any]] ?? []
            let alreadyInstalled = entries.contains { entry in
                let hooksList = entry["hooks"] as? [[String: Any]] ?? []
                return hooksList.contains { ($0["command"] as? String) == notifyPath }
            }
            if !alreadyInstalled {
                entries.append(needsMatcher ? withMatcher : withoutMatcher)
                hooks[event] = entries
                changed = true
            }
        }

        guard changed else { return }
        settings["hooks"] = hooks

        let fm = FileManager.default
        try? fm.createDirectory(atPath: NSHomeDirectory() + "/.claude", withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) {
            fm.createFile(atPath: claudeSettingsPath, contents: data)
        }
    }

    static var notifyScript: String {
        """
        #!/bin/bash
        # Weave agent notification hook

        [ -z "$WEAVE_TAB_ID" ] && exit 0

        INPUT=$(cat)
        EVENT_TYPE=$(echo "$INPUT" | grep -oE '"hook_event_name"[[:space:]]*:[[:space:]]*"[^"]*"' | grep -oE '"[^"]*"$' | tr -d '"')

        case "$EVENT_TYPE" in
            UserPromptSubmit|PostToolUse|PostToolUseFailure) STATUS="working" ;;
            Stop) STATUS="idle" ;;
            PermissionRequest) STATUS="permission" ;;
            *) exit 0 ;;
        esac

        STATUS_DIR="$HOME/.weave/status"
        mkdir -p "$STATUS_DIR"
        rm -f "$STATUS_DIR/$WEAVE_TAB_ID"
        echo "$STATUS" > "$STATUS_DIR/$WEAVE_TAB_ID"

        exit 0
        """
    }
}
