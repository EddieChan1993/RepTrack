import Foundation
import Security

// MARK: - SMTP Config

struct SMTPConfig {
    var host:        String = ""
    var port:        Int    = 465
    var senderEmail: String = ""
    var useSSL:      Bool   = true  // true = smtps (465), false = smtp + STARTTLS (587)
}

extension SMTPConfig {
    static let qqPreset      = SMTPConfig(host: "smtp.qq.com",           port: 465, senderEmail: "", useSSL: true)
    static let mail163Preset = SMTPConfig(host: "smtp.163.com",          port: 465, senderEmail: "", useSSL: true)
    static let gmailPreset   = SMTPConfig(host: "smtp.gmail.com",        port: 587, senderEmail: "", useSSL: false)
    static let outlookPreset = SMTPConfig(host: "smtp-mail.outlook.com", port: 587, senderEmail: "", useSSL: false)
}

// MARK: - Email Service

final class EmailService {
    static let shared = EmailService()
    private init() {}

    private let kcService = "com.bananatrack.smtp"
    private let kcAccount = "smtp-password"

    // MARK: Keychain

    func savePassword(_ pwd: String) {
        guard let data = pwd.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: kcService,
            kSecAttrAccount as String: kcAccount
        ]
        let status = SecItemUpdate(query as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query; add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    func loadPassword() -> String {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: kcService,
            kSecAttrAccount as String: kcAccount,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var ref: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &ref) == errSecSuccess,
              let data = ref as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: Send

    enum SMTPError: LocalizedError {
        case curlFailed(Int32, String)
        case writeFailed(Error)
        var errorDescription: String? {
            switch self {
            case .curlFailed(_, let msg): return msg.isEmpty ? "发送失败，请检查 SMTP 配置" : msg
            case .writeFailed(let e):     return "临时文件写入失败：\(e.localizedDescription)"
            }
        }
    }

    func send(
        config:    SMTPConfig,
        to:        String,
        subject:   String,
        body:      String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let password = loadPassword()

        // Build RFC 2822 message
        let dateFmt = DateFormatter()
        dateFmt.locale = Locale(identifier: "en_US_POSIX")
        dateFmt.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"

        let subjectEncoded = "=?UTF-8?B?\(Data(subject.utf8).base64EncodedString())?="
        let bodyEncoded    = Data(body.utf8).base64EncodedString(options: .lineLength76Characters)

        let rfc2822 = [
            "From: \(config.senderEmail)",
            "To: \(to)",
            "Subject: \(subjectEncoded)",
            "Date: \(dateFmt.string(from: Date()))",
            "MIME-Version: 1.0",
            "Content-Type: text/html; charset=UTF-8",
            "Content-Transfer-Encoding: base64",
            "",
            bodyEncoded, ""
        ].joined(separator: "\r\n")

        // Write to temp file
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("bt_mail_\(UUID().uuidString).eml")
        do {
            try rfc2822.write(to: tmp, atomically: true, encoding: .utf8)
        } catch {
            DispatchQueue.main.async { completion(.failure(SMTPError.writeFailed(error))) }
            return
        }

        // Build curl args
        let scheme = config.useSSL ? "smtps" : "smtp"
        var args: [String] = [
            "--url",         "\(scheme)://\(config.host):\(config.port)",
            "--user",        "\(config.senderEmail):\(password)",
            "--mail-from",   config.senderEmail,
            "--mail-rcpt",   to,
            "--upload-file", tmp.path,
            "--silent", "--show-error"
        ]
        if !config.useSSL { args.append("--ssl-reqd") }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        proc.arguments = args
        let errPipe = Pipe()
        proc.standardError  = errPipe
        proc.standardOutput = Pipe()

        proc.terminationHandler = { p in
            try? FileManager.default.removeItem(at: tmp)
            let errMsg = (String(data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                                 encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                p.terminationStatus == 0
                    ? completion(.success(()))
                    : completion(.failure(SMTPError.curlFailed(p.terminationStatus, errMsg)))
            }
        }
        do {
            try proc.run()
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            DispatchQueue.main.async { completion(.failure(error)) }
        }
    }
}
