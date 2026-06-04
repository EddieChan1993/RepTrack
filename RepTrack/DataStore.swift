import Foundation
import Observation

@Observable
final class DataStore {
    var levels: [Level] = []
    var sessions: [ReviewSession] = []

    // MARK: - Sync check
    // mtime of the file the last time we read or wrote it
    private var lastKnownMtime: Date = .distantPast
    private var syncTimer: Timer?
    private var saveWorkItem: DispatchWorkItem?

    // MARK: - Storage location

    private static let dataPathKey    = "RepTrack.dataFilePath"
    private static let hasSetupKey    = "RepTrack.hasCompletedSetup"
    private static let folderMapKey   = "RepTrack.levelFolderPaths"
    private static let recipientEmailKey = "RepTrack.recipientEmail"
    private static let smtpHostKey       = "RepTrack.smtpHost"
    private static let smtpPortKey       = "RepTrack.smtpPort"
    private static let smtpUserKey       = "RepTrack.smtpUser"
    private static let smtpSSLKey        = "RepTrack.smtpSSL"

    // MARK: - Email

    var recipientEmail: String {
        get { UserDefaults.standard.string(forKey: DataStore.recipientEmailKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: DataStore.recipientEmailKey) }
    }

    var smtpConfig: SMTPConfig {
        get {
            let port = UserDefaults.standard.integer(forKey: DataStore.smtpPortKey)
            let ssl  = UserDefaults.standard.object(forKey: DataStore.smtpSSLKey)
            return SMTPConfig(
                host:        UserDefaults.standard.string(forKey: DataStore.smtpHostKey) ?? "",
                port:        port == 0 ? 465 : port,
                senderEmail: UserDefaults.standard.string(forKey: DataStore.smtpUserKey) ?? "",
                useSSL:      ssl == nil ? true : UserDefaults.standard.bool(forKey: DataStore.smtpSSLKey)
            )
        }
        set {
            UserDefaults.standard.set(newValue.host,        forKey: DataStore.smtpHostKey)
            UserDefaults.standard.set(newValue.port,        forKey: DataStore.smtpPortKey)
            UserDefaults.standard.set(newValue.senderEmail, forKey: DataStore.smtpUserKey)
            UserDefaults.standard.set(newValue.useSSL,      forKey: DataStore.smtpSSLKey)
        }
    }

    var smtpConfigured: Bool {
        let c = smtpConfig
        return !c.host.isEmpty && !c.senderEmail.isEmpty && !EmailService.shared.loadPassword().isEmpty
    }

    func sendDailyEmail(to recipient: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let (subject, body) = buildEmailContent()
        EmailService.shared.send(config: smtpConfig, to: recipient,
                                  subject: subject, body: body, completion: completion)
    }

    // MARK: - HTML email builder

    private func buildEmailContent() -> (subject: String, body: String) {
        let dateFmt = DateFormatter()
        dateFmt.locale = Locale(identifier: "zh_CN")
        dateFmt.dateFormat = "yyyy年MM月dd日 EEEE"
        let todayStr = dateFmt.string(from: Date())
        let subject  = "📚 今日复习提醒 · \(todayStr)"
        return (subject: subject, body: buildHTML(dateLabel: todayStr))
    }

    /// 与 Helpers.swift levelColor() 使用完全相同的哈希算法 + 调色板，确保邮件颜色和 app 一致。
    private func levelHexColor(_ id: String) -> String {
        let palette = [
            "#E0954F", // hue 0.08 橙
            "#56BF74", // hue 0.38 绿
            "#5486D1", // hue 0.60 蓝
            "#9966CC", // hue 0.75 紫
            "#59BAC7", // hue 0.52 青
            "#D96185", // hue 0.95 粉红
            "#D16354", // hue 0.02 红
            "#637FC7", // hue 0.62 蓝紫
            "#60BFA3", // hue 0.45 青绿
            "#D173B7", // hue 0.88 淡紫
        ]
        let hash = abs(id.unicodeScalars.reduce(5381) { ($0 &* 31) &+ Int($1.value) })
        return palette[hash % palette.count]
    }

