# 数据存储迁移模块

macOS SwiftUI app 通用的「可迁移存储位置 + 导入/导出备份」方案，适合单文件 JSON 持久化的场景。

---

## 核心机制

用户选择一个文件夹后，app 把数据文件写到该文件夹，并把完整路径存入 `UserDefaults`。下次启动时优先读取该路径，若路径失效则回退到默认位置（`~/Library/Application Support/<AppName>/data.json`）。

---

## 1. 替换以下占位符

| 占位符 | 替换为 |
|--------|--------|
| `<AppName>` | 你的 app 名称，如 `MyApp` |
| `<AppName>.dataFilePath` | UserDefaults key，建议加 bundle 前缀 |
| `<AppName>.hasCompletedSetup` | 首次启动 flag 的 UserDefaults key |
| `<DataFileName>.json` | 数据文件名，如 `MyAppData.json` |
| `Saved` | 你的顶层 Codable 数据结构 |

---

## 2. DataStore 中需要的代码

```swift
// MARK: - Storage location

private static let dataPathKey   = "<AppName>.dataFilePath"
private static let hasSetupKey   = "<AppName>.hasCompletedSetup"

/// 默认位置：~/Library/Application Support/<AppName>/data.json
static var defaultDataURL: URL {
    let dir = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("<AppName>", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("data.json")
}

/// 运行时读取当前路径；若 UserDefaults 中的路径所在文件夹不存在则回退默认。
var dataURL: URL {
    if let path = UserDefaults.standard.string(forKey: Self.dataPathKey) {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path) {
            return url
        }
    }
    return Self.defaultDataURL
}

/// 首次启动判断
var isFirstLaunch: Bool {
    !UserDefaults.standard.bool(forKey: Self.hasSetupKey)
}

/// 标记已完成首次设置
func completeSetup() {
    UserDefaults.standard.set(true, forKey: Self.hasSetupKey)
}

/// 将数据文件复制到新文件夹，更新 UserDefaults，重新写盘。
/// 旧文件不删除，由用户手动清理。
func setStorageFolder(_ folderURL: URL) {
    let newURL = folderURL.appendingPathComponent("<DataFileName>.json")
    let old = dataURL
    if FileManager.default.fileExists(atPath: old.path) {
        try? FileManager.default.copyItem(at: old, to: newURL)
    }
    UserDefaults.standard.set(newURL.path, forKey: Self.dataPathKey)
    save()   // 写到新路径
}

/// 从外部 JSON 文件还原数据（替换当前全部内容）。
@discardableResult
func importFromFile(_ url: URL) -> Bool {
    guard let data  = try? Data(contentsOf: url),
          let saved = try? JSONDecoder().decode(Saved.self, from: data)
    else { return false }
    // 在这里赋值给你自己的模型属性，例如：
    // self.items = saved.items
    save()
    return true
}

/// 将当前数据导出到用户指定的 JSON 文件。
func exportToFile(_ url: URL) throws {
    let data = try JSONEncoder().encode(Saved(/* 你的属性 */))
    try data.write(to: url, options: .atomic)
}

// MARK: - Persistence（基础读写，如已有可复用）

private func load() {
    guard let data  = try? Data(contentsOf: dataURL),
          let saved = try? JSONDecoder().decode(Saved.self, from: data)
    else { return }
    // 赋值给自己的属性
}

private func save() {
    try? JSONEncoder().encode(Saved(/* 你的属性 */)).write(to: dataURL, options: .atomic)
}
```

---

## 3. DataSettingsView（UI 层，完整可复用）

