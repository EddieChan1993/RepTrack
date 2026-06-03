import SwiftUI
import Charts
import UniformTypeIdentifiers

// MARK: - Main View

struct StatsView: View {
    @Environment(DataStore.self) private var store
    @State private var selectedTab = "全部"
    @State private var draggingId: String?
    @State private var isRefreshing = false
    @State private var refreshHovered = false
    @State private var refreshRotation: Double = 0
    @State private var showFolderMissingAlert = false
    @State private var missingPaths: [String] = []

    private var tabs: [String] { ["全部"] + store.levels.map(\.id) }

    private var canRefresh: Bool {
        if selectedTab == "全部" { return store.levels.contains { store.sourceURL(for: $0.id) != nil } }
        return store.sourceURL(for: selectedTab) != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        TabButton(title: "全部", isSelected: selectedTab == "全部") {
                            selectedTab = "全部"
                        }
                        ForEach(store.levels, id: \.id) { level in
                            TabButton(
                                title: level.id,
                                isSelected: selectedTab == level.id,
                                action: { selectedTab = level.id },
                                onDelete: {
                                    if selectedTab == level.id { selectedTab = "全部" }
                                    store.deleteLevel(level.id)
                                }
                            )
                            .onDrag {
                                draggingId = level.id
                                return NSItemProvider(object: level.id as NSString)
                            }
                            .onDrop(of: [UTType.plainText], isTargeted: nil) { _ in
                                guard let from = draggingId, from != level.id else { return false }
                                store.swapLevels(from, level.id)
                                draggingId = nil
                                return true
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                if canRefresh {
                    Divider().frame(height: 20)
                    Button {
                        guard !isRefreshing else { return }

                        // Validate paths before refreshing
                        let levelsToCheck = selectedTab == "全部"
                            ? store.levels.map(\.id)
                            : [selectedTab]
                        let missing = levelsToCheck.compactMap { id -> String? in
                            guard let url = store.sourceURL(for: id) else { return nil }
                            var isDir: ObjCBool = false
                            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                            return (exists && isDir.boolValue) ? nil : url.path
                        }
                        if !missing.isEmpty {
                            missingPaths = missing
                            showFolderMissingAlert = true
                            return
                        }

                        isRefreshing = true
                        withAnimation(.linear(duration: 0.6)) { refreshRotation += 360 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                            if selectedTab == "全部" {
                                store.refreshAllLevels()
                            } else {
                                store.refreshLevel(selectedTab)
                            }
                            isRefreshing = false
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(refreshHovered ? Color.primary : .secondary)
                            .rotationEffect(.degrees(refreshRotation))
                            .frame(width: 44, height: 44)
                            .background(refreshHovered ? Color.primary.opacity(0.06) : .clear)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { refreshHovered = $0 }
                    .help(selectedTab == "全部" ? "重新扫描所有等级文件夹" : "重新扫描 \(selectedTab) 文件夹")
                    .alert("找不到文件夹", isPresented: $showFolderMissingAlert) {
                        Button("好") { }
                    } message: {
                        let paths = missingPaths.map { "• " + $0.replacingOccurrences(of: NSHomeDirectory(), with: "~") }.joined(separator: "\n")
                        Text("以下文件夹在本机上不存在，请重新导入对应等级的文件夹：\n\n\(paths)")
                    }
                }
            }
            .frame(height: 44)
            .background(.bar)

            Divider()

            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if selectedTab == "全部" {
                            AllLevelsContent(paneHeight: proxy.size.height)
                        } else if let stats = store.levelStats(for: selectedTab) {
                            LevelContent(stats: stats, paneHeight: proxy.size.height)
                        } else {
                            ContentUnavailableView(
                                "暂无课程",
                                systemImage: "tray",
                                description: Text("点击工具栏文件夹图标导入课程目录")
                            )
                        }
                    }
                    .padding(16)
                }
            }
        }
        .onChange(of: store.levels) { _, _ in
            if !tabs.contains(selectedTab) { selectedTab = "全部" }
        }
    }
}

