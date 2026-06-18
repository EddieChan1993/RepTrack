import SwiftUI
import AppKit

struct DataSettingsView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let isOnboarding: Bool

    // 备份设置本地状态（绑定 store 属性）
    @State private var backupEnabled: Bool = true
    @State private var backupHour: Int = 3
    @State private var backupMinute: Int = 0
    @State private var backupFolderURL: URL = DataStore.defaultBackupURL
    @State private var backupResult: BackupResult? = nil
    @State private var showBackupList = false

    enum BackupResult { case success, failure }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isOnboarding ? "欢迎使用 RepTrack" : "数据文件")
                        .font(.title2).fontWeight(.semibold)
                    if isOnboarding {
                        Text("选择复习数据的存储位置，之后可以在设置中随时更改。")
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

                    // ── Storage location ──────────────────────────
                    SectionCard(title: isOnboarding ? "选择存储位置" : "存储位置") {
                        if isOnboarding {
                            HStack(spacing: 10) {
                                Button("使用默认位置") {
                                    store.completeSetup()
                                    dismiss()
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.regular)

                                Button("自定义位置…") { chooseStorageFolder() }
                                    .buttonStyle(.bordered).controlSize(.regular)
                            }
                        } else {
                            HStack(spacing: 10) {
                                Image(systemName: "doc.fill")
                                    .font(.title2)
                                    .foregroundStyle(.blue)
                                    .frame(width: 32)

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
                                    NSWorkspace.shared.selectFile(
                                        store.dataURL.path,
                                        inFileViewerRootedAtPath: ""
                                    )
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button("更改位置…") { chooseStorageFolder() }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                        }
                    }

                    // ── Auto backup ───────────────────────────────
                    if !isOnboarding {
                        SectionCard(title: "自动备份") {
                            VStack(alignment: .leading, spacing: 12) {

                                // 开关
                                Toggle(isOn: $backupEnabled) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "clock.arrow.2.circlepath")
                                            .foregroundStyle(.green)
                                        Text("开启自动备份")
                                            .font(.callout)
                                    }
                                }
                                .toggleStyle(.switch)
                                .onChange(of: backupEnabled) { _, v in
                                    store.backupEnabled = v
                                    store.scheduleBackupTimer()
                                }

                                if backupEnabled {
                                    Divider()

                                    // 备份时间
                                    HStack(spacing: 8) {
                                        Text("备份时间")
                                            .font(.callout).foregroundStyle(.secondary)
                                            .frame(width: 60, alignment: .leading)
                                        Picker("", selection: $backupHour) {
                                            ForEach(0..<24, id: \.self) { h in
                                                Text(String(format: "%02d", h)).tag(h)
                                            }
                                        }
                                        .labelsHidden()
                                        .frame(width: 64)
                                        .onChange(of: backupHour) { _, v in
                                            store.backupHour = v
                                            store.scheduleBackupTimer()
                                        }

                                        Text("时")
                                            .font(.callout).foregroundStyle(.secondary)

                                        Picker("", selection: $backupMinute) {
                                            ForEach([0, 15, 30, 45], id: \.self) { m in
                                                Text(String(format: "%02d", m)).tag(m)
                                            }
                                        }
                                        .labelsHidden()
                                        .frame(width: 64)
                                        .onChange(of: backupMinute) { _, v in
                                            store.backupMinute = v
                                            store.scheduleBackupTimer()
                                        }

                                        Text("分")
                                            .font(.callout).foregroundStyle(.secondary)
                                    }

                                    Divider()
                                }

                                // 备份地址
                                HStack(spacing: 8) {
                                    Image(systemName: "folder.fill")
                                        .foregroundStyle(.orange)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(backupFolderURL.lastPathComponent)
                                            .font(.callout).fontWeight(.medium)
                                        Text(backupFolderURL.path
                                            .replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                            .font(.caption).foregroundStyle(.secondary)
                                            .lineLimit(1).truncationMode(.middle)
                                    }
                                    Spacer()
                                    Button("更改…") { chooseBackupFolder() }
                                        .buttonStyle(.bordered).controlSize(.small)
                                    Button("在 Finder 中显示") {
                                        NSWorkspace.shared.open(backupFolderURL)
                                    }
                                    .buttonStyle(.bordered).controlSize(.small)
                                }

                                Divider()

                                // 备份操作行
                                HStack(spacing: 10) {
                                    // 备份列表
                                    let backups = store.listBackups()
                                    Button {
                                        showBackupList.toggle()
                                    } label: {
                                        Label("已备份 \(backups.count)/10 个", systemImage: "list.bullet.rectangle")
                                    }
                                    .buttonStyle(.bordered).controlSize(.small)
                                    .popover(isPresented: $showBackupList, arrowEdge: .bottom) {
                                        BackupListPopover(backups: backups)
                                    }

                                    Spacer()

                                    // 立即备份
                                    if let result = backupResult {
                                        Label(result == .success ? "备份成功" : "备份失败",
                                              systemImage: result == .success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(result == .success ? Color.green : Color.red)
                                    }
                                    Button("立即备份") {
                                        let ok = store.performBackup()
                                        backupResult = ok ? .success : .failure
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { backupResult = nil }
                                    }
                                    .buttonStyle(.borderedProminent).controlSize(.small)
                                }
                            }
                        }
                    }

                }
                .padding(24)
            }

            if isOnboarding {
                Divider()
                HStack {
                    Spacer()
                    Button("稍后再说") {
                        store.completeSetup()
                        dismiss()
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .controlSize(.small)
                }
                .padding(.horizontal, 24).padding(.vertical, 12)
            }
        }
        .frame(width: 500)
        .onAppear {
            backupEnabled    = store.backupEnabled
            backupHour       = store.backupHour
            backupMinute     = store.backupMinute
            backupFolderURL  = store.backupFolderURL
        }
    }

    // MARK: - Actions

    private func chooseStorageFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "选择数据文件的存储文件夹（如 iCloud Drive、Documents 等）"
        panel.prompt = "选择"
        if panel.runModal() == .OK, let url = panel.url {
            store.setStorageFolder(url)
            if isOnboarding {
                store.completeSetup()
                dismiss()
            }
        }
    }

    private func chooseBackupFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "选择备份文件的保存位置"
        panel.prompt = "选择"
        if panel.runModal() == .OK, let url = panel.url {
            store.backupFolderURL = url
            backupFolderURL = url
        }
    }
}

// MARK: - Backup list popover

private struct BackupListPopover: View {
    let backups: [URL]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("备份文件（最多保留10个）")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
            Divider()
            if backups.isEmpty {
                Text("暂无备份")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(14)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(backups, id: \.path) { url in
                            HStack(spacing: 8) {
                                Image(systemName: "doc.zipper")
                                    .foregroundStyle(.secondary).font(.caption)
                                Text(url.lastPathComponent
                                    .replacingOccurrences(of: "RepTrack-backup-", with: "")
                                    .replacingOccurrences(of: ".json", with: ""))
                                    .font(.caption).lineLimit(1)
                                Spacer()
                                Button {
                                    NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
                                } label: {
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
        }
        .frame(width: 320)
    }
}

// MARK: - Section card

private struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(.secondary)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
}
