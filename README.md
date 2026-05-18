# RepTrack

A native macOS app for tracking spaced-repetition language course reviews.

![RepTrack screenshot](docs/screenshot.png)

## Features

- **Multi-level course management** — import lesson folders (e.g. S1-EK, S2-IC, S3-IK) or add lessons manually; drag tabs to reorder levels
- **Batch session logging** — record multiple lessons across multiple levels and multiple dates in a single save
- **Interactive stats** — coverage and review-count charts powered by Swift Charts; hover for tooltips; tap stat cards to cycle Today / This Week / This Month
- **Review log** — chronological list grouped by month; inline edit or delete with confirmation
- **Cloud-sync friendly** — point the data file at any folder (Nutstore, iCloud Drive, Dropbox) on first launch or via the toolbar; export/import JSON backups at any time

## Requirements

- macOS 14 Sonoma or later
- Xcode 15 or later (to build from source)

## Getting Started

1. Clone the repo and open `RepTrack.xcodeproj` in Xcode
2. Build and run (⌘R)
3. On first launch, choose where to store your data file (or keep the default `~/Library/Application Support/RepTrack/data.json`)
4. Click the folder-plus toolbar icon to import a course directory, or add lessons manually via the level tabs

### Importing a course directory

Each selected folder becomes one **level** (e.g. `S3-IK`). Files inside the folder become **lessons** — the filename stem is parsed as `<number>.<title>.md`, for example:

```
S3-IK/
  011.烹饪.md
  012.点餐.md
  043.时态梳理.md
```

Non-markdown files are ignored. You can re-import a folder later to add new lessons or update titles without duplicating existing data.

## Adding a Review Session

1. Press **⌘N** or click **+** in the toolbar
2. Select a level, type lesson numbers (comma-separated, e.g. `43, 44`) and click **添加**
3. Switch to another level and add more lessons — each level-date combination becomes a separate entry in the pending list
4. Click **保存记录** — sessions are grouped by date automatically (any unsaved input in the text field is also flushed before saving)

## Data Format

Data is stored as a single JSON file:

```json
{
  "levels": [{ "id": "S3-IK", "lessons": [...] }],
  "sessions": [{ "id": "...", "date": "...", "items": [...] }]
}
```

You can export a snapshot at any time via the drive toolbar icon → **导出备份**, and restore it with **从文件导入**.

## Project Structure

```
RepTrack/
├── Models.swift            # Value types (Level, Lesson, ReviewSession, …)
├── DataStore.swift         # @Observable store — CRUD + persistence
├── Helpers.swift           # Pure utilities and StatPeriod enum
├── ContentView.swift       # Root VSplitView layout + toolbar
├── StatsView.swift         # Tab bar + stat cards + Swift Charts
├── LogView.swift           # Session list with edit/delete
├── AddSessionView.swift    # Add/edit session sheet
├── DataSettingsView.swift  # Storage location + import/export
└── ManageLevelsView.swift  # Level and lesson management
```

## License

MIT
