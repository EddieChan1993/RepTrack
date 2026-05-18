import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(DataStore.self) private var store
    @State private var showAdd = false
    @State private var showDataSettings = false
    @State private var showOnboarding = false

    var body: some View {
        VSplitView {
            StatsView()
                .frame(minHeight: 260)
            LogView()
                .frame(minHeight: 180)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { openImportPanel() } label: {
                    Label("导入课程目录", systemImage: "folder.badge.plus")
                }
                .help("选择课程文件夹，自动读取等级和课程列表")

                Button { showAdd = true } label: {
                    Label("添加复习", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                .help("记录今天的复习 (⌘N)")

                Button { showDataSettings = true } label: {
                    Label("数据文件", systemImage: "externaldrive")
                }
                .help("管理数据存储位置、导入或导出备份")
            }
        }
        .sheet(isPresented: $showAdd) { AddSessionView() }
        .sheet(isPresented: $showDataSettings) {
            DataSettingsView(isOnboarding: false)
        }
        .sheet(isPresented: $showOnboarding) {
            DataSettingsView(isOnboarding: true)
        }
        .onAppear {
            if store.isFirstLaunch { showOnboarding = true }
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    private func openImportPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.message = "选择一个或多个课程等级文件夹（如 S1-EK、S2-IC、S3-IK）"
        panel.prompt = "导入"
        if panel.runModal() == .OK {
            store.importLevelFolders(panel.urls)
        }
    }
}
