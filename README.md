# BananaTrack 🍌

A native macOS app for tracking spaced-repetition language course reviews.

![RepTrack screenshot](docs/screenshot.png)

## Features

- **Multi-level course management** — import lesson folders (e.g. S1-EK, S2-IC, S3-IK) or add lessons manually; drag tabs to reorder levels
- **Batch session logging** — record multiple lessons across multiple levels and multiple dates in a single save
- **Interactive stats** — coverage and review-count charts powered by Swift Charts; hover for tooltips; tap stat cards to cycle Today / This Week / This Month
- **Review log** — chronological list grouped by month; inline edit or delete with confirmation; auto-refreshes when the app returns from background
- **Daily email reminder** — send today's recommendations and yesterday's review content directly via SMTP (no mail client needed); beautifully formatted HTML email with level badges and review-count chips
- **Cloud-sync friendly** — point the data file at any folder (Nutstore, iCloud Drive, Dropbox) on first launch or via the toolbar; export/import JSON backups at any time

## Requirements

- macOS 14 Sonoma or later
- Xcode 15 or later (to build from source)

## Getting Started

1. Clone the repo and open `RepTrack.xcodeproj` in Xcode
2. Build and run (⌘R)
3. On first launch, choose where to store your data file (or keep the default `~/Library/Application Support/BananaTrack/data.json`)
4. Click the folder-plus toolbar icon to import a course directory, or add lessons manually via the level tabs

### Importing a course directory

Each selected folder becomes one **level** (e.g. `S3-IK`). Files inside the folder become **lessons** — the filename stem is parsed as `<number>.<title>`, for example:

```
课程根目录/
├── S1-EK/                   ← 等级文件夹（文件夹名即等级 ID）
│   ├── 001.一般过去式 When.md
│   ├── 002.时间介词.md
│   └── 003.购物.md
├── S2-IC/
│   ├── 000.话题通关.md
│   ├── 001.广告.md
│   └── 021.职业技能.md
└── S3-IK/
    ├── 011.烹饪.md
    ├── 012.点餐.md
    ├── 043.时态梳理.md
    └── 044.人生经历.md
```

**文件命名规则：**

| 部分 | 说明 | 示例 |
|------|------|------|
| `<编号>` | 纯数字，支持前置零（`011` 与 `11` 视为同一课） | `011`、`43` |
| `.` | 分隔符（英文句点） | |
| `<标题>` | 课程名称，可含中英文及空格 | `烹饪`、`一般过去式 When` |
| 扩展名 | 任意（`.md` 推荐），非数字开头的文件自动忽略 | `.md` |

**导入行为：**
- 首次导入：按文件列表创建等级和课程
- **重新导入同一文件夹**：已有文件 → 标题更新；新增文件 → 追加课程；**已删除文件 → 对应课程自动移除**，相关复习日志同步清理
- 可同时选择多个等级文件夹，一次性批量导入

## Adding a Review Session

1. Press **⌘N** or click **+** in the toolbar
2. Click lesson chips to select them (highlighted = selected; click again to deselect); switch levels to select from multiple levels
3. Click **添加** to commit the current selection to the pending list; use **清除** to reset
4. Click **保存记录** — sessions are grouped by date automatically

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
