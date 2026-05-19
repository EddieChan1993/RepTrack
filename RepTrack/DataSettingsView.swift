import SwiftUI
import AppKit

struct DataSettingsView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let isOnboarding: Bool

    @State private var exportError: String?

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