// MARK: - Tab button

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    var onDelete: (() -> Void)? = nil
    @State private var hovered = false
    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(spacing: 0) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? .primary : (hovered ? .primary : .secondary))
                .padding(.leading, 14)
                .padding(.trailing, onDelete != nil ? 4 : 14)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .onTapGesture { action() }

            if onDelete != nil {
                Button { showDeleteConfirm = true } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary.opacity(hovered ? 1 : 0))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
            }
        }
        .background(
            isSelected
                ? AnyShapeStyle(Color.accentColor.opacity(0.12))
                : AnyShapeStyle(hovered ? Color.secondary.opacity(0.08) : Color.clear),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .scaleEffect(hovered && !isSelected ? 1.03 : 1.0)
        .animation(.easeInOut(duration: 0.12), value: hovered)
        .onHover { hovered = $0 }
        .confirmationDialog("删除「\(title)」等级？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) { onDelete?() }
        } message: {
            Text("该等级下的所有课程将被移除，相关复习记录中的条目也会同步删除。")
        }
    }
}

private struct CardHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - "全部" content

struct LevelCoverage: Identifiable {
    let id: String; let total: Int; let reviewed: Int
    var pct: Double { total > 0 ? Double(reviewed) / Double(total) * 100 : 0 }
}

struct AllLevelsContent: View {
    @Environment(DataStore.self) private var store
    var paneHeight: CGFloat = 400
    @State private var reviewPeriod: StatPeriod = .week
    @State private var coveragePeriod: StatPeriod = .week
    @State private var chartCardHeight: CGFloat = 0

    private var totalLessons: Int { store.levels.reduce(0) { $0 + $1.lessons.count } }
    private var coverage: Double {
        guard totalLessons > 0 else { return 0 }
        return Double(store.reviewedLessonCount(period: coveragePeriod)) / Double(totalLessons)
    }
    private var levelCoverages: [LevelCoverage] {
        store.levels.map { lv in
            let rev = lv.lessons.filter { store.reviewCount(for: $0.id) > 0 }.count
            return LevelCoverage(id: lv.id, total: lv.lessons.count, reviewed: rev)
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            StatCard("总课数", "\(totalLessons)", Color(red: 0.10, green: 0.48, blue: 1.00))
            PeriodStatCard(
                value: store.reviewedLessonCount(period: reviewPeriod),
                color: Color(red: 0.00, green: 0.72, blue: 0.72),
                period: $reviewPeriod
            )
            PeriodCoverageCard(
                pct: coverage,
                color: Color(red: 0.62, green: 0.15, blue: 0.90),
                period: $coveragePeriod
            )
        }
        if levelCoverages.filter({ $0.total > 0 }).isEmpty {
            ContentUnavailableView("暂无课程数据", systemImage: "folder.badge.plus",
                description: Text("点击工具栏文件夹图标导入课程目录"))
        } else {
            let levelKey = store.levels.map(\.id).joined()
            HStack(alignment: .top, spacing: 14) {
                CoverageChartCard(coverages: levelCoverages, paneHeight: paneHeight)
                    .id(levelKey)
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: CardHeightKey.self, value: geo.size.height)
                    })
                RecommendedLessonsCard()
                    .id(levelKey)
                    .frame(minWidth: 190, maxWidth: 240)
                    .frame(height: chartCardHeight > 0 ? chartCardHeight : (paneHeight > 0 ? max(150, paneHeight - 214) : 280))
            }
            .onPreferenceChange(CardHeightKey.self) { chartCardHeight = $0 }
        }
    }
}

struct CoverageChartCard: View {
    let coverages: [LevelCoverage]
    var paneHeight: CGFloat = 400
    @State private var hoveredId: String?
    @State private var animate = false

    // 扣掉统计卡(~96) + 卡片头部(38) + 内外间距(~80) 剩余给图表
    // paneHeight 首帧为 0，用 280 保底避免图表太矮被截断
    private var chartHeight: CGFloat { paneHeight > 0 ? max(150, paneHeight - 214) : 280 }

