# RepTrack — Claude Code Guide

## Project Overview
RepTrack is a macOS SwiftUI app (macOS 14+) for tracking spaced-repetition language course reviews. Users log which lessons they reviewed on which dates, and the app visualises coverage and review frequency via Swift Charts.

## Architecture

### Key Files
| File | Purpose |
|---|---|
| `Models.swift` | Value types: `Level`, `Lesson`, `ReviewSession`, `ReviewItem`, `LessonStat`, `LevelStats` |
| `DataStore.swift` | `@Observable` store — all state, CRUD, persistence, import/export |
| `Helpers.swift` | Pure helpers: `StatPeriod`, `levelColor`, `paddedDisplay`, `normalizeNumber`, `lessonNumberLess`, `sameNumber`, `deduplicatedByNumber` |
| `ContentView.swift` | Root layout: `VSplitView` of `StatsView` (top) + `LogView` (bottom); toolbar actions |
| `StatsView.swift` | Tab bar, stat cards, Swift Charts (coverage bars + lesson frequency bars) |
| `LogView.swift` | Grouped session list with edit/delete per row |
| `AddSessionView.swift` | Sheet for adding (multi-date, multi-level) or editing a session |
| `DataSettingsView.swift` | First-launch onboarding + storage location / import / export settings |
| `ManageLevelsView.swift` | Inline level/lesson management |

### Data Flow
```
DataStore (@Observable)
  └─ injected via .environment() at app root
  └─ all views read store.levels / store.sessions directly
  └─ mutations only via store.* methods → auto-save to dataURL
```

### Persistence
- Data is stored as `data.json` (JSON-encoded `Saved` struct with `levels` + `sessions`)
- Default path: `~/Library/Application Support/RepTrack/data.json`
- Custom path stored in `UserDefaults["RepTrack.dataFilePath"]` — user can point to a cloud-sync folder (e.g. Nutstore)
- Active data path: set to Nutstore sync folder via DataSettingsView

## Important Invariants

### Lesson number handling
- Stored numbers are **not** zero-padded — stored as the user typed ("2", "43", "011")
- `paddedDisplay(n)` — display-only zero-padding ("2" → "002"), never mutates stored data
- `sameNumber(a, b)` — "2" == "002" == "2" (integer equality)
- `lessonNumberLess(a, b)` — numeric-aware sort ("2" < "10" < "19")
- `deduplicatedByNumber` — merges integer-equal duplicates, keeping non-empty title

### ensureLesson must only be called at save time
`store.ensureLesson(number:levelId:)` creates a lesson if it doesn't exist.  
**Never call it during `addEntry()` in add mode** — only call it inside `save()` when the user confirms. Calling it earlier creates ghost lessons that persist even if the user cancels.

### Session creation (add mode)
`AddSessionView` accumulates `[PendingEntry]` (raw lesson numbers, no IDs).  
`save()` groups by calendar day → builds `levelMap [levelId: [lessonId]]` → one `ReviewSession` per unique day.  
`save()` also auto-flushes any typed-but-not-yet-added `lessonInput` before saving.

### Level ordering
Level order is user-controlled via drag-and-drop in the tab bar (`store.swapLevels`).  
Whenever sorting session items for display, sort by `store.levels.firstIndex` — never alphabetically.

## Build
Open `RepTrack.xcodeproj` in Xcode 15+ and run on macOS 14+. No external dependencies.
