import SwiftUI
import AppKit

struct DataSettingsView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let isOnboarding: Bool

    @State private var backupEnabled: Bool = true
    @State private var backupTime: Date = {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = 3; c.minute = 0
        return Calendar.current.date(from: c) ?? Date()
    }()
    @State private var backupFolderURL: URL = DataStore.defaultBackupURL
    @State private var backupResult: BackupResult? = nil
    @State private var showBackupList = false
    @State private var restoreConfirmURL: URL? = nil
    @State private var showRestoreFilePicker = false

    enum BackupResult { case success, failure, restoreSuccess, restoreFailure }

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
                    DSButton("完成", style: .ghost) { dismiss() }
                }
            }
            .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // ── Storage location ──────────────────────────
                    SectionCard(title: isOnboarding ? "选择存储位置" : "存储位置",
                                icon: "externaldrive.fill", iconColor: .blue) {
                        if isOnboarding {
                            HStack(spacing: 10) {
                                DSButton("使用默认位置", style: .primary) {
                                    store.completeSetup(); dismiss()
                                }
                                DSButton("自定义位置…", style: .secondary) { chooseStorageFolder() }
                            }
                        } else {
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
                                DSButton("Finder 显示", style: .secondary) {
                                    NSWorkspace.shared.selectFile(store.dataURL.path,
                                                                  inFileViewerRootedAtPath: "")
                                }
                                DSButton("更改位置…", style: .secondary) { chooseStorageFolder() }
                            }
                        }
                    }

                    // ── Auto backup ───────────────────────────────
                    if !isOnboarding {
                        SectionCard(title: "自动备份",
                                    icon: "clock.arrow.2.circlepath", iconColor: .green) {
                            VStack(alignment: .leading, spacing: 14) {

                                // 开关行
                                HStack {
                                    Text("自动备份")
                                        .font(.callout)
                                    Spacer()
                                    Toggle("", isOn: $backupEnabled)
                                        .toggleStyle(.switch)
                                        .labelsHidden()
                                        .onChange(of: backupEnabled) { _, v in
                                            store.backupEnabled = v
                                            store.scheduleBackupTimer()
                                        }
                                }

                                if backupEnabled {
                                    Divider()

                                    // 备份时间 — DatePicker 紧凑模式
                                    HStack {
                                        Text("每天备份时间")
                                            .font(.callout).foregroundStyle(.secondary)
                                        Spacer()
                                        DatePicker("", selection: $backupTime,
                                                   displayedComponents: .hourAndMinute)
                                            .labelsHidden()
                                            .datePickerStyle(.compact)
                                            .onChange(of: backupTime) { _, t in
                                                let c = Calendar.current.dateComponents([.hour, .minute], from: t)
                                                store.backupHour   = c.hour   ?? 3
                                                store.backupMinute = c.minute ?? 0
                                                store.scheduleBackupTimer()
                                            }
                                    }

                                    Divider()
                                }

                                // 备份地址
                                HStack(spacing: 10) {
                                    Image(systemName: "folder.fill").foregroundStyle(.orange)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(backupFolderURL.lastPathComponent)
                                            .font(.callout).fontWeight(.medium)
                                        Text(backupFolderURL.path
                                            .replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                            .font(.caption).foregroundStyle(.secondary)
                                            .lineLimit(1).truncationMode(.middle)
                                    }
                                    Spacer()
                                    DSButton("Finder 显示", style: .secondary) {
                                        NSWorkspace.shared.open(backupFolderURL)
                                    }
                                    DSButton("更改…", style: .secondary) { chooseBackupFolder() }
                                }

                                Divider()

                                // 操作行
                                HStack(spacing: 10) {
                                    let backups = store.listBackups()
                                    DSButton("已备份 \(backups.count)/10", icon: "list.bullet.rectangle",
                                             style: .secondary) {
                                        showBackupList.toggle()
                                    }
                                    .popover(isPresented: $showBackupList, arrowEdge: .bottom) {
                                        BackupListPopover(backups: backups) { url in
                                            showBackupList = false
                                            restoreConfirmURL = url
                                        }
                                    }

                                    DSButton("从文件恢复", icon: "arrow.counterclockwise",
                                             style: .secondary) {
                                        showRestoreFilePicker = true
                                    }

                                    Spacer()

                                    if let result = backupResult {
                                        let isOk = result == .success || result == .restoreSuccess
                                        Label(result == .success ? "备份成功"
                                              : result == .restoreSuccess ? "恢复成功" : "操作失败",
                                              systemImage: isOk ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(isOk ? Color.green : Color.red)
                                            .transition(.opacity)
                                    }

                                    DSButton("立即备份", style: .primary) {
                                        let ok = store.performBackup()
                                        withAnimation { backupResult = ok ? .success : .failure }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                            withAnimation { backupResult = nil }
                                        }
                                    }
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
                    DSButton("稍后再说", style: .ghost) {
                        store.completeSetup(); dismiss()
                    }
                }
                .padding(.horizontal, 24).padding(.vertical, 12)
            }
        }
        .frame(width: 500)
        // 从文件选择器恢复
        .fileImporter(isPresented: $showRestoreFilePicker,
                      allowedContentTypes: [.json],
                      allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            restoreConfirmURL = url
        }
        // 恢复确认弹窗
        .confirmationDialog(
            "确认恢复备份？",
            isPresented: Binding(get: { restoreConfirmURL != nil },
                                 set: { if !$0 { restoreConfirmURL = nil } }),
            titleVisibility: .visible
        ) {
            Button("恢复", role: .destructive) {
                guard let url = restoreConfirmURL else { return }
                let ok = store.importFromFile(url)
                withAnimation { backupResult = ok ? .restoreSuccess : .restoreFailure }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation { backupResult = nil }
                }
                restoreConfirmURL = nil
            }
            Button("取消", role: .cancel) { restoreConfirmURL = nil }
        } message: {
            if let url = restoreConfirmURL {
                Text("将用「\(url.lastPathComponent)」覆盖当前所有数据，此操作不可撤销。")
            }
        }
        .onAppear {
            backupEnabled   = store.backupEnabled
            backupFolderURL = store.backupFolderURL
            var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            c.hour = store.backupHour; c.minute = store.backupMinute
            backupTime = Calendar.current.date(from: c) ?? backupTime
        }
    }

    // MARK: - Actions

    private func chooseStorageFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "选择数据文件的存储文件夹（如 iCloud Drive、Documents 等）"
        panel.prompt = "选择"
        if panel.runModal() == .OK, let url = panel.url {
            store.setStorageFolder(url)
            if isOnboarding { store.completeSetup(); dismiss() }
        }
    }

    private func chooseBackupFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "选择备份文件的保存位置"
        panel.prompt = "选择"
        if panel.runModal() == .OK, let url = panel.url {
            store.backupFolderURL = url
            backupFolderURL = url
        }
    }
}