    private var hoveredItem: LevelCoverage? { coverages.first { $0.id == hoveredId } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("各内容覆盖率").font(.headline)
                Spacer()
                if let lv = hoveredItem {
                    CoverageTooltip(lv: lv)
                        .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .trailing)))
                }
            }
            .frame(height: 28)
            .animation(.easeInOut(duration: 0.12), value: hoveredId)

            coverageChart
                .frame(height: chartHeight)
                .animation(.spring(response: 0.6, dampingFraction: 0.82), value: animate)
        }
        .padding(16)
        .background(.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .onAppear {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.8).delay(0.05)) { animate = true }
        }
    }

    private var coverageChart: some View {
        Chart(coverages) { lv in
            let dimmed = hoveredId != nil && hoveredId != lv.id
            let opacity: Double = dimmed ? 0.3 : 1.0
            let xVal: Double = animate ? lv.pct : 0
            BarMark(x: .value("覆盖率 %", xVal), y: .value("内容", lv.id))
                .foregroundStyle(levelColor(lv.id).opacity(opacity).gradient)
                .cornerRadius(6)
                .annotation(position: .trailing, alignment: .leading, spacing: 6) {
                    Text(String(format: "%.0f%%", lv.pct))
                        .font(.caption2)
                        .foregroundStyle(hoveredId == lv.id ? Color.primary : Color.secondary)
                }
        }
        .chartXScale(domain: 0...100)
        .chartXAxis {
            AxisMarks(values: [0, 25, 50, 75, 100]) {
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                AxisValueLabel().font(.caption2)
            }
        }
        .chartYAxis {
            AxisMarks { AxisValueLabel().font(.system(size: 12, weight: .medium)) }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Color.clear.contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let loc):
                            let frame = geo[proxy.plotFrame!]
                            let y = loc.y - frame.origin.y
                            withAnimation(.easeInOut(duration: 0.1)) {
                                hoveredId = proxy.value(atY: y, as: String.self)
                            }
                        case .ended:
                            withAnimation(.easeInOut(duration: 0.1)) { hoveredId = nil }
                        }
                    }
            }
        }
    }
}

private struct CoverageTooltip: View {
    let lv: LevelCoverage
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(levelColor(lv.id)).frame(width: 7, height: 7)
            Text(lv.id).font(.caption).fontWeight(.medium)
            Text("·").foregroundStyle(.secondary)
            Text("\(lv.reviewed)/\(lv.total) 课  \(String(format: "%.0f%%", lv.pct))")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(.secondary.opacity(0.1), in: Capsule())
    }
}

// MARK: - Recommended lessons card

struct RecommendedLessonsCard: View {
    @Environment(DataStore.self) private var store

    private struct LevelRec {
        let level: Level
        let avg: Double
        let lessons: [LessonStat]
    }

