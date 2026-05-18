import SwiftUI
import AppKit

struct DataSettingsView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let isOnboarding: Bool

    @State private var importError: String?
    @State private var showImportConfirm = false
    @State private var pendingImportURL: URL?
    @State private var exportError: String?
    @State private var didImport = false

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

                    // ── Current location ─────────────────────────
                    SectionCard(title: "当前存储位置") {
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
                        }
                    }

                    // ── Change location ───────────────────────────
                    SectionCard(title: isOnboarding ? "选择存储位置" : "更改存储位置") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("当前数据会复制到新位置，旧文件不会自动删除。")
                                .font(.caption).foregroundStyle(.secondary)

                            HStack(spacing: 10) {
                                if isOnboarding {
                                    Button("使用默认位置") {
                                        store.completeSetup()
                                        dismiss()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.regular)
                                }

                                if isOnboarding {
                                    Button("自定义位置…") { chooseStorageFolder() }
                                        .buttonStyle(.bordered).controlSize(.regular)
                                } else {
                                    Button("选择文件夹…") { chooseStorageFolder() }
                                        .buttonStyle(.borderedProminent).controlSize(.regular)
                                }
                            }
                        }
                    }

                    // ── Import ────────────────────────────────────
                    SectionCard(title: "从文件读取") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("选择一个 RepTrack 数据文件（.json），将替换当前所有数据。")
                                .font(.caption).foregroundStyle(.secondary)

                            if let err = importError {
                                Text(err).font(.caption).foregroundStyle(.red)
                            }
                            if didImport {
                                Label("已成功读取", systemImage: "checkmark.circle.fill")
                                    .font(.caption).foregroundStyle(.green)
                            }

                            Button("从文件打开…") { pickImportFile() }
                                .buttonStyle(.bordered)
                                .controlSize(.regular)
                        }
                    }

                    // ── Export ────────────────────────────────────
                    SectionCard(title: "导出备份") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("将当前数据导出为 JSON 文件，可用于备份或在其他设备上导入。")
                                .font(.caption).foregroundStyle(.secondary)

                            if let err = exportError {
                                Text(err).font(.caption).foregroundStyle(.red)
                            }

                            Button("导出当前数据…") { exportData() }
                                .buttonStyle(.bordered)
                                .controlSize(.regular)
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
        .frame(width: 480)
        .confirmationDialog(
            "替换当前数据？",
            isPresented: $showImportConfirm,
            titleVisibility: .visible
        ) {
            Button("替换", role: .destructive) {
                if let url = pendingImportURL {
                    importError = nil
                    didImport = false
                    if store.importFromFile(url) {
                        didImport = true
                        if isOnboarding {
                            store.completeSetup()
                            dismiss()
                        }
                    } else {
                        importError = "文件格式无效或无法读取"
                    }
                }
                pendingImportURL = nil
            }
        } message: {
            Text("此操作将用所选文件的内容替换当前全部复习记录和课程数据，无法撤销。")
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

    private func pickImportFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.message = "选择 RepTrack 数据文件（data.json 或 RepTrackData.json）"
        panel.prompt = "打开"
        if panel.runModal() == .OK, let url = panel.url {
            pendingImportURL = url
            showImportConfirm = true
        }
    }

    private func exportData() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "RepTrackData.json"
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