    private func countBadgeStyle(_ count: Int) -> (bg: String, fg: String) {
        if count == 0 { return ("#FFF3E0", "#E65100") }
        if count <= 2 { return ("#E3F2FD", "#1565C0") }
        return ("#E8F5E9", "#2E7D32")
    }

    private func buildHTML(dateLabel: String) -> String {
        // ── 推荐复习 HTML ───────────────────────────
        struct RecLevel { let id: String; let avg: Double; let stats: [LessonStat] }
        let recLevels: [RecLevel] = levels.compactMap { level in
            guard !level.lessons.isEmpty else { return nil }
            let stats = level.lessons.map { lesson in
                LessonStat(lesson: lesson,
                           reviewCount: reviewCount(for: lesson.id),
                           lastReviewed: lastReviewed(lessonId: lesson.id))
            }
            let top = topRecommendations(stats)
            guard !top.isEmpty else { return nil }
            let avg = Double(stats.reduce(0) { $0 + $1.reviewCount }) / Double(stats.count)
            return RecLevel(id: level.id, avg: avg, stats: top)
        }

        var recHTML = ""
        if recLevels.isEmpty {
            recHTML = "<div style='padding:20px;text-align:center;color:#8E8E93;font-size:14px;'>暂无推荐（课程复习数据不足）</div>"
        } else {
            for (i, rec) in recLevels.enumerated() {
                let color     = levelHexColor(rec.id)
                let isLast    = i == recLevels.count - 1
                let separator = isLast ? "" : "border-bottom:1px solid #F2F2F7;"
                var lessonRows = ""
                for stat in rec.stats {
                    let (bg, fg) = countBadgeStyle(stat.reviewCount)
                    let countTip = stat.reviewCount == 0 ? "未复习" : "已复习 \(stat.reviewCount) 次"
                    lessonRows += """
                    <tr>
                      <td style='padding:7px 0;font-size:14px;color:#1C1C1E;'>\(stat.lesson.displayName)</td>
                      <td style='padding:7px 0;text-align:right;'>
                        <span style='background:\(bg);color:\(fg);padding:3px 10px;border-radius:100px;font-size:12px;font-weight:600;white-space:nowrap;'>\(countTip)</span>
                      </td>
                    </tr>
                    """
                }
                recHTML += """
                <div style='padding:14px 20px;\(separator)'>
                  <div style='margin-bottom:10px;'>
                    <span style='background:\(color);color:#fff;padding:3px 10px;border-radius:6px;font-size:12px;font-weight:700;'>\(rec.id)</span>
                    <span style='color:#8E8E93;font-size:12px;margin-left:8px;'>均复习 \(String(format: "%.1f", rec.avg)) 次</span>
                  </div>
                  <table width='100%' cellpadding='0' cellspacing='0' style='border-collapse:collapse;'>\(lessonRows)</table>
                </div>
                """
            }
        }

        // ── 通用：session 列表 → HTML ────────────────
        func sessionListHTML(_ list: [ReviewSession], emptyMsg: String) -> String {
            guard !list.isEmpty else {
                return "<div style='padding:20px;text-align:center;color:#8E8E93;font-size:14px;'>\(emptyMsg)</div>"
            }
            var html = ""
            let df = DateFormatter(); df.locale = Locale(identifier: "zh_CN"); df.dateFormat = "MM月dd日 EEEE"
            for session in list {
                var itemRows = ""
                let sorted = session.items.sorted { a, b in
                    (levels.firstIndex { $0.id == a.levelId } ?? Int.max) <
                    (levels.firstIndex { $0.id == b.levelId } ?? Int.max)
                }
                for item in sorted {
                    let color = levelHexColor(item.levelId)
                    let lessons = item.lessonIds
                        .compactMap { lid in levels.flatMap(\.lessons).first { $0.id == lid } }
                        .sorted { lessonNumberLess($0.number, $1.number) }
                    let chips = lessons.map {
                        "<span style='background:\(color)22;color:\(color);padding:2px 8px;border-radius:5px;font-size:13px;margin-right:4px;display:inline-block;margin-bottom:4px;'>\($0.displayName)</span>"
                    }.joined()
                    itemRows += """
                    <tr>
                      <td style='padding:4px 0;vertical-align:top;width:72px;'>
                        <span style='background:\(color);color:#fff;padding:3px 8px;border-radius:5px;font-size:12px;font-weight:700;white-space:nowrap;'>\(item.levelId)</span>
                      </td>
                      <td style='padding:4px 0 4px 6px;'>\(chips)</td>
                    </tr>
                    """
                }
                html += """
                <div style='padding:14px 20px;'>
                  <div style='font-size:14px;font-weight:600;color:#3C3C43;margin-bottom:10px;'>\(df.string(from: session.date))</div>
                  <table width='100%' cellpadding='0' cellspacing='0' style='border-collapse:collapse;'>\(itemRows)</table>
                </div>
                """
            }
            return html
        }

        let cal = Calendar.current
        let todayHTML     = sessionListHTML(sessions.filter { cal.isDateInToday($0.date) },     emptyMsg: "今天暂无复习记录")
        let yesterdayHTML = sessionListHTML(sessions.filter { cal.isDateInYesterday($0.date) }, emptyMsg: "昨天没有复习记录")

        // ── Full HTML ───────────────────────────────
        return """
        <!DOCTYPE html>
        <html>
        <head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0"></head>
        <body style='margin:0;padding:0;background:#F2F2F7;font-family:-apple-system,BlinkMacSystemFont,"PingFang SC","Helvetica Neue",Arial,sans-serif;'>
        <div style='max-width:600px;margin:0 auto;padding:0 0 40px;'>

          <!-- Header -->
          <div style='background:linear-gradient(135deg,#FF9500 0%,#FF6B00 100%);padding:40px 28px 32px;text-align:center;border-radius:0 0 28px 28px;'>
            <div style='font-size:44px;line-height:1;margin-bottom:12px;'>📚</div>
            <h1 style='margin:0 0 8px;color:#FFFFFF;font-size:22px;font-weight:700;letter-spacing:-0.3px;'>今日复习提醒</h1>
            <p style='margin:0;color:rgba(255,255,255,0.88);font-size:14px;'>\(dateLabel)</p>
          </div>

          <div style='padding:20px 12px 0;'>

            <!-- 今日推荐 -->
            <div style='background:#FFFFFF;border-radius:16px;overflow:hidden;margin-bottom:14px;box-shadow:0 1px 10px rgba(0,0,0,0.07);'>
              <div style='padding:15px 20px;border-bottom:1px solid #F2F2F7;'>
                <span style='font-size:18px;vertical-align:middle;margin-right:8px;'>⭐</span>
                <span style='font-size:16px;font-weight:600;color:#1C1C1E;vertical-align:middle;'>今日推荐复习</span>
              </div>
              \(recHTML)
            </div>

            <!-- 今日已复习 -->
            <div style='background:#FFFFFF;border-radius:16px;overflow:hidden;margin-bottom:14px;box-shadow:0 1px 10px rgba(0,0,0,0.07);'>
              <div style='padding:15px 20px;border-bottom:1px solid #F2F2F7;'>
                <span style='font-size:18px;vertical-align:middle;margin-right:8px;'>✅</span>
                <span style='font-size:16px;font-weight:600;color:#1C1C1E;vertical-align:middle;'>今日已复习内容</span>
              </div>
              \(todayHTML)
            </div>

            <!-- 昨天复习 -->
            <div style='background:#FFFFFF;border-radius:16px;overflow:hidden;margin-bottom:20px;box-shadow:0 1px 10px rgba(0,0,0,0.07);'>
              <div style='padding:15px 20px;border-bottom:1px solid #F2F2F7;'>
                <span style='font-size:18px;vertical-align:middle;margin-right:8px;'>📅</span>
                <span style='font-size:16px;font-weight:600;color:#1C1C1E;vertical-align:middle;'>昨天复习内容</span>
              </div>
              \(yesterdayHTML)
            </div>

            <!-- Footer -->
            <p style='text-align:center;color:#AEAEB2;font-size:12px;margin:0;'>由 BananaTrack 自动生成 · \(dateLabel)</p>

          </div>
        </div>
        </body>
        </html>
        """
    }

