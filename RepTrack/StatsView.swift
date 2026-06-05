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
    @State private var importHovered = false
    @State private var refreshRotation: Double = 0
    @State private var showFolderMissingAlert = false
    @State private var missingPaths: [String] = []

    private var tabs: [String] { ["全部"] + store.levels.map(\.id) }

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

    private var canRefresh: Bool {
        if selectedTab == "全部" { return store.levels.contains { store.sourceURL(for: $0.id) != nil } }
        return true // 单个 tab 始终显示，没有绑定文件夹时点击弹选择器
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

                Divider().frame(height: 20)
                Button {
                    openImportPanel()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(importHovered ? Color.primary : .secondary)
                        .frame(width: 36, height: 44)
                        .background(importHovered ? Color.primary.opacity(0.06) : .clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { importHovered = $0 }
                .help("导入新的课程等级文件夹")

                if canRefresh {
                    Divider().frame(height: 20)
                    Button {
                        guard !isRefreshing else { return }

                        // 单个 tab 且没有绑定文件夹 → 弹选择器让用户绑定
                        if selectedTab != "全部", store.sourceURL(for: selectedTab) == nil {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            panel.allowsMultipleSelection = false
                            panel.prompt = "选择文件夹"
                            panel.message = "为「\(selectedTab)」选择对应的课程文件夹"
                            if panel.runModal() == .OK, let url = panel.url {
                                store.importLevelFolders([url])
                            }
                            return
                        }

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
                        let hasSource = selectedTab == "全部" || store.sourceURL(for: selectedTab) != nil
                        Image(systemName: hasSource ? "arrow.clockwise" : "folder.badge.plus")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(refreshHovered ? Color.primary : .secondary)
                            .rotationEffect(.degrees(hasSource ? refreshRotation : 0))
                            .frame(width: 44, height: 44)
                            .background(refreshHovered ? Color.primary.opacity(0.06) : .clear)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { refreshHovered = $0 }
                    .help(selectedTab == "全部"
                          ? "重新扫描所有等级文件夹"
                          : (store.sourceURL(for: selectedTab) != nil
                             ? "重新扫描 \(selectedTab) 文件夹"
                             : "为 \(selectedTab) 绑定课程文件夹"))
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
    let id: String
    let total: Int        // 总课数
    let reviewed: Int     // 至少复习过1次的课数
    let totalReviews: Int // 累计复习次数
    let minReviews: Int          // 最少被复习的课的次数
    let cappedTotalReviews: Int  // Σ min(N, 每课次数)，每课贡献上限N
    let tierStep: Int            // 升阶所需每课最低次数
    // 覆盖率得分(0-50)：reviewed / total × 50
    var coverageScore: Double { total > 0 ? Double(reviewed) / Double(total) * 50 : 0 }
    // 当前阶梯信息（基于最薄弱课时）
    var tierFloor: Int { (minReviews / tierStep) * tierStep }
    var tierCeil: Int { tierFloor + tierStep }
    var tierNumber: Int { tierFloor / tierStep + 1 }
    // 频次得分(0-50)：Σmin(N,课次) / total / N * 50，满分=每课都达到N次
    var freqScore: Double {
        guard total > 0, tierStep > 0 else { return 0 }
        return Double(cappedTotalReviews) / Double(total) / Double(tierStep) * 50
    }
    // 雷达轴值 = 总分(0-100)
    var pct: Double { coverageScore + freqScore }
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
            let counts = lv.lessons.map { store.reviewCount(for: $0.id) }
            let totalRev = counts.reduce(0, +)
            let rev = counts.filter { $0 > 0 }.count
            let minRev = counts.min() ?? 0
            let capped = counts.reduce(0) { $0 + min($1, lv.tierStep) }
            return LevelCoverage(id: lv.id, total: lv.lessons.count,
                                 reviewed: rev, totalReviews: totalRev,
                                 minReviews: minRev, cappedTotalReviews: capped,
                                 tierStep: lv.tierStep)
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            StatCard("总课数", "\(totalLessons)", Color(red: 0.10, green: 0.48, blue: 1.00))
            PeriodStatCard(
                value: store.totalReviewCount(period: reviewPeriod),
                color: Color(red: 0.00, green: 0.72, blue: 0.72),
                period: $reviewPeriod
            )
            PeriodCoverageCard(
                pct: coverage,
                color: Color(red: 0.62, green: 0.15, blue: 0.90),
                period: $coveragePeriod
            )
            StatCard("累计复习", "\(store.totalReviewCount(period: .total))",
                     Color(red: 0.20, green: 0.65, blue: 0.30))
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

// MARK: - Radar Chart Card (五边形战士风格)

struct CoverageChartCard: View {
    let coverages: [LevelCoverage]
    var paneHeight: CGFloat = 400
    @State private var hoveredId: String?
    @State private var progress: CGFloat = 0
    @State private var showingInfo = false

    private var chartHeight: CGFloat { paneHeight > 0 ? max(150, paneHeight - 214) : 280 }
    private var hoveredItem: LevelCoverage? { coverages.first { $0.id == hoveredId } }
    private var axisCount: Int { max(coverages.count, 3) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("综合实力").font(.headline)
                Button {
                    showingInfo.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingInfo, arrowEdge: .bottom) {
                    RadarInfoPopover(coverages: coverages)
                }
                Spacer()
                if let lv = hoveredItem {
                    CoverageTooltip(lv: lv)
                        .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .trailing)))
                }
            }
            .frame(height: 28)
            .animation(.easeInOut(duration: 0.12), value: hoveredId)

            GeometryReader { geo in radarContent(in: geo.size) }
                .frame(height: chartHeight)
        }
        .padding(16)
        .background(.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.78).delay(0.08)) { progress = 1 }
        }
    }

    private func radarAngle(i: Int, n: Int) -> Double {
        let offset: Double = -Double.pi / 2
        let step: Double = 2 * Double.pi / Double(n)
        return offset + step * Double(i)
    }

    @ViewBuilder
    private func radarContent(in size: CGSize) -> some View {
        let cx   = size.width  / 2
        let cy   = size.height / 2
        let maxR = min(size.width, size.height) * 0.40
        let n    = axisCount
        ZStack {
            radarGrid(n: n)
            radarAxes(n: n)
            radarData(n: n)
            radarLabels(cx: cx, cy: cy, maxR: maxR, n: n)
            radarPctHints(cx: cx, cy: cy, maxR: maxR, n: n)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            handleHover(phase, cx: cx, cy: cy, maxR: maxR, n: n)
        }
    }

    @ViewBuilder
    private func radarGrid(n: Int) -> some View {
        let fracs: [CGFloat] = [0.25, 0.5, 0.75, 1.0]
        ForEach(fracs, id: \.self) { frac in
            let isOuter = frac == 1.0
            RadarGridShape(n: n, fraction: frac)
                .stroke(
                    Color.secondary.opacity(isOuter ? 0.28 : 0.10),
                    style: StrokeStyle(lineWidth: isOuter ? 1 : 0.5,
                                       dash: isOuter ? [] : [4, 3])
                )
        }
    }

    @ViewBuilder
    private func radarAxes(n: Int) -> some View {
        ForEach(0..<n, id: \.self) { i in
            RadarAxisShape(i: i, n: n)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private func radarData(n: Int) -> some View {
        if !coverages.isEmpty {
            let slice = Array(coverages.prefix(n))
            RadarDataShape(coverages: slice, n: n, progress: progress)
                .fill(LinearGradient(
                    colors: [Color.accentColor.opacity(0.38), Color.accentColor.opacity(0.1)],
                    startPoint: .center, endPoint: .bottom
                ))
            RadarDataShape(coverages: slice, n: n, progress: progress)
                .stroke(Color.accentColor.opacity(0.85), lineWidth: 2)
        }
    }

    @ViewBuilder
    private func radarLabels(cx: CGFloat, cy: CGFloat, maxR: CGFloat, n: Int) -> some View {
        ForEach(Array(coverages.prefix(n).enumerated()), id: \.offset) { i, cov in
            let a     = radarAngle(i: i, n: n)
            let pct   = CGFloat(cov.pct) / 100.0 * progress
            let color = levelColor(cov.id)
            Circle()
                .fill(color)
                .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.5))
                .frame(width: 9, height: 9)
                .position(x: cx + maxR * pct * cos(a),
                          y: cy + maxR * pct * sin(a))
            VStack(spacing: 2) {
                Text(cov.id)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                Text(String(format: "%.0f%%", cov.pct))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .position(x: cx + (maxR + 36) * cos(a),
                      y: cy + (maxR + 22) * sin(a))
        }
    }

    @ViewBuilder
    private func radarPctHints(cx: CGFloat, cy: CGFloat, maxR: CGFloat, n: Int) -> some View {
        let a0 = radarAngle(i: 0, n: n)
        Text("50%")
            .font(.system(size: 8))
            .foregroundStyle(Color.secondary.opacity(0.35))
            .position(x: cx + maxR * 0.5 * cos(a0) + 10,
                      y: cy + maxR * 0.5 * sin(a0))
        Text("100%")
            .font(.system(size: 8))
            .foregroundStyle(Color.secondary.opacity(0.35))
            .position(x: cx + maxR * cos(a0) + 12,
                      y: cy + maxR * sin(a0))
    }

    private func handleHover(_ phase: HoverPhase, cx: CGFloat, cy: CGFloat, maxR: CGFloat, n: Int) {
        if case .active(let loc) = phase {
            func radarPoint(offset: Int, pct: Double) -> CGPoint {
                let a = radarAngle(i: offset, n: n)
                let r = maxR * CGFloat(pct) / 100
                return CGPoint(x: cx + r * cos(a), y: cy + r * sin(a))
            }
            let closest = coverages.prefix(n).enumerated().min { a, b in
                let pa = radarPoint(offset: a.offset, pct: a.element.pct)
                let pb = radarPoint(offset: b.offset, pct: b.element.pct)
                return hypot(loc.x - pa.x, loc.y - pa.y) < hypot(loc.x - pb.x, loc.y - pb.y)
            }
            withAnimation(.easeInOut(duration: 0.1)) { hoveredId = closest?.element.id }
        } else {
            withAnimation(.easeInOut(duration: 0.1)) { hoveredId = nil }
        }
    }
}

