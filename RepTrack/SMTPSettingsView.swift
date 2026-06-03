import SwiftUI

struct SMTPSettingsView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var host:        String = ""
    @State private var portStr:     String = "465"
    @State private var senderEmail: String = ""
    @State private var password:    String = ""
    @State private var useSSL:      Bool   = true
    @State private var saveHovered  = false
    // 用于清掉自动聚焦
    @FocusState private var focused: Bool

    var canSave: Bool { !host.isEmpty && !senderEmail.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("邮件发送配置").font(.title2).fontWeight(.semibold)
                Spacer()
                Button { saveConfig() } label: {
                    Text("保存")
                        .fontWeight(.semibold)
                        .foregroundStyle(canSave ? .white : Color.secondary)
                        .padding(.horizontal, 16).padding(.vertical, 6)
                        .background(
                            canSave
                                ? AnyShapeStyle(Color.accentColor.opacity(saveHovered ? 0.75 : 1.0))
                                : AnyShapeStyle(Color.secondary.opacity(0.15)),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .scaleEffect(canSave && saveHovered ? 1.04 : 1.0)
                        .animation(.easeInOut(duration: 0.12), value: saveHovered)
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .onHover { if canSave { saveHovered = $0 } }
            }
            .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Presets
                    VStack(alignment: .leading, spacing: 8) {
                        Text("快速填入").font(.subheadline).fontWeight(.semibold).foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            ForEach([("QQ邮箱", SMTPConfig.qqPreset),
                                     ("163邮箱", SMTPConfig.mail163Preset),
                                     ("Gmail",  SMTPConfig.gmailPreset),
                                     ("Outlook",SMTPConfig.outlookPreset)], id: \.0) { name, preset in
                                Button(name) { applyPreset(preset) }
                                    .buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))

                    // SMTP config
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SMTP 服务器").font(.subheadline).fontWeight(.semibold).foregroundStyle(.secondary)

                        LabeledRow("服务器") {
                            TextField("smtp.qq.com", text: $host)
                                .textFieldStyle(.roundedBorder)
                                .focused($focused)
                        }
                        LabeledRow("端口") {
                            TextField("465", text: $portStr)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                            Toggle("SSL", isOn: $useSSL)
                                .toggleStyle(.checkbox)
                        }
                        LabeledRow("发件邮箱") {
                            TextField("your@example.com", text: $senderEmail)
                                .textFieldStyle(.roundedBorder)
                        }
                        LabeledRow("授权码") {
                            SecureField("邮箱授权码（非登录密码）", text: $password)
                                .textFieldStyle(.roundedBorder)
                        }

                        Text("⚠️ 请使用邮件客户端生成的「授权码」，不要填写登录密码。")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))

                }
                .padding(24)
            }

        }
        .frame(width: 460)
        .onAppear {
            loadConfig()
            // 清掉自动聚焦，避免任何输入框高亮选中
            DispatchQueue.main.async { focused = false }
        }
    }

    // MARK: -

    private func loadConfig() {
        let c = store.smtpConfig
        host        = c.host
        portStr     = "\(c.port)"
        senderEmail = c.senderEmail
        useSSL      = c.useSSL
        password    = EmailService.shared.loadPassword()
    }

    private func applyPreset(_ preset: SMTPConfig) {
        host    = preset.host
        portStr = "\(preset.port)"
        useSSL  = preset.useSSL
    }

    private func saveConfig() {
        let port = Int(portStr) ?? (useSSL ? 465 : 587)
        store.smtpConfig = SMTPConfig(host: host, port: port,
                                      senderEmail: senderEmail, useSSL: useSSL)
        if !password.isEmpty { EmailService.shared.savePassword(password) }
        dismiss()   // 保存后直接关闭
    }
}

// MARK: - Small helper

private struct LabeledRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content
    init(_ label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label; self.content = content
    }
    var body: some View {
        HStack {
            Text(label)
                .font(.callout).foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
            content()
        }
    }
}