// MARK: - Custom Button with hover effect

private struct DSButton: View {
    enum Style { case primary, secondary, ghost }

    let title: String
    var icon: String? = nil
    let style: Style
    let action: () -> Void
    @State private var hovered = false

    init(_ title: String, icon: String? = nil, style: Style = .secondary, action: @escaping () -> Void) {
        self.title = title; self.icon = icon; self.style = style; self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).font(.system(size: 11)) }
                Text(title).font(.system(size: 12))
            }
            .padding(.horizontal, style == .ghost ? 4 : 10)
            .padding(.vertical, 5)
            .background(background, in: RoundedRectangle(cornerRadius: 7))
            .foregroundStyle(foreground)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(border, lineWidth: style == .primary ? 0 : 1)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(hovered ? 1.03 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: hovered)
        .onHover { hovered = $0 }
    }

    private var background: AnyShapeStyle {
        switch style {
        case .primary:   return AnyShapeStyle(hovered ? Color.accentColor.opacity(0.85) : Color.accentColor)
        case .secondary: return AnyShapeStyle(hovered ? Color.secondary.opacity(0.16) : Color.secondary.opacity(0.08))
        case .ghost:     return AnyShapeStyle(hovered ? Color.secondary.opacity(0.10) : Color.clear)
        }
    }

    private var foreground: AnyShapeStyle {
        switch style {
        case .primary: return AnyShapeStyle(Color.white)
        case .secondary, .ghost: return AnyShapeStyle(hovered ? Color.primary : Color.primary.opacity(0.75))
        }
    }

    private var border: AnyShapeStyle {
        switch style {
        case .primary: return AnyShapeStyle(Color.clear)
        case .secondary: return AnyShapeStyle(Color.secondary.opacity(hovered ? 0.35 : 0.22))
        case .ghost: return AnyShapeStyle(Color.clear)
        }
    }
}

// MARK: - Section card

private struct SectionCard<Content: View>: View {
    let title: String
    var icon: String? = nil
    var iconColor: Color = .secondary
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(iconColor)
                }
                Text(title)
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Backup list popover

private struct BackupListPopover: View {
    let backups: [URL]
    var onRestore: (URL) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("备份文件（最多保留 10 个）")
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
                            BackupRow(url: url, onRestore: onRestore)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .frame(width: 340)
    }
}

private struct BackupRow: View {
    let url: URL
    var onRestore: (URL) -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.fill")
                .foregroundStyle(.blue.opacity(0.7)).font(.caption)
            Text(url.lastPathComponent
                .replacingOccurrences(of: "RepTrack-backup-", with: "")
                .replacingOccurrences(of: ".json", with: ""))
                .font(.caption).lineLimit(1)
            Spacer()
            // Finder 显示
            Button {
                NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(hovered ? 1 : 0)
            // 恢复按钮
            Button {
                onRestore(url)
            } label: {
                Text("恢复")
                    .font(.system(size: 11))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.accentColor.opacity(hovered ? 1 : 0.8),
                                in: RoundedRectangle(cornerRadius: 5))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .opacity(hovered ? 1 : 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(hovered ? Color.secondary.opacity(0.07) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .animation(.easeInOut(duration: 0.1), value: hovered)
    }
}
