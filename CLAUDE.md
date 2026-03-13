# Weave

Native macOS app (Swift/SwiftUI + libghostty) for managing parallel git worktrees with embedded terminal sessions.

**Status**: Public alpha — breaking changes are expected. Don't push commits or create releases without explicit approval.

## Build & Run

- **Build**: `xcodebuild -project Weave.xcodeproj -scheme Weave -configuration Debug build`
- **Run**: `open ~/Library/Developer/Xcode/DerivedData/Weave-ctubmypjxmvjnbawrnzysubshqeb/Build/Products/Debug/Weave.app`
- **Quit**: `osascript -e 'tell application "Weave" to quit'`
  - NEVER use `pkill` or `kill` — it bypasses `applicationWillTerminate` and loses scrollback history
  - Always quit gracefully before relaunching

## Ghostty XCFramework

- Git submodule at `vendor/ghostty`
- Build: `cd vendor/ghostty && zig build -Demit-xcframework=true -Dxcframework-target=native -Doptimize=ReleaseFast`
- Xcode references the xcframework directly at `vendor/ghostty/macos/GhosttyKit.xcframework`
- `ghostty.h` copied to `Weave/` (avoids modulemap conflict with xcframework)
- Zig 0.15.2 (homebrew)

## Project Structure

```
Weave/
  App/           — WeaveApp.swift, AppDelegate.swift
  Model/         — AppState, WeaveThread, Tab, Pane, Repo, EditorLauncher
  Terminal/      — GhosttyRuntime, GhosttySurfaceView, TerminalView
  Git/           — GitWorktree (shell-env PATH pattern for GUI apps)
  Views/         — SidebarView
  Persistence/   — StateStore, SessionStore (scrollback capture/replay)
  AgentStatus/   — AgentStatusMonitor (file watcher), HookSetup (Claude Code hooks)
  Extensions/    — String+Path
```

## Key Patterns

- **Keyboard input**: Ctrl fast path bypasses `interpretKeyEvents`; `shouldSendText` prevents control chars from being sent as text (fixes Kitty protocol for Shift+Enter etc.)
- **Scrollback restore**: On quit, captures terminal content via `ghostty_surface_read_text`. On restore, replays via `cat scrollback; exec zsh -l` command.
- **Agent status**: Hooks installed in `~/.claude/settings.json` fire `~/.weave/hooks/notify.sh` which writes to `~/.weave/status/<tab-id>`. App watches the status directory with DispatchSource.
- **Shell-env for git**: GUI apps get minimal PATH; `GitWorktree` spawns a login shell to capture the full PATH before running git commands.

## Release & Distribution

- **GitHub repo**: `lukasfroehlich1/weave`
- **Homebrew tap**: `lukasfroehlich1/homebrew-tap` → `brew install lukasfroehlich1/tap/weave`
- **Release script**: `scripts/release.sh <version>` (stable) or `scripts/release.sh <version> beta` (beta)
  - Builds Release, re-signs Sparkle binaries, notarizes + staples, creates zip, signs for Sparkle, updates appcast, creates GitHub Release, updates Homebrew cask
- **Signing identity**: `Developer ID Application: Lukas Froehlich (TP77KRF2NP)`
- **Notarization**: keychain profile `weave-notarize` (App Store Connect API key stored via `xcrun notarytool store-credentials`)
- **Sparkle**: EdDSA keys in keychain, public key in Info.plist. Two appcast feeds: `appcast.xml` (stable) and `appcast-beta.xml` (beta)
- **Release build notes**: `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO` required for notarization. Sparkle framework binaries must be re-signed with Developer ID + `--timestamp` before notarizing.

## Known Issues

- **Agent status blue dot sticking**: DispatchSource directory watcher coalesces file events, causing the "needs input" indicator to not clear promptly. Polling fallback not yet implemented.
- **Kitty keyboard protocol leak**: Rare race condition on tab switch — if a process (e.g. Claude Code) enables Kitty protocol and exits during a tab switch, the protocol state can get stuck. Partial fix in place (resign first responder before removing surface).

## Work Tracking

- `tasks/` directory (gitignored) has prioritized issue lists: `p0-launch-blockers.md` through `p3-future.md`
