# Weave — Parallel Workstream Manager

Native macOS app (Swift/SwiftUI + libghostty) for managing parallel development workstreams. Each "thread" is a git worktree + a real terminal session. Create a thread, get a worktree and a shell in it. Switch between threads instantly. Delete a thread, both are cleaned up.

The rough idea is to have UX similar to superset.sh (https://github.com/superset-sh/superset) but the performance and polish of a native app like cmux (https://github.com/manaflow-ai/cmux). Feel free to clone these into `/tmp` (they may already be there) for inspiration or a reference to compare against to see how they implemented things. Don't need to copy, but it's available to understand how things work.

## Architecture

### Why this stack

- **libghostty** for terminal rendering: GPU-accelerated (Metal), handles PTY, terminal emulation, input, clipboard — we just provide an NSView with a Metal layer and forward events.
- **SwiftUI** for the UI shell: sidebar, thread list, toolbar, dialogs. Native macOS look and feel.
- **Git worktrees** for parallel development: each thread gets its own working directory branched from the repo.
- **No tmux in v1**: libghostty surfaces spawn shells directly via PTY. Migration to tmux-backed sessions is planned for v2 (swap the shell command from `/bin/zsh` to `tmux new-session -A -s <name>`, UI doesn't change).

### Key dependency: libghostty

- Ghostty included as a **git submodule** at `vendor/ghostty`, tracking upstream (no fork patches).
- Built as a static library via `zig build -Doptimize=ReleaseFast`.
- C API surface: `ghostty.h` (~1,176 lines, 4 opaque types: `ghostty_config_t`, `ghostty_app_t`, `ghostty_surface_t`, `ghostty_inspector_t`).
- Reference implementations: Ghostty's own `macos/Sources/Helpers/Ghostty/SurfaceView.swift` and cmux's `GhosttyTerminalView.swift`.
- Upgrade path: `git submodule update --remote`, rebuild.

## Data Model (not set in stone)

```
Repo
  - id: UUID
  - name: String                    // e.g. "my-project"
  - path: String                    // path to the main repo clone
  - worktreeBase: String            // where worktrees live (default: ~/.weave/worktrees/<repo>/)
  - threads: [Thread]
  - defaultTabs: [TabConfig]?       // auto-open tabs from config (e.g. ["cl", ""])

Thread
  - id: UUID
  - name: String                    // branch/feature name (spaces → hyphens)
  - worktreePath: String            // ~/.weave/worktrees/<repo>/<thread>/
  - branch: String                  // git branch name
  - status: ThreadStatus            // .running, .idle, .new
  - surface: ghostty_surface_t?     // nil until activated
  - prStatus: PRStatus?             // .draft, .open, .merged, .closed, .none
  - prURL: String?
  - createdAt: Date
  - lastActiveAt: Date

ThreadStatus
  - .running    // shell/agent actively producing output
  - .idle       // session exists but quiet
  - .new        // output changed since last viewed

PRStatus
  - .draft, .open, .merged, .closed, .none
```

## UI Layout (rough idea, please make it better and more polished. This is just inspiration)

```
┌─────────────────────┬──────────────────────────────────────────┐
│  my-project ▾       │                                          │
│                     │                                          │
│  ● feature-auth  ×  │                                          │
│    PR #42 ○ Open    │    Active terminal surface               │
│  ◉ feature-pay   ×  │    (libghostty Metal rendering)          │
│    PR #51 ● Draft   │                                          │
│  ○ bugfix-login  ×  │                                          │
│    No PR            │                                          │
│                     │                                          │
│  other-repo ▾       │                                          │
│                     │                                          │
│  ○ refactor-api  ×  │                                          │
│    PR #12 ✓ Merged  │                                          │
│                     │                                          │
│                     │                                          │
│                     │                                          │
│                     │                                          │
│                     │                                          │
│                     │                                          │
└─────────────────────┴──────────────────────────────────────────┘
```

### Sidebar (left, fixed width ~250pt)

- **Repo sections**: collapsible, each repo is a header with its threads listed below.
- **Thread rows**: clickable to switch. Each shows:
  - Status icon: `●` running (animated pulse when agent is active), `○` idle, `◉` new (unread output)
  - Thread/branch name
  - PR status + link (clickable opens in browser)
  - `×` delete button (hover-visible)
- **Inline input**: creating a new thread shows a text field in the sidebar (not a modal/sheet that covers the terminal).
- Active repo context determined by which repo section is focused/expanded. `n` creates in the focused repo. If ambiguous, show a quick picker.

### Terminal area (right, fills remaining space)

- Single libghostty surface showing the active thread's terminal.
- All surfaces stay alive in memory for instant switching (no shell restart).
- When no thread is selected: show an empty state with instructions.

## Core Operations

### Create thread

1. User presses `cmd + n` (or clicks "+ New").
2. Inline text field appears in the sidebar under the active repo.
3. User types name (e.g. "auth flow"). Spaces auto-replaced with hyphens → `auth-flow`.
4. On confirm:
   - `git worktree add <worktreeBase>/<repo>/<thread> -b <thread> HEAD`
   - Create libghostty surface with `cwd` set to the new worktree path.
   - If `defaultTabs` configured, run the startup commands (e.g. open `cl` in one tab, blank shell in another — initially just run the first command in the shell).
   - Add thread to the repo's thread list, set as active.
5. On failure: roll back (remove partial worktree, free surface, show error).

### Switch thread

1. User clicks thread in sidebar, or uses `↑`/`↓` + `Enter`, or `Alt+1-9`.
2. Active surface is hidden (not destroyed), new surface is shown and focused.
3. If the thread's surface was nil (e.g. reconnecting after restart), create a new surface in the existing worktree directory.
4. Mark thread as no longer `.new` (clear unread indicator).

### Delete thread

1. User presses cmd delete or clicks `×` on a thread row.
2. Confirmation prompt (inline or alert).
3. On confirm:
   - `ghostty_surface_free()` if surface exists.
   - `git worktree remove <path>` (with `--force` option behind a setting).
   - Optionally delete the branch: `git branch -d <branch>` (prompt or setting).
   - Remove thread from list.
   - If deleted thread was active, switch to adjacent thread.

### Add repo

1. User presses shortcut.
2. File picker or path input appears.
3. Validate it's a git repo.
4. Add to repo list. Scan for existing worktrees via `git worktree list --porcelain`.
5. Create Thread objects for each existing worktree found.

### Attach (enter a thread's terminal)

Clicking a thread or pressing Enter switches the terminal surface. The terminal is always live — there's no separate "attach" step since libghostty surfaces are persistent.

### Open in VS Code

When the terminal is focused, can press cmd + o to open in vscode:
```
code <worktreePath>
```

## Configuration

File: `~/.config/weave/config.yaml`

```yaml
worktree_base: ~/.weave/worktrees    # where worktrees are created

repos:
  - path: ~/Developer/my-project
    default_tabs:                     # commands to run on new thread creation
      - cl                            # e.g. opens claude
      - ""                            # blank shell

  - path: ~/Developer/other-repo
    default_tabs:
      - ""

editor_command: code                  # command to open worktree in editor
delete_branch_on_remove: false        # also delete the git branch when deleting a thread
force_remove_worktree: false          # use --force when removing worktrees

# v2
# tmux_backend: false                 # switch to tmux-backed sessions
```

On startup, the app:
1. Reads config.
2. For each repo, runs `git worktree list --porcelain` to discover existing worktrees.
3. Reconciles with any previously known threads (restores metadata like PR links).
4. Creates surfaces for the last-active thread in each repo.

## State Persistence

File: `~/.weave/state.json`

Stores:
- Last active repo + thread.
- Thread metadata that isn't derivable from git (PR URLs, last-viewed timestamps for unread detection).
- Window size/position.

On relaunch:
- Worktrees still exist on disk → threads are restored.
- If a thread's worktree was removed externally → thread is removed from the list.
- Surfaces are created fresh (libghostty doesn't persist terminal state in v1; tmux migration in v2 solves this).

## GitHub PR Status (nice to have)

- On thread creation or periodically, run `gh pr list --head <branch> --json number,state,url,isDraft`.
- If a PR exists for the branch, populate `prStatus` and `prURL`.
- Display in sidebar. Clicking the PR line opens the URL in the browser.
- Refresh interval: configurable, default 60s. Only for visible/active threads.

## Auto-close Claude Sessions (nice to have)

- Track terminal output timestamps per thread.
- After a configurable timeout (e.g. 30min of no output), detect if a Claude session is running (heuristic: check for `claude` process in the PTY's process group, or pattern-match the terminal output).
- Kill the process to free memory.
- Store a flag on the thread: `claudeWasSuspended = true`.
- On next switch to that thread, if the flag is set, run `clc` (claude continue) automatically.
- This is inherently heuristic. Start simple (timeout + process name check), iterate.

## Testing Harness (nice to have)

- XCTest / XCUITest for the SwiftUI layer.
- For integration testing: mock the git and ghostty layers behind protocols.
  - `GitWorktreeProvider` protocol: methods for create/delete/list worktrees.
  - `TerminalSurfaceProvider` protocol: wraps surface creation/destruction.
- Test scenarios: create thread, switch, delete, multi-repo, config loading, error rollback.
- For LLM-driven testing: expose an accessibility-friendly view hierarchy so UI state can be queried programmatically.

## GhosttyView Implementation Notes

The bridging layer between SwiftUI and libghostty. This is the riskiest piece — start here.

### Approach

- `GhosttyMetalView`: an `NSView` subclass that owns a `CAMetalLayer` and a `ghostty_surface_t`.
- `GhosttyTerminalView`: an `NSViewRepresentable` that wraps `GhosttyMetalView` for SwiftUI.
- On init: create `CAMetalLayer`, call `ghostty_surface_new()` with a surface config specifying the working directory and shell command.
- Forward all keyboard events via `ghostty_surface_key()` and `ghostty_surface_text()`.
- Forward mouse events via `ghostty_surface_mouse_*()`.
- Handle resize via `ghostty_surface_set_size()`.
- Clipboard: implement the clipboard callback in the runtime config to bridge to `NSPasteboard`.
- Display link: use `CVDisplayLink` or `CADisplayLink` to drive `ghostty_surface_draw()`.

### Reference code

- Ghostty upstream: `macos/Sources/Helpers/Ghostty/SurfaceView.swift` (canonical, cleanest).
- cmux: `Sources/GhosttyTerminalView.swift` (more features, shows what to strip out).

### What to skip initially

- Inspector support.
- Split panes within a surface.
- Custom font/theme (defer to Ghostty's own config file at `~/.config/ghostty/config`).

## Build & Project Structure

```
weave/
├── vendor/
│   └── ghostty/                 # git submodule (upstream ghostty)
├── Weave/
│   ├── App/
│   │   ├── WeaveApp.swift       # @main, app lifecycle, ghostty_app init
│   │   └── AppDelegate.swift    # NSApplicationDelegate for ghostty tick loop
│   ├── Terminal/
│   │   ├── GhosttyMetalView.swift    # NSView + CAMetalLayer + surface
│   │   └── GhosttyTerminalView.swift # NSViewRepresentable wrapper
│   ├── Model/
│   │   ├── Repo.swift
│   │   ├── Thread.swift
│   │   ├── ThreadStore.swift    # ObservableObject, manages all state
│   │   └── Config.swift         # YAML config parsing
│   ├── Git/
│   │   └── GitWorktree.swift    # shell out to git for worktree ops
│   ├── Views/
│   │   ├── SidebarView.swift
│   │   ├── ThreadRowView.swift
│   │   ├── TerminalAreaView.swift
│   │   ├── BottomBarView.swift
│   │   └── NewThreadInput.swift
│   └── Persistence/
│       └── StateStore.swift     # JSON state persistence
├── Weave.xcodeproj
├── Makefile                     # builds libghostty, then xcodebuild
├── SPEC.md
└── CLAUDE.md
```

## Milestones

**M1 — Terminal renders**: Get a single libghostty surface rendering in an NSView. Keyboard input works. This validates the entire approach.

**M2 — Thread management**: Create/delete/switch threads. Git worktree operations. Sidebar UI with thread list.

**M3 — Multi-repo + config**: Multiple repos in sidebar. YAML config file. Startup tab commands. State persistence across relaunches.

**M4 — Polish**: PR status in sidebar. Animated status icons. Bottom bar with editor shortcut. Unread detection.

**M5 — Nice-to-haves**: Auto-close Claude sessions. Testing harness.

## v2: tmux Migration

When ready, change surface creation to connect to tmux:

```swift
// v1: direct shell
surfaceConfig.command = "/bin/zsh"
surfaceConfig.cwd = thread.worktreePath

// v2: tmux-backed
surfaceConfig.command = "tmux new-session -A -s weave-\(thread.name) -c \(thread.worktreePath)"
```

This gives: session persistence across app restarts, ability to attach from a regular terminal, and background process survival. The UI, data model, and GhosttyView don't change.