```swift
import SwiftUI
import AppKit

struct DataSettingsView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let isOnboarding: Bool   // true = 首次启动向导；false = 设置页

    @State private var importError: String?
    @State private var showImportConfirm = false
    @State private var pendingImportURL: URL?
    @State private var exportError: String?
    @State private var didImport = false

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ───────────────────────────────────────────
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isOnboarding ? "欢迎使用" : "数据文件")
                        .font(.title2).fontWeight(.semibold)
                    if isOnboarding {
                        Text("选择数据存储位置，之后可随时在设置中更改。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if !isOnboarding {
                    Button("完成") { dismiss() }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // 当前存储位置
                    SectionCard(title: "当前存储位置") {
                        HStack(spacing: 10) {
                            Image(systemName: "doc.fill")
                                .font(.title2).foregroundStyle(.blue).frame(width: 32)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(store.dataURL.lastPathComponent)
                                    .font(.callout).fontWeight(.medium)
                                Text(store.dataURL.deletingLastPathComponent().path
                                    .replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                    .font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            Button("在 Finder 中显示") {
                                NSWorkspace.shared.selectFile(store.dataURL.path,
                                    inFileViewerRootedAtPath: "")
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                        }
                    }

                    // 更改存储位置
                    SectionCard(title: isOnboarding ? "选择存储位置" : "更改存储位置") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("当前数据会复制到新位置，旧文件不会自动删除。")
                                .font(.caption).foregroundStyle(.secondary)
                            HStack(spacing: 10) {
                                if isOnboarding {
                                    Button("使用默认位置") {
                                        store.completeSetup(); dismiss()
                                    }
                                    .buttonStyle(.borderedProminent).controlSize(.regular)
                                    Button("自定义位置…") { chooseStorageFolder() }
                                        .buttonStyle(.bordered).controlSize(.regular)
                                } else {
                                    Button("选择文件夹…") { chooseStorageFolder() }
                                        .buttonStyle(.borderedProminent).controlSize(.regular)
                                }
                            }
                        }
                    }

                    // 从文件导入
                    SectionCard(title: "从文件读取") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("选择一个备份 .json 文件，将替换当前所有数据。")
                                .font(.caption).foregroundStyle(.secondary)
                            if let err = importError {
                                Text(err).font(.caption).foregroundStyle(.red)
                            }
                            if didImport {
                                Label("已成功读取", systemImage: "checkmark.circle.fill")
                                    .font(.caption).foregroundStyle(.green)
                            }
                            Button("从文件打开…") { pickImportFile() }
                                .buttonStyle(.bordered).controlSize(.regular)
                        }
                    }

                    // 导出备份
                    SectionCard(title: "导出备份") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("将当前数据导出为 JSON，可用于备份或跨设备迁移。")
                                .font(.caption).foregroundStyle(.secondary)
                            if let err = exportError {
                                Text(err).font(.caption).foregroundStyle(.red)
                            }
                            Button("导出当前数据…") { exportData() }
                                .buttonStyle(.bordered).controlSize(.regular)
                        }
                    }
                }
                .padding(24)
            }

            if isOnboarding {
                Divider()
                HStack {
                    Spacer()
                    Button("稍后再说") { store.completeSetup(); dismiss() }
                        .buttonStyle(.plain).foregroundStyle(.secondary).controlSize(.small)
                }
                .padding(.horizontal, 24).padding(.vertical, 12)
            }
        }
        .frame(width: 480)
        .confirmationDialog("替换当前数据？", isPresented: $showImportConfirm,
                            titleVisibility: .visible) {
            Button("替换", role: .destructive) {
                if let url = pendingImportURL {
                    importError = nil; didImport = false
                    if store.importFromFile(url) {
                        didImport = true
                        if isOnboarding { store.completeSetup(); dismiss() }
                    } else {
                        importError = "文件格式无效或无法读取"
                    }
                }
                pendingImportURL = nil
            }
        } message: {
            Text("此操作将替换当前全部数据，无法撤销。")
        }
    }

    // MARK: - Actions

    private func chooseStorageFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "选择数据文件夹（如 iCloud Drive、Dropbox 等）"
        panel.prompt = "选择"
        if panel.runModal() == .OK, let url = panel.url {
            store.setStorageFolder(url)
            if isOnboarding { store.completeSetup(); dismiss() }
        }
    }

    private func pickImportFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.message = "选择数据备份文件（.json）"
        panel.prompt = "打开"
        if panel.runModal() == .OK, let url = panel.url {
            pendingImportURL = url
            showImportConfirm = true
        }
    }

    private func exportData() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "<DataFileName>.json"
        panel.message = "选择导出位置"
        panel.prompt = "导出"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try store.exportToFile(url)
                exportError = nil
            } catch {
                exportError = "导出失败：\(error.localizedDescription)"
            }
        }
    }
}

// MARK: - SectionCard（辅助组件，直接复制）

private struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline).fontWeight(.semibold).foregroundStyle(.secondary)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
}
```

---

## 4. 接入点（App 入口）

```swift
// 在 App 根 Scene 中：
@State private var store = DataStore()

WindowGroup {
    ContentView()
        .environment(store)
        .sheet(isPresented: $store.isFirstLaunch) {    // 或用 onAppear 判断
            DataSettingsView(isOnboarding: true)
        }
}
```

工具栏刷新按钮触发：
```swift
Button { showDataSettings = true } label: {
    Label("数据文件", systemImage: "externaldrive")
}
.sheet(isPresented: $showDataSettings) {
    DataSettingsView(isOnboarding: false)
}
```

---

## 5. 关键细节

| 事项 | 说明 |
|------|------|
| 回退逻辑 | `dataURL` 验证文件夹是否存在再返回路径，防止外接硬盘拔出后崩溃 |
| 旧文件不删 | `setStorageFolder` 只 copy 不删，防止用户误操作导致数据丢失 |
| 原子写入 | `save()` 使用 `.atomic` 选项，防止写到一半 app 崩溃导致文件损坏 |
| 首次启动 | `isFirstLaunch` 用独立 key 记录，与数据路径解耦；`completeSetup()` 在用户做出任何选择后立即调用 |
| 导入确认 | 导入前强制 `confirmationDialog`，避免误操作覆盖数据 |