// 网格多边形
private struct RadarGridShape: Shape {
    let n: Int; let fraction: CGFloat
    func path(in rect: CGRect) -> Path {
        let cx = rect.width / 2, cy = rect.height / 2
        let r  = min(rect.width, rect.height) * 0.40 * fraction
        var p  = Path()
        for i in 0..<n {
            let a  = -Double.pi/2 + 2*Double.pi*Double(i)/Double(n)
            let pt = CGPoint(x: cx + r * cos(a), y: cy + r * sin(a))
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath(); return p
    }
}

// 轴线
private struct RadarAxisShape: Shape {
    let i: Int; let n: Int
    func path(in rect: CGRect) -> Path {
        let cx = rect.width / 2, cy = rect.height / 2
        let r  = min(rect.width, rect.height) * 0.40
        let a  = -Double.pi/2 + 2*Double.pi*Double(i)/Double(n)
        var p  = Path()
        p.move(to: CGPoint(x: cx, y: cy))
        p.addLine(to: CGPoint(x: cx + r * cos(a), y: cy + r * sin(a)))
        return p
    }
}

// 数据多边形（可动画）
private struct RadarDataShape: Shape {
    let coverages: [LevelCoverage]
    let n: Int
    var progress: CGFloat
    var animatableData: CGFloat { get { progress } set { progress = newValue } }

