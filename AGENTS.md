# Stack — Agent Notes

## App Summary
- Native macOS menu bar app named **Stack**.
- Stack-based task manager with exactly one current task: the first in-progress task.
- Tracks elapsed time per task and separates tasks into **in-progress** and **completed** lists.
- Menu bar shows a stack icon plus the current task title when one exists.

## Platform & Tech
- Language: Swift
- UI: SwiftUI + AppKit
- Persistence: SwiftData
- System integrations: Carbon hotkey APIs, ServiceManagement launch-at-login
- Target: macOS 26
- Bundle ID: `com.erazemk.Stack`
- No Xcode UI; terminal-only workflow.
- No code signing or distribution required (local `.app` only).

## Menu Bar & Popover Behavior
- Accessory app (`LSUIElement`) with no Dock presence.
- Status item shows:
  - static icon when paused or when there is no current task
  - animated 3-frame icon when the current task is running
  - current task title, truncated to 128 characters with an ellipsis if needed
- Clicking the status item toggles a transient popover.
- Global hotkey also toggles the popover.
- Clicking outside closes the popover.
- Opening the popover activates the app and resets internal focus to the current task.
- Popover size is `320x700`.

## Task & Timer Rules
- `inProgressTasks.first` is always the current task.
- Only the current task may have a running timer.
- First task added becomes current and starts immediately.
- Normal add inserts the new task directly below the current task and does not start its timer.
- `Cmd+Enter` while adding creates a new active/current task.
- Completing a task moves it to the completed list.
- Completing the current task starts the next in-progress task if one exists.
- Uncompleting a completed task moves it to the top of in-progress and starts its timer.
- Task durations are shown as `Xs`, `Xm Ys`, or `Xh Ym`.
- On load/fetch, non-current running tasks are forced to stop.

## UI Structure
- Popover sections:
  - Current Task
  - Up Next
  - Completed
  - Add Task
  - Footer shortcut hints
- If help is shown, it replaces the normal task UI.
- Long task titles use marquee-style horizontal scrolling.
- Drag and drop reordering is supported only for **Up Next** tasks.
- Completed tasks are not reorderable.

## Keyboard Shortcuts
- Global: `Ctrl + Option + S` toggles the popover.
- Main shortcuts:
  - `Cmd+N` — show add-task UI
  - `Cmd+A` — make focused in-progress task active
  - `Cmd+S` — start/stop current task timer
  - `Cmd+C` — complete/uncomplete focused task
  - `Cmd+D` — delete focused task
  - `Cmd+R` — rename focused task
  - `Cmd+Z` / `Cmd+Shift+Z` — undo / redo
  - `Cmd+/` — toggle shortcuts help
  - `Cmd+Q` — quit
- Navigation:
  - `↑` / `↓` — move focus
  - `Cmd+↑` / `Cmd+↓` — reorder focused in-progress task
  - `Enter` — complete/uncomplete focused task
  - `Esc` — reset focus to current task
  - `0-9` — quick-select in-progress tasks
- Add mode:
  - `Enter` — add normally
  - `Cmd+Enter` — add as active
  - `Esc` — cancel
- Rename mode:
  - `Enter` — confirm
  - `Esc` — cancel

## Persistence & Cleanup
- Tasks persist locally with SwiftData.
- App auto-enables launch at login on startup.
- Completed tasks may be auto-cleared when the popover opens if:
  - midnight has passed since last activity
  - inactivity is at least 3 hours
  - completed tasks have not already been auto-cleared that day
- Auto-clear does not register undo.

## Packaging (Terminal-First)
- SwiftPM project rooted at `src/`.
- Main sources live in `src/Sources/Stack/`.
- Build with `make build`:
  - `swift build --package-path src --scratch-path .build -c release`
  - assemble `.app` inside `.build/Stack.app`
  - copy `Info.plist`, `AppIcon.icns`, and `en.lproj/Localizable.strings` into the bundle
- Install with `make install`:
  - copy app to `~/Applications/Stack.app`
  - stop the running app first if needed
