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

func levelColor(_ id: String) -> Color {
    // Tailwind CSS 600 色阶 — 感知均匀校准，同亮度同饱和度，白字可读性一致
    let palette: [Color] = [
        Color(red: 0.149, green: 0.388, blue: 0.922), // blue-600    #2563EB
        Color(red: 0.086, green: 0.647, blue: 0.290), // green-600   #16A34A
        Color(red: 0.863, green: 0.149, blue: 0.149), // red-600     #DC2626
        Color(red: 0.576, green: 0.200, blue: 0.918), // purple-600  #9333EA
        Color(red: 0.035, green: 0.569, blue: 0.698), // cyan-600    #0891B2
        Color(red: 0.859, green: 0.153, blue: 0.467), // pink-600    #DB2777
        Color(red: 0.310, green: 0.275, blue: 0.898), // indigo-600  #4F46E5
        Color(red: 0.918, green: 0.345, blue: 0.047), // orange-600  #EA580C
        Color(red: 0.051, green: 0.580, blue: 0.533), // teal-600    #0D9488
        Color(red: 0.486, green: 0.227, blue: 0.929), // violet-600  #7C3AED
    ]
    let hash = abs(id.unicodeScalars.reduce(5381) { ($0 &* 31) &+ Int($1.value) })
    return palette[hash % palette.count]
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
