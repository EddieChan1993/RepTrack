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

---

## 变更记录

### 2026-06-22（再补充）
- 🐛 修复：数据加载时过滤 number 不含数字的 lesson（如 "Untitled"），无需手动刷新自动清理
- 🐛 修复：导入时同步过滤无效 number，防止 `Untitled.md` 等非课程文件被导入

### 2026-06-22（补充）
- 🐛 修复：热力图星期标签错位（Mon/Wed/Fri 下偏一行）→ 索引从 `[1,3,5]` 改为 `[0,2,4]`，与周一起始的格子对齐
- 🐛 修复：月份标签重叠（Dec+Jan 挤在一起显示乱码）→ 固定英文 locale + 最小3列间距
- 🆕 新增：今天的格子加橙色描边，视觉上一眼可见

### 2026-06-22
- 🆕 新增：点击热力图格子，复习日志自动滚动定位到对应日期的记录（居中显示）
- 🆕 新增：定位成功时，对应行即时出现 accentColor 高亮背景，1.8s 后缓慢淡出
- 🆕 新增：对应日期无记录时弹窗提示「XX月XX日 无复习记录」
- ♻️ 优化：回调链路 ActivityHeatmap → CoverageChartCard → AllLevelsContent → StatsView → ContentView → LogView，各层均有默认值不影响已有调用

### 2026-06-20
- 🐛 修复：等级标签颜色哈希碰撞问题，改为按等级在列表中的位置索引分配颜色，确保不同等级颜色不同（`levelColor(index:)`）
- 🆕 新增：课时置灰功能（`Lesson.isDisabled`）— hover 芯片右上角浮现红色禁止图标点击置灰，置灰后显示蓝色恢复图标可一键恢复；置灰课时从统计、覆盖率、推荐全部剔除
- 🆕 新增：添加/编辑记录时，默认选中当前所在等级 tab（通过 `ContentView.selectedLevelTab` 绑定传递）
- 🐛 修复：首次启动 StatsView 空白（`selectedLevelTab` 初始值改为 `"全部"`）

### 2026-06-18（补充）
- ⚡ 性能：复习日志仅渲染近一年记录（`session.date >= oneYearAgo`），统计仍全量计算，标题栏显示「N 条记录（近一年）」

### 2026-06-18
- 🆕 新增：自动备份功能（DataStore + DataSettingsView）
  - 备份地址可自定义，默认 `~/Documents/RepTrack Backups/`
  - 自动备份开关（默认开启）+ 每天具体时间点设置（DatePicker 紧凑模式）
  - 备份文件最多保留10个，超出自动删除最旧的
  - 备份列表弹窗：hover 显示「恢复」按钮 + Finder 跳转
  - 「从文件恢复」用 NSOpenPanel 直接定位到备份文件夹，恢复前弹确认框
  - 「立即备份」手动触发，显示成功/失败状态
- ♻️ 优化：数据文件界面全面重构，自定义 DSButton 组件（hover 加深+轻微放大，无选中蓝框）
- ♻️ 优化：SectionCard 标题加彩色图标
- ♻️ 优化：统计卡片视觉升级（渐变背景、装饰大字、图标、阴影、clipShape 防溢出）
- ♻️ 优化：调色板换用 Radix UI Step9 打散排列，相邻索引色相差约180°，10种颜色一眼可辨
- 🆕 新增：推荐复习卡（全部 tab / 单等级 tab）底部新增「最近复习」区块，按等级各取最近5条
- 🆕 新增：每日邮件新增「🕐 最近复习的5个内容」区块（按等级分组，置于最后）

### 2026-06-16
- 🆕 新增：全部 tab「推荐复习」卡底部新增「最近复习」区块，跨等级展示最近复习的5条（等级徽章 + 课程名 + 次数）
- 🆕 新增：单等级 tab「推荐复习」卡底部新增「最近复习」区块，展示该等级最近复习的5条
- 🆕 新增：每日邮件新增「🕐 最近复习的5个内容」卡片区块，含等级徽章、课程名、复习次数、相对时间（如"3天前"）

### 2026-06-03 (本次)
- 🆕 新增：综合实力雷达图，替换原各内容覆盖率图，满分100分（覆盖率50 + 频次50）
- 🆕 新增：`Level.tierStep` 字段（默认N=5），支持自定义每节课复习N次为一阶，向后兼容旧数据解码
- ♻️ 优化：覆盖率得分 = reviewed/total×50，消除课程体量差异
- ♻️ 优化：频次得分 = Σmin(N,每课次数)/total/N×50，防单课刷高分
- ♻️ 优化：各等级阶梯独立计算，以最薄弱课时为进度指针
- 🆕 新增：ⓘ 说明弹窗，含各等级当前阶段和N值自定义入口（点击N=5直接修改）
- ♻️ 优化：雷达图半径从0.33扩大到0.40，ZStack显式frame实现真正居中
- 🐛 修复：编译器类型检查超时（radarAngle、handleHover拆分子表达式）
- 🐛 修复：新增字段导致旧数据加载失败，改用 `decodeIfPresent` 兼容