    func path(in rect: CGRect) -> Path {
        let cx = rect.width / 2, cy = rect.height / 2
        let maxR = min(rect.width, rect.height) * 0.40
        var p = Path()
        for (i, cov) in coverages.enumerated() {
            let a  = -Double.pi/2 + 2*Double.pi*Double(i)/Double(n)
            let r  = maxR * CGFloat(cov.pct) / 100.0 * progress
            let pt = CGPoint(x: cx + r * cos(a), y: cy + r * sin(a))
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath(); return p
    }
}

private struct RadarInfoPopover: View {
    let coverages: [LevelCoverage]
    @Environment(DataStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("综合实力雷达图", systemImage: "chart.xyaxis.line")
                .font(.headline)

            Text("每条轴代表一个学习内容，**满分100分**，两个维度各占50分：")
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                ScoreDimRow(icon: "checkmark.circle.fill", color: .blue,
                            title: "覆盖率（0–50分）",
                            desc: "已复习过至少1次的课 ÷ 总课数 × 50")
                ScoreDimRow(icon: "repeat.circle.fill", color: .orange,
                            title: "复习深度（0–50分）",
                            desc: "每节课都达到 N 次才能升阶，以最薄弱那节课的进度计分")
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("各内容当前阶段").font(.callout).fontWeight(.medium)
                ForEach(coverages) { cov in
                    TierRow(cov: cov, store: store)
                }
            }

            Divider()

            Label("鼠标悬停可查看各内容的具体数值", systemImage: "cursorarrow.motionlines")
                .font(.callout).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 310)
    }
}

