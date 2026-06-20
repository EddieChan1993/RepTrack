import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(DataStore.self) private var store
    @State private var showDataSettings = false
    @State private var showOnboarding = false
    @State private var showEmailPopover = false
    @State private var emailInput = ""

    @State private var selectedLevelTab = "全部"

    var body: some View {
        VSplitView {
            StatsView(selectedTab: $selectedLevelTab)
                .frame(minHeight: 440, maxHeight: 600)
                .background(SplitViewAutosaver())
            LogView(defaultLevelId: selectedLevelTab == "全部" ? "" : selectedLevelTab)
                .frame(minHeight: 200)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    emailInput = store.recipientEmail
                    showEmailPopover = true
                } label: {
                    Label("发送提醒邮件", systemImage: "envelope")
                }
                .help("将今日推荐和昨天复习内容发送到邮箱")
                .popover(isPresented: $showEmailPopover, arrowEdge: .bottom) {
                    EmailPopover(emailInput: $emailInput, isPresented: $showEmailPopover)
                        .environment(store)
                }

                Button { showDataSettings = true } label: {
                    Label("数据文件", systemImage: "externaldrive")
                }
                .help("管理数据存储位置、导入或导出备份")
            }
        }
        .sheet(isPresented: $showDataSettings) {
            DataSettingsView(isOnboarding: false)
        }
        .sheet(isPresented: $showOnboarding) {
            DataSettingsView(isOnboarding: true)
        }
        .onAppear {
            if store.isFirstLaunch { showOnboarding = true }
        }
        .frame(minWidth: 720, minHeight: 740)
    }


}

// MARK: - VSplitView autosave helper
// 找到底层 NSSplitView 并设置 autosaveName，让 AppKit 自动保存/恢复分割位置

private struct SplitViewAutosaver: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            var v: NSView? = nsView.superview
            while let current = v {
                if let split = current as? NSSplitView {
                    if split.autosaveName == nil || split.autosaveName == "" {
                        split.autosaveName = "RepTrack.MainSplitView"
                    }
                    break
                }
                v = current.superview
            }
        }
    }
}

// MARK: - Email popover

private struct EmailPopover: View {
    @Environment(DataStore.self) private var store
    @Binding var emailInput: String
    @Binding var isPresented: Bool

    @State private var sendState: SendState = .idle
    @State private var showSMTPSettings = false
    @FocusState private var focused: Bool

    enum SendState: Equatable {
        case idle, sending, success, failure(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "envelope.fill").foregroundStyle(Color.accentColor)
                Text("发送每日复习提醒").font(.headline)
            }

            if !store.smtpConfigured {
                // SMTP 未配置
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("尚未配置邮件发送服务").font(.caption).foregroundStyle(.secondary)
                }
                Button("前往配置 SMTP →") { showSMTPSettings = true }
                    .buttonStyle(.borderedProminent)
            } else {
                Text("将「今日推荐」和「昨天复习」直接发送到邮箱")
                    .font(.caption).foregroundStyle(.secondary)

                Divider()

                HStack(spacing: 8) {
                    Image(systemName: "at").foregroundStyle(.secondary)
                    TextField("收件人邮箱", text: $emailInput)
                        .textFieldStyle(.roundedBorder)
                        .focused($focused)
                        .disabled(sendState == .sending)
                        .onSubmit { send() }
                }

                // 发送状态
                switch sendState {
                case .idle:    EmptyView()
                case .sending:
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.75)
                        Text("正在发送…").font(.caption).foregroundStyle(.secondary)
                    }
                case .success:
                    Label("发送成功", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                case .failure(let msg):
                    Text("❌ \(msg)").font(.caption).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Button("SMTP 设置") { showSMTPSettings = true }
                        .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("取消") { isPresented = false }
                        .keyboardShortcut(.cancelAction)
                        .disabled(sendState == .sending)
                    Button("发送") { send() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(emailInput.trimmingCharacters(in: .whitespaces).isEmpty
                                  || sendState == .sending)
                }
            }
        }
        .padding(18)
        .frame(width: 320)
        .onAppear { focused = true }
        .sheet(isPresented: $showSMTPSettings) {
            SMTPSettingsView().environment(store)
        }
    }

    private func send() {
        let email = emailInput.trimmingCharacters(in: .whitespaces)
        guard !email.isEmpty else { return }
        store.recipientEmail = email
        sendState = .sending
        store.sendDailyEmail(to: email) { result in
            switch result {
            case .success:
                sendState = .success
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { isPresented = false }
            case .failure(let err):
                sendState = .failure(err.localizedDescription)
            }
        }
    }
}
