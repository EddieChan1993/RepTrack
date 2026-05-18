import Foundation

struct Level: Identifiable, Codable, Hashable {
    let id: String
    var lessons: [Lesson]
}

struct Lesson: Identifiable, Codable, Hashable {
    let id: String
    var number: String
    var title: String
    var levelId: String

    var displayName: String {
        let p = paddedDisplay(number)
        return title.isEmpty ? p : "\(p). \(title)"
    }
}

struct ReviewSession: Identifiable, Codable {
    var id: UUID
    var date: Date
    var items: [ReviewItem]

    init(id: UUID = UUID(), date: Date = .now, items: [ReviewItem] = []) {
        self.id = id
        self.date = date
        self.items = items
    }
}

struct ReviewItem: Identifiable, Codable {
    var id: UUID
    var levelId: String
    var lessonIds: [String]

    init(id: UUID = UUID(), levelId: String, lessonIds: [String] = []) {
        self.id = id
        self.levelId = levelId
        self.lessonIds = lessonIds
    }
}

struct LessonStat: Identifiable {
    var id: String { lesson.id }
    var lesson: Lesson
    var reviewCount: Int
    var lastReviewed: Date?
}

struct LevelStats {
    var level: Level
    var lessonStats: [LessonStat]

    var totalLessons: Int { lessonStats.count }
    var reviewedCount: Int { lessonStats.filter { $0.reviewCount > 0 }.count }
    var totalReviews: Int { lessonStats.reduce(0) { $0 + $1.reviewCount } }
    var coverage: Double {
        guard totalLessons > 0 else { return 0 }
        return Double(reviewedCount) / Double(totalLessons)
    }
}
