import SwiftUI

// MARK: - Recommendation scoring (shared between StatsView and email)

/// Multi-dimensional weighted score — higher = more urgently needs review.
func recommendScore(_ stat: LessonStat, avg: Double, maxDays: Double) -> Double {
    let now = Date()
    let countScore = (avg - Double(stat.reviewCount)) / (avg + 1)
    let days: Double
    if let last = stat.lastReviewed {
        days = min(max(now.timeIntervalSince(last) / 86400, 0), maxDays)
    } else {
        days = maxDays
    }
    let recencyScore = maxDays > 0 ? days / maxDays : 1.0
    return 0.7 * countScore + 0.3 * recencyScore
}

/// Top-N recommendations from a list of LessonStats (reviewed-only).
func topRecommendations(_ stats: [LessonStat], count: Int = 4) -> [LessonStat] {
    let reviewed = stats.filter { $0.reviewCount > 0 }
    guard !reviewed.isEmpty else { return [] }
    let avg = Double(reviewed.reduce(0) { $0 + $1.reviewCount }) / Double(reviewed.count)
    let maxDays = reviewed.compactMap { $0.lastReviewed }
        .map { Date().timeIntervalSince($0) / 86400 }
        .max() ?? 30
    return Array(
        reviewed.sorted { recommendScore($0, avg: avg, maxDays: maxDays) >
                          recommendScore($1, avg: avg, maxDays: maxDays) }
            .prefix(count)
    )
}

// MARK: - Flow layout (wrapping HStack)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0
        for sv in subviews {
            let sz = sv.sizeThatFits(.unspecified)
            if x + sz.width > maxW, x > 0 { x = 0; y += lineH + spacing; lineH = 0 }
            x += sz.width + spacing
            lineH = max(lineH, sz.height)
        }
        return CGSize(width: maxW, height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
        for sv in subviews {
            let sz = sv.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += lineH + spacing; lineH = 0 }
            sv.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += sz.width + spacing
            lineH = max(lineH, sz.height)
        }
    }
}

// MARK: - Stat period

enum StatPeriod: String, CaseIterable {
    case day = "日", week = "周", month = "月", year = "年", total = "累计"

    var label: String {
        switch self {
        case .day:   return "今日"
        case .week:  return "本周"
        case .month: return "本月"
        case .year:  return "今年"
        case .total: return "累计"
        }
    }

    /// 日/周/月/年 循环切换，累计为固定卡不参与切换
    var next: StatPeriod {
        let cycling: [StatPeriod] = [.day, .week, .month, .year]
        guard let idx = cycling.firstIndex(of: self) else { return self }
        return cycling[(idx + 1) % cycling.count]
    }
}

private let levelColorPalette: [Color] = [
    Color(red: 0.898, green: 0.282, blue: 0.302), // 红      #E5484D  (~0°)
    Color(red: 0.000, green: 0.565, blue: 1.000), // 蓝      #0090FF  (~211°)
    Color(red: 0.275, green: 0.655, blue: 0.345), // 翠绿    #46A758  (~135°)
    Color(red: 0.839, green: 0.251, blue: 0.624), // 洋红    #D6409F  (~313°)
    Color(red: 0.969, green: 0.420, blue: 0.082), // 橙      #F76B15  (~25°)
    Color(red: 0.243, green: 0.388, blue: 0.867), // 靛      #3E63DD  (~228°)
    Color(red: 0.071, green: 0.647, blue: 0.580), // 青      #12A594  (~170°)
    Color(red: 0.851, green: 0.467, blue: 0.024), // 琥珀    #D97706  (~38°)
    Color(red: 0.557, green: 0.306, blue: 0.776), // 紫      #8E4EC6  (~277°)
    Color(red: 0.000, green: 0.635, blue: 0.784), // 天青    #00A2C7  (~192°)
]

/// 按等级在 store 中的位置索引分配颜色，避免哈希碰撞导致相邻等级同色
func levelColor(index: Int) -> Color {
    levelColorPalette[abs(index) % levelColorPalette.count]
}

/// 兼容旧调用：无法取得索引时回退到哈希（仅在无 store 上下文时使用）
func levelColor(_ id: String) -> Color {
    let hash = abs(id.unicodeScalars.reduce(5381) { ($0 &* 31) &+ Int($1.value) })
    return levelColorPalette[hash % levelColorPalette.count]
}

// Display-only padding: "2" → "002", "21" → "021"; never changes stored data
func paddedDisplay(_ n: String) -> String {
    if let i = Int(n), n.count < 3 { return String(format: "%03d", i) }
    return n
}

// Used when mapping user input to a lesson number for lookup/create
func normalizeNumber(_ input: String) -> String {
    input.trimmingCharacters(in: .whitespaces)
}

// Numeric-aware sort: "2" < "10" < "019", falls back to string for non-numeric
func lessonNumberLess(_ a: String, _ b: String) -> Bool {
    switch (Int(a), Int(b)) {
    case (let x?, let y?): return x < y
    case (nil, _?):        return false
    case (_?, nil):        return true
    case (nil, nil):       return a < b
    }
}

// True if two number strings represent the same integer ("2" == "002")
func sameNumber(_ a: String, _ b: String) -> Bool {
    if a == b { return true }
    if let ia = Int(a), let ib = Int(b) { return ia == ib }
    return false
}

// Remove integer-duplicate lessons; prefers the entry with a non-empty title
func deduplicatedByNumber(_ lessons: [Lesson]) -> [Lesson] {
    var seen: [String: Int] = [:]  // canonical key → index in result
    var result: [Lesson] = []
    for lesson in lessons {
        let key = Int(lesson.number).map { String($0) } ?? lesson.number
        if let idx = seen[key] {
            if !lesson.title.isEmpty && result[idx].title.isEmpty {
                result[idx].title = lesson.title
            }
        } else {
            seen[key] = result.count
            result.append(lesson)
        }
    }
    return result
}
