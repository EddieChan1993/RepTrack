import Foundation
import Observation

@Observable
final class DataStore {
    var levels: [Level] = []
    var sessions: [ReviewSession] = []

    // MARK: - Storage location

    private static let dataPathKey = "RepTrack.dataFilePath"
    private static let hasSetupKey = "RepTrack.hasCompletedSetup"

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
        sessions = sessions.compactMap { s in
            var copy = s
            copy.items.removeAll { $0.levelId == id }
            return copy.items.isEmpty ? nil : copy
        }
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
        let cal = Calendar.current
        let now = Date()
        return sessions.filter { s in
            switch period {
            case .day:   return cal.isDateInToday(s.date)
            case .week:  return cal.isDate(s.date, equalTo: now, toGranularity: .weekOfYear)
            case .month: return cal.isDate(s.date, equalTo: now, toGranularity: .month)
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

    func levelStats(for levelId: String) -> LevelStats? {
        guard let level = levels.first(where: { $0.id == levelId }) else { return nil }
        let stats = level.lessons.map {
            LessonStat(lesson: $0, reviewCount: reviewCount(for: $0.id), lastReviewed: lastReviewed(lessonId: $0.id))
        }
        return LevelStats(level: level, lessonStats: stats)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: dataURL),
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        levels = saved.levels.map { lv in
            var copy = lv
            copy.lessons = deduplicatedByNumber(copy.lessons)
            copy.lessons.sort { lessonNumberLess($0.number, $1.number) }
            return copy
        }
        sessions = saved.sessions.sorted { $0.date > $1.date }
    }

    func save() {
        try? JSONEncoder().encode(Saved(levels: levels, sessions: sessions)).write(to: dataURL, options: .atomic)
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

    private func importSingleLevel(_ url: URL) {
        let levelId = url.lastPathComponent
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
        } else {
            levels.append(Level(id: levelId, lessons: deduplicatedByNumber(newLessons)))
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