    private var recommendations: [LevelRec] {
        store.levels.compactMap { level in
            guard !level.lessons.isEmpty else { return nil }
            let stats = level.lessons.map { lesson in
                LessonStat(
                    lesson: lesson,
                    reviewCount: store.reviewCount(for: lesson.id),
                    lastReviewed: store.lastReviewed(lessonId: lesson.id)
                )
            }
            let avg = Double(stats.reduce(0) { $0 + $1.reviewCount }) / Double(stats.count)
            return LevelRec(level: level, avg: avg, lessons: topRecommendations(stats))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("推荐复习").font(.headline)
                Spacer()
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(height: 28)

            ScrollView(.vertical, showsIndicators: false) {
                if recommendations.isEmpty {
                    Text("暂无课程数据")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 12)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(recommendations, id: \.level.id) { rec in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 6) {
                                    Text(rec.level.id)
                                        .font(.caption).fontWeight(.semibold)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(levelColor(rec.level.id), in: RoundedRectangle(cornerRadius: 4))
                                    Text(String(format: "均 %.1f 次", rec.avg))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                ForEach(rec.lessons) { stat in
                                    HStack(spacing: 0) {
                                        Text(stat.lesson.displayName)
                                            .font(.callout)
                                            .lineLimit(1)
                                        Spacer(minLength: 8)
                                        Text("\(stat.reviewCount)")
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(stat.reviewCount == 0
                                                ? Color.orange.opacity(0.85)
                                                : Color.secondary)
                                            .padding(.horizontal, 5).padding(.vertical, 2)
                                            .background(
                                                (stat.reviewCount == 0 ? Color.orange : Color.secondary)
                                                    .opacity(0.10),
                                                in: RoundedRectangle(cornerRadius: 4)
                                            )
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(16)
        .background(.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Single level content

struct LevelContent: View {
    @Environment(DataStore.self) private var store
    let stats: LevelStats
    var paneHeight: CGFloat = 400
    @State private var reviewPeriod: StatPeriod = .week
    @State private var coveragePeriod: StatPeriod = .week
    @State private var chartCardHeight: CGFloat = 0

    private var coverage: Double {
        guard stats.totalLessons > 0 else { return 0 }
        return Double(store.reviewedLessonCount(levelId: stats.level.id, period: coveragePeriod)) / Double(stats.totalLessons)
    }

    var body: some View {
        HStack(spacing: 14) {
            StatCard("总课数", "\(stats.totalLessons)", Color(red: 0.10, green: 0.48, blue: 1.00))
            PeriodStatCard(
                value: store.reviewedLessonCount(levelId: stats.level.id, period: reviewPeriod),
                color: Color(red: 0.00, green: 0.72, blue: 0.72),
                period: $reviewPeriod
            )
            PeriodCoverageCard(
                pct: coverage,
                color: Color(red: 0.62, green: 0.15, blue: 0.90),
                period: $coveragePeriod
            )
        }
        if stats.totalLessons > 0 {
            HStack(alignment: .top, spacing: 14) {
                LessonCountChartCard(stats: stats, paneHeight: paneHeight)
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: CardHeightKey.self, value: geo.size.height)
                    })
                LevelRecommendedCard(stats: stats)
                    .frame(minWidth: 190, maxWidth: 240)
                    .frame(height: chartCardHeight > 0 ? chartCardHeight : 270)
            }
            .onPreferenceChange(CardHeightKey.self) { chartCardHeight = $0 }
        } else {
            ContentUnavailableView("该等级暂无课程", systemImage: "doc.text",
                description: Text("导入文件夹后自动填充课程列表"))
        }
    }
}

struct LevelRecommendedCard: View {
    let stats: LevelStats

    private var avg: Double {
        guard !stats.lessonStats.isEmpty else { return 0 }
        return Double(stats.lessonStats.reduce(0) { $0 + $1.reviewCount }) / Double(stats.lessonStats.count)
    }

    private var recommendations: [LessonStat] {
        topRecommendations(stats.lessonStats)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("推荐复习").font(.headline)
                Spacer()
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(height: 28)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(stats.level.id)
                            .font(.caption).fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(levelColor(stats.level.id), in: RoundedRectangle(cornerRadius: 4))
                        Text(String(format: "均 %.1f 次", avg))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    ForEach(recommendations) { stat in
                        HStack(spacing: 0) {
                            Text(stat.lesson.displayName)
                                .font(.callout).lineLimit(1)
                            Spacer(minLength: 8)
                            Text("\(stat.reviewCount)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(stat.reviewCount == 0
                                    ? Color.orange.opacity(0.85) : Color.secondary)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(
                                    (stat.reviewCount == 0 ? Color.orange : Color.secondary).opacity(0.10),
                                    in: RoundedRectangle(cornerRadius: 4)
                                )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct LessonCountChartCard: View {
    let stats: LevelStats
    var paneHeight: CGFloat = 400
    @State private var hoveredNumber: String?
    @State private var animate = false

    // stat cards (~64) + spacing (16) + chart-card header (38) + card padding (32) + scroll padding (32)
    private var chartHeight: CGFloat { max(150, paneHeight - 214) }

    private var hoveredStat: LessonStat? {
        guard let key = hoveredNumber else { return nil }
        return stats.lessonStats.first { paddedDisplay($0.lesson.number) == key }
    }

    // ≤30 lessons → show all; >30 → show every ceil(n/30)th label.
    private var xAxisStride: Int {
        let n = stats.lessonStats.count
        guard n > 30 else { return 1 }
        return Int(ceil(Double(n) / 30.0))
    }

    private var xAxisValues: [String] {
        let sorted = stats.lessonStats.sorted { lessonNumberLess($0.lesson.number, $1.lesson.number) }
        let stride = xAxisStride
        return sorted.enumerated().compactMap { idx, stat in
            idx % stride == 0 ? paddedDisplay(stat.lesson.number) : nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("各课复习次数").font(.headline)
                Spacer()
                if let st = hoveredStat {
                    LessonTooltip(stat: st, levelId: stats.level.id)
                        .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .trailing)))
                }
            }
            .frame(height: 28)
            .animation(.easeInOut(duration: 0.1), value: hoveredNumber)

            lessonChart
                .frame(height: chartHeight)
                .animation(.spring(response: 0.55, dampingFraction: 0.8), value: animate)
        }
        .padding(16)
        .background(.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.05)) { animate = true }
        }
    }

    private var lessonChart: some View {
        Chart(stats.lessonStats) { stat in
            let key = paddedDisplay(stat.lesson.number)
            let dimmed = hoveredNumber != nil && hoveredNumber != key
            let barStyle: AnyShapeStyle = stat.reviewCount == 0
                ? AnyShapeStyle(Color.gray.opacity(dimmed ? 0.1 : 0.22))
                : AnyShapeStyle(levelColor(stats.level.id).opacity(dimmed ? 0.25 : 1.0).gradient)
            let yVal = animate ? stat.reviewCount : 0
            BarMark(x: .value("课程", key), y: .value("次数", yVal))
                .foregroundStyle(barStyle)
                .cornerRadius(4)
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) {
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                AxisValueLabel().font(.caption2)
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3, dash: [3]))
                if let key = value.as(String.self), xAxisValues.contains(key) {
                    AxisValueLabel(orientation: .verticalReversed).font(.system(size: 10))
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Color.clear.contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let loc):
                            let frame = geo[proxy.plotFrame!]
                            let x = loc.x - frame.origin.x
                            withAnimation(.easeInOut(duration: 0.1)) {
                                hoveredNumber = proxy.value(atX: x, as: String.self)
                            }
                        case .ended:
                            withAnimation(.easeInOut(duration: 0.1)) { hoveredNumber = nil }
                        }
                    }
            }
        }
    }
}