private struct TierRow: View {
    let cov: LevelCoverage
    let store: DataStore
    @State private var editing = false
    @State private var stepInput = ""

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(levelColor(cov.id)).frame(width: 7, height: 7)
            Text(cov.id).font(.caption).fontWeight(.medium)
            Spacer()
            Text("第\(cov.tierNumber)阶  \(cov.minReviews)/\(cov.tierCeil)次")
                .font(.caption).foregroundStyle(.secondary)
            if editing {
                TextField("N", text: $stepInput)
                    .frame(width: 36)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onSubmit { commitStep() }
                Button("✓") { commitStep() }
                    .buttonStyle(.plain).font(.caption).foregroundStyle(Color.accentColor)
            } else {
                Button("N=\(cov.tierStep)") { stepInput = "\(cov.tierStep)"; editing = true }
                    .buttonStyle(.plain).font(.caption).foregroundStyle(Color.accentColor)
            }
        }
    }

    private func commitStep() {
        if let n = Int(stepInput), n > 0,
           let idx = store.levels.firstIndex(where: { $0.id == cov.id }) {
            store.levels[idx].tierStep = n
            store.save()
        }
        editing = false
    }
}

private struct ScoreDimRow: View {
    let icon: String; let color: Color; let title: String; let desc: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout).fontWeight(.medium)
                Text(desc).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct CoverageTooltip: View {
    let lv: LevelCoverage
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(levelColor(lv.id)).frame(width: 7, height: 7)
            Text(lv.id).font(.caption).fontWeight(.medium)
            Text("·").foregroundStyle(.secondary)
            Text("\(String(format: "%.0f", lv.pct))分")
                .font(.caption).fontWeight(.medium).foregroundStyle(.primary)
            Text("覆\(lv.reviewed)/\(lv.total)")
                .font(.caption).foregroundStyle(.secondary)
            Text("均\(String(format: "%.1f", lv.total > 0 ? Double(lv.totalReviews)/Double(lv.total) : 0))/\(lv.tierStep)次")
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
                value: store.totalReviewCount(levelId: stats.level.id, period: reviewPeriod),
                color: Color(red: 0.00, green: 0.72, blue: 0.72),
                period: $reviewPeriod
            )
            PeriodCoverageCard(
                pct: coverage,
                color: Color(red: 0.62, green: 0.15, blue: 0.90),
                period: $coveragePeriod
            )
            StatCard("累计复习", "\(store.totalReviewCount(levelId: stats.level.id, period: .total))",
                     Color(red: 0.20, green: 0.65, blue: 0.30))
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
    private var recommendations: [LessonStat] { topRecommendations(stats.lessonStats) }
    private var unreviewed: [LessonStat] {
        Array(stats.lessonStats
            .filter { $0.reviewCount == 0 }
            .sorted { lessonNumberLess($0.lesson.number, $1.lesson.number) }
            .prefix(4))
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
                    // 等级标签 + 均次
                    HStack(spacing: 6) {
                        Text(stats.level.id)
                            .font(.caption).fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(levelColor(stats.level.id), in: RoundedRectangle(cornerRadius: 4))
                        Text(String(format: "均 %.1f 次", avg))
                            .font(.caption2).foregroundStyle(.secondary)
                    }

                    // 推荐复习（已复习但频次低）
                    ForEach(recommendations) { stat in
                        RecommendRow(stat: stat)
                    }

                    // 未复习区块
                    if !unreviewed.isEmpty {
                        HStack(spacing: 4) {
                            Rectangle().frame(height: 0.5).foregroundStyle(Color.orange.opacity(0.3))
                            Text("未复习 \(unreviewed.count) 课")
                                .font(.caption2).foregroundStyle(Color.orange.opacity(0.7))
                                .fixedSize()
                            Rectangle().frame(height: 0.5).foregroundStyle(Color.orange.opacity(0.3))
                        }
                        .padding(.top, 2)

                        ForEach(unreviewed) { stat in
                            RecommendRow(stat: stat)
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

private struct RecommendRow: View {
    let stat: LessonStat
    var body: some View {
        HStack(spacing: 0) {
            Text(stat.lesson.displayName)
                .font(.callout).lineLimit(1)
            Spacer(minLength: 8)
            Text(stat.reviewCount == 0 ? "未" : "\(stat.reviewCount)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(stat.reviewCount == 0 ? Color.orange.opacity(0.85) : Color.secondary)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(
                    (stat.reviewCount == 0 ? Color.orange : Color.secondary).opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 4)
                )
        }
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
        .help("点击切换周期")
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
        .help("点击切换周期")
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
