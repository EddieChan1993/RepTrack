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
快速构建脚本：`bash build.sh`（自动杀旧进程、构建、启动）

---

## 历史问题与解决方案

### 1. 多等级同时提交丢失数据
**问题**：AddSessionView 中，用户在 S2 加完课程切换到 S3 再加课程，最后点保存时 S3 的选择丢失。  
**原因**：`save()` 直接跳过了当前已选但未点"添加"的输入。  
**解决**：`save()` 开头增加 `if canAddEntry { addEntry() }`，先 flush 当前选中的 chip 再执行保存。

---

### 2. 重新导入文件夹时课程不同步
**问题**：删除或重命名课程文件后重新导入同一等级文件夹，已删除的课程仍然保留，改名的课程未更新标题。  
**解决**：`importSingleLevel` 分两步处理：
1. 遍历新文件列表，已有课程更新标题，新课程追加。
2. 找出旧课程中编号不在新列表的（用 `sameNumber` 比较），从 `levels` 中删除，并级联清理 `sessions` 中引用了这些课程的 item；item 全空则整条 session 删除。

---

### 3. `PRODUCT_NAME` 导致 .app 名字不对
**问题**：将 app 改名为 BananaTrack 后，`build.sh` 找不到 `BananaTrack.app`，因为构建产物仍叫 `RepTrack.app`。  
**原因**：`PRODUCT_NAME = $(TARGET_NAME)`，而 target 名是 `RepTrack`。  
**解决**：在 `project.pbxproj` 的 Debug 和 Release 两个 configuration 中均显式设置 `PRODUCT_NAME = BananaTrack`。

---

### 4. 推荐复习卡高度与图表卡不一致
**问题**：`RecommendedLessonsCard` / `LevelRecommendedCard` 放在外层 `ScrollView` 内时，`.frame(height:)` 传入计算值无法匹配左侧图表卡的实际渲染高度。  
**解决**：用 `PreferenceKey`（`CardHeightKey`）在图表卡的 `background(GeometryReader)` 中读取实际渲染高度，通过 `.onPreferenceChange` 写入 `@State var chartCardHeight`，再 `.frame(height: chartCardHeight > 0 ? chartCardHeight : nil)` 约束推荐卡。

---

### 5. `.frame(minWidth:maxWidth:height:)` 编译报错
**错误**：`extra argument 'height' in call`  
**原因**：SwiftUI 的 `.frame()` 不允许在同一次调用中混用 min/max 尺寸参数和固定尺寸参数。  
**解决**：拆成两次调用：
```swift
.frame(minWidth: 190, maxWidth: 240)
.frame(height: chartCardHeight > 0 ? chartCardHeight : nil)
```

---

### 6. 推荐卡滚动条遮住数字徽章
**问题**：`ScrollView` 的滚动条指示器叠在右侧复习次数徽章上。  
**解决**：`showsIndicators: false` 隐藏滚动条；同时将 `Spacer()` 改为 `Spacer(minLength: 8)` 保证徽章与课程名之间有最小间距。

---

### 7. X 轴标签过多时拥挤重叠
**问题**：课程数超过 30 时，x 轴标签密集重叠难以阅读。  
**解决**：动态计算显示步长 `xAxisStride = ceil(n / 30)`，在 `AxisMarks` 闭包中只对 `xAxisValues`（按步长筛选后的 key 集合）中的值渲染 `AxisValueLabel`，网格线仍对所有柱显示。规则：≤30 课全显示，每多 30 课步长加一。