### 2026-06-03 (邮件新增未复习区块)
- 🆕 新增：每日邮件新增「未复习课程」区块，按等级分组展示从未复习的课，最多显示8课+数量提示

### 2026-06-03 (统计卡片精简)
- ♻️ 优化：「今年复习」并入第二张可循环卡，循环顺序改为 今日→本周→本月→今年
- 🗑️ 删除：独立的「今年复习」固定卡，卡片数量从5张减为4张

### 2026-06-03 (工具栏整合)
- ♻️ 优化：导入课程文件夹按钮从顶部工具栏移至 tab 栏右侧，与刷新按钮并列
- 🗑️ 删除：ContentView 工具栏的 books.vertical 图标及 openImportPanel 方法

### 2026-06-03 (编辑交互优化)
- 🆕 新增：点击「当前记录/本次记录」中某条，上方日期、内容、芯片同步高亮回填
- 🐛 修复：选中记录后修改课时点击添加，改为替换而非追加
- 🆕 新增：`totalReviewCount` 方法，统计卡片改为显示累计复习次数（不去重）
- ♻️ 优化：未复习课程列表最多显示4条

### 2026-06-03 (单等级推荐卡优化)
- 🆕 新增：单等级推荐复习卡新增「未复习」区块，显示所有从未复习的课，橙色「未」徽章标注
- ♻️ 优化：抽取 `RecommendRow` 组件复用推荐行样式

### 2026-06-03 (统计卡片扩展)
- 🆕 新增：StatPeriod 加入 `.year`（今年）和 `.total`（累计）
- ♻️ 优化：`next` 循环限制在日/周/月，年和累计为固定卡不切换
- 🆕 新增：全部 tab 和各等级 tab 新增「今年复习」「累计复习」固定卡

### 2026-06-03 (SMTP 配置优化)
- ♻️ 优化：授权码输入框改为明文 TextField，支持复制粘贴
- 🆕 新增：重置按钮，清空所有 SMTP 配置及 Keychain 授权码
- ♻️ 优化：保存按钮改为 ✕ 关闭图标，关闭时自动保存

### 2026-06-07
- ♻️ 优化：统计区主 ScrollView 改为 showsIndicators: false，隐藏右侧多余滚动条


- 🐛 修复：统计卡片水印数字位置不一致 → 三种卡片（StatCard/PeriodStatCard/PeriodCoverageCard）统一为 ZStack + offset(x:8,y:8)
- 🐛 修复：SMTPSettingsView 加 .frame(height:360) 修复新版 macOS 弹窗不展开问题
- 🐛 修复：SMTP 界面重置/关闭/预设按钮加 .focusable(false) 消除焦点蓝框

### 2026-06-06
- 🐛 修复：「保存修改/保存记录」按钮将 padding/background/contentShape 移入 label 内部，整个圆角区域均可点击
- ♻️ 优化：「添加复习」按钮从工具栏移入「复习日志」标题栏，与「N 条记录」同行，⌘N 快捷键保留

### 2026-06-06 (本次)
- 🐛 修复：单等级 tab 的柱状图高度公式由 `paneHeight - 182` 改为 `paneHeight - 214`，与「全部」tab 对齐，使各 tab 底部均有一致的 16px 留白间距

### 2026-06-05 (本次)
- ♻️ 优化：「全部」tab 覆盖率图高度改为 `paneHeight - 214` 动态计算，与单等级 tab 逻辑一致，拉伸窗格时图表自适应填满
- 🐛 修复：拖动 VSplitView 分割线时图表即时跟手，去掉 `chartHeight` 变化时的 easeInOut 缓动
- 🐛 修复：VSplitView 分割位置在关闭后丢失 → 通过 `SplitViewAutosaver`（NSViewRepresentable）找到底层 NSSplitView 并设置 `autosaveName = "RepTrack.MainSplitView"`，利用 AppKit 原生 autosave 机制持久化
- ⚡ 性能：build.sh 加 `-jobs $(sysctl -n hw.logicalcpu)` 用满 12 核并行编译，加速构建