    // Local-only folder map: levelId → absolute path (never written to the shared data file)
    private var folderMap: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: DataStore.folderMapKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: DataStore.folderMapKey) }
    }

    func sourceURL(for levelId: String) -> URL? {
        guard let path = folderMap[levelId] else { return nil }
        return URL(fileURLWithPath: path)
    }

    private func setSourceURL(_ url: URL, for levelId: String) {
        var map = folderMap
        map[levelId] = url.path
        folderMap = map
    }

    static var defaultDataURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("RepTrack", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("data.json")
    }

    var dataURL: URL {
        if let path = UserDefaults.standard.string(forKey: DataStore.dataPathKey) {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path) {
                return url
            }
        }
        return DataStore.defaultDataURL
    }

    var isFirstLaunch: Bool { !UserDefaults.standard.bool(forKey: DataStore.hasSetupKey) }

    func completeSetup() {
        UserDefaults.standard.set(true, forKey: DataStore.hasSetupKey)
    }

    // Move data file to a new folder and persist the new path.
    func setStorageFolder(_ folderURL: URL) {
        let newURL = folderURL.appendingPathComponent("RepTrackData.json")
        let old = dataURL
        if FileManager.default.fileExists(atPath: old.path) {
            try? FileManager.default.copyItem(at: old, to: newURL)
        }
        UserDefaults.standard.set(newURL.path, forKey: DataStore.dataPathKey)
        save()
    }

    // Replace all in-memory data from an external file, then save to current location.
    @discardableResult
    func importFromFile(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return false }
        levels = saved.levels.map { lv in
            var copy = lv
            copy.lessons = deduplicatedByNumber(copy.lessons)
            copy.lessons.sort { lessonNumberLess($0.number, $1.number) }
            return copy
        }
        sessions = saved.sessions.sorted { $0.date > $1.date }
        save()
        return true
    }

    // Export a copy of current data to a chosen file URL.
    func exportToFile(_ url: URL) throws {
        let data = try JSONEncoder().encode(Saved(levels: levels, sessions: sessions))
        try data.write(to: url, options: .atomic)
    }

    init() {
        load()
        if levels.isEmpty { levels = Self.defaultLevels() }
        startSyncTimer()
    }

    deinit { syncTimer?.invalidate() }

    // Poll every 30 s — lightweight mtime check, no kernel event machinery needed.
    private func startSyncTimer() {
        syncTimer?.invalidate()
        syncTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.reloadIfNeeded()
        }
    }

    // Compare file mtime with what we last read/wrote. Reload only on external change.
    func reloadIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: dataURL.path),
              let mtime = attrs[.modificationDate] as? Date,
              mtime > lastKnownMtime.addingTimeInterval(1) else { return }
        load()
    }

    // MARK: - Sessions

    func addSession(_ session: ReviewSession) {
        sessions.append(session)
        sessions.sort { $0.date > $1.date }
        save()
    }

    func deleteSession(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        save()
    }

    func deleteSessions(_ ids: Set<UUID>) {
        sessions.removeAll { ids.contains($0.id) }
        save()
    }

    func updateSession(_ session: ReviewSession) {
        guard let idx = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[idx] = session
        sessions.sort { $0.date > $1.date }
        save()
    }

    // MARK: - Levels & Lessons

    func swapLevels(_ a: String, _ b: String) {
        guard let ia = levels.firstIndex(where: { $0.id == a }),
              let ib = levels.firstIndex(where: { $0.id == b }) else { return }
        levels.swapAt(ia, ib)
        save()
    }

    func addLevel(id: String) {
        guard !id.isEmpty, !levels.contains(where: { $0.id == id }) else { return }
        levels.append(Level(id: id, lessons: []))
        save()
    }

    func deleteLevel(_ id: String) {
        levels.removeAll { $0.id == id }
        // 历史复习记录保留，不随等级删除而清除
        save()
    }

    func addLesson(number: String, title: String, to levelId: String) {
        let lessonId = "\(levelId)-\(number)"
        guard let li = levels.firstIndex(where: { $0.id == levelId }),
              !levels[li].lessons.contains(where: { $0.id == lessonId }) else { return }
        levels[li].lessons.append(Lesson(id: lessonId, number: number, title: title, levelId: levelId))
        levels[li].lessons.sort { lessonNumberLess($0.number, $1.number) }
        save()
    }

    func updateLessonTitle(_ title: String, lessonId: String, levelId: String) {
        guard let li = levels.firstIndex(where: { $0.id == levelId }),
              let lsi = levels[li].lessons.firstIndex(where: { $0.id == lessonId }) else { return }
        levels[li].lessons[lsi].title = title
        save()
    }

    func deleteLesson(lessonId: String, levelId: String) {
        guard let li = levels.firstIndex(where: { $0.id == levelId }) else { return }
        levels[li].lessons.removeAll { $0.id == lessonId }
        save()
    }

    // Creates a lesson if it doesn't exist yet; returns the lesson.
    @discardableResult
    func ensureLesson(number: String, levelId: String) -> Lesson {
        let lessonId = "\(levelId)-\(number)"
        if let li = levels.firstIndex(where: { $0.id == levelId }) {
            // Match by ID, then by number string, then by integer value ("1" == "001")
            if let existing = levels[li].lessons.first(where: {
                $0.id == lessonId ||
                $0.number == number ||
                (Int($0.number) != nil && Int($0.number) == Int(number))
            }) {
                return existing
            }
        }
        let lesson = Lesson(id: lessonId, number: number, title: "", levelId: levelId)
        if let li = levels.firstIndex(where: { $0.id == levelId }) {
            levels[li].lessons.append(lesson)
            levels[li].lessons.sort { lessonNumberLess($0.number, $1.number) }
        }
        return lesson
    }

    // MARK: - Stats

    private func sessions(in period: StatPeriod) -> [ReviewSession] {
        // Use a Monday-based calendar so "this week" = Mon–Sun regardless of device locale
        var cal = Calendar.current
        cal.firstWeekday = 2   // 1 = Sunday, 2 = Monday
        let now = Date()
        return sessions.filter { s in
            switch period {
            case .day:   return cal.isDateInToday(s.date)
            case .week:  return cal.isDate(s.date, equalTo: now, toGranularity: .weekOfYear)
            case .month: return cal.isDate(s.date, equalTo: now, toGranularity: .month)
            case .year:  return cal.isDate(s.date, equalTo: now, toGranularity: .year)
            case .total: return true
            }
        }
    }

    func reviewedLessonCount(period: StatPeriod) -> Int {
        Set(sessions(in: period).flatMap { $0.items.flatMap(\.lessonIds) }).count
    }

    func reviewedLessonCount(levelId: String, period: StatPeriod) -> Int {
        Set(sessions(in: period)
            .flatMap { $0.items.filter { $0.levelId == levelId }.flatMap(\.lessonIds) }).count
    }

    // 累计复习次数（每条记录都算，不去重）
    func totalReviewCount(period: StatPeriod) -> Int {
        sessions(in: period).flatMap { $0.items.flatMap(\.lessonIds) }.count
    }

    func totalReviewCount(levelId: String, period: StatPeriod) -> Int {
        sessions(in: period)
            .flatMap { $0.items.filter { $0.levelId == levelId }.flatMap(\.lessonIds) }.count
    }

    func reviewCount(for lessonId: String) -> Int {
        sessions.reduce(0) { total, s in
            total + s.items.reduce(0) { t, item in t + (item.lessonIds.contains(lessonId) ? 1 : 0) }
        }
    }

    func lastReviewed(lessonId: String) -> Date? {
        sessions
            .filter { $0.items.contains { $0.lessonIds.contains(lessonId) } }
            .map(\.date)
            .max()
    }

    // 单次 O(sessions) 扫描构建全量统计，避免对每课各扫一遍
    private func buildReviewIndex() -> (counts: [String: Int], lastDates: [String: Date]) {
        var counts: [String: Int] = [:]
        var lastDates: [String: Date] = [:]
        for session in sessions {
            for item in session.items {
                for lessonId in item.lessonIds {
                    counts[lessonId, default: 0] += 1
                    if let prev = lastDates[lessonId] {
                        if session.date > prev { lastDates[lessonId] = session.date }
                    } else {
                        lastDates[lessonId] = session.date
                    }
                }
            }
        }
        return (counts, lastDates)
    }

    func levelStats(for levelId: String) -> LevelStats? {
        guard let level = levels.first(where: { $0.id == levelId }) else { return nil }
        let index = buildReviewIndex()
        let stats = level.lessons.map {
            LessonStat(lesson: $0,
                       reviewCount: index.counts[$0.id] ?? 0,
                       lastReviewed: index.lastDates[$0.id])
        }
        return LevelStats(level: level, lessonStats: stats)
    }

    // MARK: - Persistence

    private func load() {
        let url = dataURL
        guard let data = try? Data(contentsOf: url) else { return }

        // Record mtime so we can detect future external changes
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let mtime = attrs[.modificationDate] as? Date {
            lastKnownMtime = mtime
        }

        // Migrate sourceURL out of JSON into UserDefaults (runs once on old data)
        if folderMap.isEmpty, let legacy = try? JSONDecoder().decode(LegacySaved.self, from: data) {
            var map: [String: String] = [:]
            for lv in legacy.levels { if let url = lv.sourceURL { map[lv.id] = url.path } }
            if !map.isEmpty { folderMap = map }
        }

        guard let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        levels = saved.levels.map { lv in
            var copy = lv
            copy.lessons = deduplicatedByNumber(copy.lessons)
            copy.lessons.sort { lessonNumberLess($0.number, $1.number) }
            return copy
        }
        sessions = saved.sessions.sorted { $0.date > $1.date }
    }

    func save() {
        // 防抖：300ms 内多次调用只触发最后一次，后台线程写磁盘，不阻塞 UI
        saveWorkItem?.cancel()
        let payload = Saved(levels: levels, sessions: sessions)
        let url = dataURL
        let workItem = DispatchWorkItem { [weak self] in
            guard let data = try? JSONEncoder().encode(payload) else { return }
            try? data.write(to: url, options: .atomic)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let mtime = attrs[.modificationDate] as? Date {
                DispatchQueue.main.async { self?.lastKnownMtime = mtime }
            } else {
                DispatchQueue.main.async { self?.lastKnownMtime = Date() }
            }
        }
        saveWorkItem = workItem
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    // Legacy decode support: Level used to carry sourceURL in the JSON.
    // We read it once to migrate into UserDefaults, then ignore it going forward.
    private struct LegacyLevel: Codable {
        let id: String
        var lessons: [Lesson]
        var sourceURL: URL?
    }
    private struct LegacySaved: Codable {
        var levels: [LegacyLevel]
        var sessions: [ReviewSession]
    }

    private struct Saved: Codable {
        var levels: [Level]
        var sessions: [ReviewSession]
    }

    // Each selected folder = one level; .md files inside = lessons ("011.烹饪.md")
    func importLevelFolders(_ urls: [URL]) {
        for url in urls { importSingleLevel(url) }
        levels.sort { $0.id < $1.id }
        save()
    }

    func refreshLevel(_ levelId: String) {
        guard let url = sourceURL(for: levelId) else { return }
        importSingleLevel(url)
        save()
    }

    func refreshAllLevels() {
        let urls = levels.compactMap { sourceURL(for: $0.id) }
        guard !urls.isEmpty else { return }
        for url in urls { importSingleLevel(url) }
        save()
    }

    private func importSingleLevel(_ url: URL) {
        let levelId = url.lastPathComponent
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        )) ?? []

        var newLessons: [Lesson] = []
        for fileURL in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let stem = fileURL.deletingPathExtension().lastPathComponent
            let parts = stem.split(separator: ".", maxSplits: 1).map(String.init)
            guard let number = parts.first?.trimmingCharacters(in: .whitespaces), !number.isEmpty else { continue }
            let title = parts.count > 1 ? parts[1] : ""
            let lessonId = "\(levelId)-\(number)"
            newLessons.append(Lesson(id: lessonId, number: number, title: title, levelId: levelId))
        }

        if let idx = levels.firstIndex(where: { $0.id == levelId }) {
            // Update titles for existing lessons; append genuinely new ones
            for lesson in newLessons {
                if let existIdx = levels[idx].lessons.firstIndex(where: { sameNumber($0.number, lesson.number) }) {
                    if !lesson.title.isEmpty {
                        levels[idx].lessons[existIdx].title = lesson.title
                    }
                } else {
                    levels[idx].lessons.append(lesson)
                }
            }
            // Remove lessons whose files no longer exist in the folder
            let removedIds = Set(
                levels[idx].lessons
                    .filter { existing in !newLessons.contains(where: { sameNumber($0.number, existing.number) }) }
                    .map(\.id)
            )
            if !removedIds.isEmpty {
                levels[idx].lessons.removeAll { removedIds.contains($0.id) }
                // Clean up session references to deleted lessons
                sessions = sessions.compactMap { s in
                    var copy = s
                    copy.items = copy.items.compactMap { item in
                        guard item.levelId == levelId else { return item }
                        var i = item
                        i.lessonIds.removeAll { removedIds.contains($0) }
                        return i.lessonIds.isEmpty ? nil : i
                    }
                    return copy.items.isEmpty ? nil : copy
                }
            }
            levels[idx].lessons = deduplicatedByNumber(levels[idx].lessons)
            levels[idx].lessons.sort { lessonNumberLess($0.number, $1.number) }
            setSourceURL(url, for: levelId)
        } else {
            let level = Level(id: levelId, lessons: deduplicatedByNumber(newLessons))
            setSourceURL(url, for: levelId)
            levels.append(level)
        }
    }

    static func defaultLevels() -> [Level] {
        [
            Level(id: "S1-EK", lessons: []),
            Level(id: "S2-IC", lessons: []),
            Level(id: "S3-IK", lessons: [
                Lesson(id: "S3-IK-011", number: "011", title: "烹饪",   levelId: "S3-IK"),
                Lesson(id: "S3-IK-012", number: "012", title: "点餐",   levelId: "S3-IK"),
                Lesson(id: "S3-IK-013", number: "013", title: "旅行路上", levelId: "S3-IK"),
                Lesson(id: "S3-IK-014", number: "014", title: "极限挑战", levelId: "S3-IK"),
                Lesson(id: "S3-IK-017", number: "017", title: "环球美食", levelId: "S3-IK"),
                Lesson(id: "S3-IK-018", number: "018", title: "饮食文化", levelId: "S3-IK"),
                Lesson(id: "S3-IK-043", number: "043", title: "时态梳理", levelId: "S3-IK"),
                Lesson(id: "S3-IK-044", number: "044", title: "人生经历", levelId: "S3-IK"),
                Lesson(id: "S3-IK-045", number: "045", title: "语言梳理", levelId: "S3-IK"),
                Lesson(id: "S3-IK-046", number: "046", title: "小组对话", levelId: "S3-IK"),
                Lesson(id: "S3-IK-047", number: "047", title: "工作方式", levelId: "S3-IK"),
                Lesson(id: "S3-IK-048", number: "048", title: "商务职场", levelId: "S3-IK"),
            ]),
        ]
    }
}