private struct LessonTooltip: View {
    let stat: LessonStat
    let levelId: String
    var body: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(stat.reviewCount > 0 ? levelColor(levelId) : Color.gray.opacity(0.5))
                .frame(width: 8, height: 8)
            Text(stat.lesson.displayName)
                .font(.caption).fontWeight(.medium)
                .lineLimit(1)
            Text("·").foregroundStyle(.secondary)
            Text(stat.reviewCount == 0 ? "未复习" : "复习 \(stat.reviewCount) 次")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(.secondary.opacity(0.1), in: Capsule())
    }
}

// MARK: - Period stat card (tappable, cycles day → week → month)

struct PeriodStatCard: View {
    let value: Int
    let color: Color
    @Binding var period: StatPeriod
    @State private var hovered = false

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .contentTransition(.numericText())

            HStack(spacing: 4) {
                Text("\(period.label)复习")
                    .font(.caption).foregroundStyle(.secondary)
                Image(systemName: "chevron.right.2")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(hovered ? color.opacity(0.8) : Color.secondary.opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(color.opacity(hovered ? 0.22 : 0.14))
                RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.28), lineWidth: 1)
            }
        )
        .scaleEffect(hovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.12), value: hovered)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) { period = period.next }
        }
        .onHover { hovered = $0 }
        .help("点击切换：今日 / 本周 / 本月")
    }
}

// MARK: - Period coverage card (tappable, cycles day → week → month)

struct PeriodCoverageCard: View {
    let pct: Double
    let color: Color
    @Binding var period: StatPeriod
    @State private var hovered = false

    var body: some View {
        VStack(spacing: 4) {
            Text(String(format: "%.0f%%", pct * 100))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .contentTransition(.numericText())

            HStack(spacing: 4) {
                Text("\(period.label)覆盖率")
                    .font(.caption).foregroundStyle(.secondary)
                Image(systemName: "chevron.right.2")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(hovered ? color.opacity(0.8) : Color.secondary.opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(color.opacity(hovered ? 0.22 : 0.14))
                RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.28), lineWidth: 1)
            }
        )
        .scaleEffect(hovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.12), value: hovered)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) { period = period.next }
        }
        .onHover { hovered = $0 }
        .help("点击切换：今日 / 本周 / 本月")
    }
}

// MARK: - Shared stat card

struct StatCard: View {
    let title: String; let value: String; let color: Color
    init(_ title: String, _ value: String, _ color: Color) {
        self.title = title; self.value = value; self.color = color
    }
    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.14))
                RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.28), lineWidth: 1)
            }
        )
    }
}
