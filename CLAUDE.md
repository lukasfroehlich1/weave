# Weave

Native macOS app (Swift/SwiftUI + libghostty) for managing parallel git worktrees with embedded terminal sessions.

## Build & Run

- **Build**: `xcodebuild -project Weave.xcodeproj -scheme Weave -configuration Debug build`
- **Run**: `open ~/Library/Developer/Xcode/DerivedData/Weave-ctubmypjxmvjnbawrnzysubshqeb/Build/Products/Debug/Weave.app`
- **Quit**: `osascript -e 'tell application "Weave" to quit'`
  - NEVER use `pkill` or `kill` — it bypasses `applicationWillTerminate` and loses scrollback history
  - Always quit gracefully before relaunching

## Ghostty XCFramework

- Git submodule at `vendor/ghostty`
- Build: `cd vendor/ghostty && zig build -Demit-xcframework=true -Dxcframework-target=native -Doptimize=ReleaseFast`
- Output symlinked to project root as `GhosttyKit.xcframework`
- `ghostty.h` copied to project root (avoids modulemap conflict)
- Zig 0.15.2 (homebrew)

## Project Structure

```
Weave/
  App/           — WeaveApp.swift, AppDelegate.swift
  Model/         — WeaveThread, ThreadStore, TerminalTab, Repo, WeaveConfig
  Terminal/      — GhosttyRuntime, GhosttySurfaceView, TerminalView
  Git/           — GitWorktree (shell-env PATH pattern for GUI apps)
  Views/         — SidebarView, TabBarView
  Persistence/   — StateStore, SessionStore (scrollback capture/replay)
  AgentStatus/   — AgentStatusMonitor (file watcher), HookSetup (Claude Code hooks)
  Extensions/    — String+Path
```

## Key Patterns

- **Keyboard input**: Ctrl fast path bypasses `interpretKeyEvents`; `shouldSendText` prevents control chars from being sent as text (fixes Kitty protocol for Shift+Enter etc.)
- **Scrollback restore**: On quit, captures terminal content via `ghostty_surface_read_text`. On restore, replays via `cat scrollback; exec zsh -l` command.
- **Agent status**: Hooks installed in `~/.claude/settings.json` fire `~/.weave/hooks/notify.sh` which writes to `~/.weave/status/<tab-id>`. App watches the status directory with DispatchSource.
- **Shell-env for git**: GUI apps get minimal PATH; `GitWorktree` spawns a login shell to capture the full PATH before running git commands.