### 2026-06-04 (本次)
- 🐛 修复：删除等级后覆盖率图 / 推荐列表不刷新 → `.id(levelKey)` 绑定等级集合，等级增删时强制重建两个卡片
- 🐛 修复：LogView 在 `store.levels.count` 变化时递增 `listRefreshID`，删除等级后日志立即刷新
- ♻️ 优化：覆盖率图高度改为固定 200px，Swift Charts 自动压缩柱条，不再随等级数增长溢出
- ♻️ 优化：推荐卡 / 单等级推荐卡默认高度改为 270，防止 PreferenceKey 首帧未触发时撑高布局
- ♻️ 优化：VSplitView 恢复使用，`idealHeight: 440` 让分割线默认落在内容高度处（替代之前空白的 50/50 分割）
- 🆕 新增：每日邮件新增「今日已复习内容」区块（✅ 图标），与推荐复习和昨天复习并列展示
- ♻️ 优化：邮件等级颜色改用与 app Helpers.swift 完全相同的哈希算法 + 10 色调色板，颜色一致

### 2026-06-03
- 🆕 新增：每日复习邮件直发功能，不再依赖系统邮件客户端
  - `EmailService.swift`：通过 macOS 内置 curl 发送 SMTP/SMTPS，密码存 Keychain
  - `SMTPSettingsView.swift`：SMTP 配置界面，含 QQ/163/Gmail/Outlook 快捷预设，保存后自动关闭
  - 工具栏新增信封按钮，弹出 popover 填写收件人，显示发送中/成功/失败状态
- ♻️ 优化：邮件内容改为 HTML 富文本，橙色渐变 header、彩色等级徽章、复习次数色块（未复习橙色、1-2次蓝色、3次+绿色）
- ♻️ 优化：`recommendScore` / `topRecommendations` 移至 `Helpers.swift` 供 StatsView 和邮件功能共用
- ♻️ 优化：AddSessionView 「等级」Picker 标签改为「内容」
- ♻️ 优化：StatsView「各等级覆盖率」改为「各内容覆盖率」，图表 Y 轴系列名同步更新

### 2026-06-05
- 🐛 修复：未绑定文件夹的 tab（如手动添加的「听力」）现在也显示按钮，图标为 `folder.badge.plus`，点击弹选择器绑定文件夹；已绑定的 tab 保持原刷新逻辑

### 2026-06-16
- 🆕 新增：活跃记录热力图左侧加入星期标签（Mon / Wed / Fri）
- 🆕 新增：热力图底部加入颜色图例（Less ●●●●● More）
- 🆕 新增：综合实力卡片内置「活跃记录」热力图视图——右上角图标切换雷达图 / 热力图，默认显示热力图
- 🆕 新增：热力图展示最近 26 周每日复习活动，颜色深浅按当日课时数变化，鼠标悬停显示日期浮窗
- ♻️ 优化：切换到热力图时卡片标题自动改为「活跃记录」，切回雷达图恢复「综合实力」
- ♻️ 优化：热力图格子自适应卡片容器尺寸，启动时与切换后效果一致，无空白区域

### 2026-06-02
- 🐛 修复：删除等级 tab 不再级联删除历史复习记录，数据完整保留
- ♻️ 优化：LogView `grouped` 过滤只显示有对应 tab 的 session/item，重新导入后自动恢复显示
- ⚡ 性能：`save()` 改为后台线程写磁盘 + 300ms 防抖，UI 操作不再卡顿
- ⚡ 性能：`levelStats` 改为单次 O(sessions) 扫描建索引，性能从 O(课程×sessions) 降至 O(sessions)
- 🐛 修复：StatsView 增加 `maxHeight: 520`，新增等级时上方统计区不再自动撑高遮挡日志列表
- ♻️ 优化：LogView 最小高度从 320 降至 200，窗口空间分配更合理
- ♻️ 优化：`levelColor` 改为哈希动态分配颜色，10色调色板覆盖所有等级，饱和度 0.50~0.65、亮度 0.75~0.88，中性不刺眼，不再有灰色兜底

### 2026-06-01
- 🐛 修复：LogView 新增 `listRefreshID`，监听 `NSApplication.didBecomeActiveNotification`，app 从挂起恢复后强制 `List` 重绘，解决表格不自动显示、只有鼠标 hover 才出来的问题

### 2026-05-31
- ♻️ 优化：工具栏「导入课程目录」图标改为 `books.vertical`，「添加复习」改为 `plus.circle.fill`，两者视觉差异明显

### 2026-05-29
- 🆕 新增：LogView 每条记录加编辑按钮（`square.and.pencil` 图标），点击直接打开编辑弹窗
- ♻️ 优化：编辑界面「取消」按钮去掉焦点蓝框，加 hover 交互，整个背景区域可点击（`.contentShape`）
- ♻️ 优化：编辑界面「保存修改/保存记录」按钮改为自定义样式，加 hover 放大 + 颜色变化
- ♻️ 优化：EditItemRow / PendingEntryRow 删除按钮统一抽为 `RemoveButton` 组件，hover 时背景变深灰
