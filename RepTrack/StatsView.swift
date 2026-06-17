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
            StatCard("总课数", "\(totalLessons)", Color(red: 0.10, green: 0.48, blue: 1.00), icon: "books.vertical.fill")
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
                     Color(red: 0.20, green: 0.65, blue: 0.30), icon: "checkmark.seal.fill")
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
    @State private var cardTab = 1   // 0=雷达图 1=热力图
    @State private var tabHovered: Int? = nil

    private var chartHeight: CGFloat { paneHeight > 0 ? max(150, paneHeight - 214) : 280 }
    private var hoveredItem: LevelCoverage? { coverages.first { $0.id == hoveredId } }
    private var axisCount: Int { max(coverages.count, 3) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(cardTab == 0 ? "综合实力" : "活跃记录")
                    .font(.headline)
                    .animation(.easeInOut(duration: 0.15), value: cardTab)
                if cardTab == 0 {
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
                }
                Spacer()
                if cardTab == 0, let lv = hoveredItem {
                    CoverageTooltip(lv: lv)
                        .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .trailing)))
                }
                // Tab 切换：雷达图 / 热力图
                HStack(spacing: 2) {
                    ForEach([(0, "chart.xyaxis.line"), (1, "square.grid.3x3.fill")], id: \.0) { idx, icon in
                        let isSelected = cardTab == idx
                        let isHovered  = tabHovered == idx
                        Button {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) { cardTab = idx }
                        } label: {
                            Image(systemName: icon)
                                .font(.system(size: 11))
                                .foregroundStyle(isSelected ? Color.primary : (isHovered ? Color.primary.opacity(0.7) : Color.secondary.opacity(0.4)))
                                .frame(width: 26, height: 22)
                                .background(isSelected ? Color.primary.opacity(0.12) : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                .scaleEffect(isHovered && !isSelected ? 1.08 : 1.0)
                        }
                        .buttonStyle(.plain)
                        .onHover { tabHovered = $0 ? idx : nil }
                        .animation(.easeInOut(duration: 0.1), value: isHovered)
                    }
                }
            }
            .frame(height: 28)
            .animation(.easeInOut(duration: 0.12), value: hoveredId)

            if cardTab == 0 {
                GeometryReader { geo in radarContent(in: geo.size) }
                    .frame(height: chartHeight)
            } else {
                ActivityHeatmap()
                    .frame(maxWidth: .infinity)
                    .frame(height: chartHeight)
            }
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

    private var recentByLevel: [LevelRec] {
        store.levels.compactMap { level in
            guard !level.lessons.isEmpty else { return nil }
            let stats = level.lessons.map { lesson in
                LessonStat(lesson: lesson,
                           reviewCount: store.reviewCount(for: lesson.id),
                           lastReviewed: store.lastReviewed(lessonId: lesson.id))
            }
            let recent = Array(stats
                .filter { $0.lastReviewed != nil }
                .sorted { ($0.lastReviewed ?? .distantPast) > ($1.lastReviewed ?? .distantPast) }
                .prefix(5))
            guard !recent.isEmpty else { return nil }
            let avg = Double(stats.reduce(0) { $0 + $1.reviewCount }) / Double(stats.count)
            return LevelRec(level: level, avg: avg, lessons: recent)
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

                        if !recentByLevel.isEmpty {
                            HStack(spacing: 4) {
                                Rectangle().frame(height: 0.5).foregroundStyle(Color.accentColor.opacity(0.3))
                                Text("最近复习")
                                    .font(.caption2).foregroundStyle(Color.accentColor.opacity(0.7))
                                    .fixedSize()
                                Rectangle().frame(height: 0.5).foregroundStyle(Color.accentColor.opacity(0.3))
                            }
                            .padding(.top, 2)

                            ForEach(recentByLevel, id: \.level.id) { rec in
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 6) {
                                        Text(rec.level.id)
                                            .font(.caption).fontWeight(.semibold)
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(levelColor(rec.level.id), in: RoundedRectangle(cornerRadius: 4))
                                    }
                                    ForEach(rec.lessons) { stat in
                                        HStack(spacing: 0) {
                                            Text(stat.lesson.displayName)
                                                .font(.callout).lineLimit(1)
                                            Spacer(minLength: 8)
                                            Text("\(stat.reviewCount)")
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundStyle(Color.secondary)
                                                .padding(.horizontal, 5).padding(.vertical, 2)
                                                .background(Color.secondary.opacity(0.10),
                                                            in: RoundedRectangle(cornerRadius: 4))
                                        }
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
            StatCard("总课数", "\(stats.totalLessons)", Color(red: 0.10, green: 0.48, blue: 1.00), icon: "books.vertical.fill")
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
                     Color(red: 0.20, green: 0.65, blue: 0.30), icon: "checkmark.seal.fill")
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
    private var recentlyReviewed: [LessonStat] {
        Array(stats.lessonStats
            .filter { $0.lastReviewed != nil }
            .sorted { ($0.lastReviewed ?? .distantPast) > ($1.lastReviewed ?? .distantPast) }
            .prefix(5))
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

                    // 最近复习区块
                    if !recentlyReviewed.isEmpty {
                        HStack(spacing: 4) {
                            Rectangle().frame(height: 0.5).foregroundStyle(Color.accentColor.opacity(0.3))
                            Text("最近复习")
                                .font(.caption2).foregroundStyle(Color.accentColor.opacity(0.7))
                                .fixedSize()
                            Rectangle().frame(height: 0.5).foregroundStyle(Color.accentColor.opacity(0.3))
                        }
                        .padding(.top, 2)

                        ForEach(recentlyReviewed) { stat in
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
        ZStack(alignment: .bottomTrailing) {
            // 装饰性大数字
            Text("\(value)")
                .font(.system(size: 56, weight: .black, design: .rounded))
                .foregroundStyle(color.opacity(0.08))
                .offset(x: 8, y: 8)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "arrow.2.squarepath")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color.opacity(0.7))
                Spacer()
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(
                    colors: [color.opacity(hovered ? 0.28 : 0.18), color.opacity(hovered ? 0.14 : 0.08)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(color.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: color.opacity(hovered ? 0.18 : 0.08), radius: hovered ? 8 : 4, x: 0, y: 2)
        .scaleEffect(hovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.12), value: hovered)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { period = period.next } }
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
        ZStack(alignment: .bottomTrailing) {
            Text(String(format: "%.0f%%", pct * 100))
                .font(.system(size: 56, weight: .black, design: .rounded))
                .foregroundStyle(color.opacity(0.08))
                .offset(x: 8, y: 8)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color.opacity(0.7))
                Spacer()
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(
                    colors: [color.opacity(hovered ? 0.28 : 0.18), color.opacity(hovered ? 0.14 : 0.08)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(color.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: color.opacity(hovered ? 0.18 : 0.08), radius: hovered ? 8 : 4, x: 0, y: 2)
        .scaleEffect(hovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.12), value: hovered)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { period = period.next } }
        .onHover { hovered = $0 }
        .help("点击切换周期")
    }
}

// MARK: - Shared stat card

struct StatCard: View {
    let title: String; let value: String; let color: Color
    let icon: String
    init(_ title: String, _ value: String, _ color: Color, icon: String = "number") {
        self.title = title; self.value = value; self.color = color; self.icon = icon
    }
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Text(value)
                .font(.system(size: 56, weight: .black, design: .rounded))
                .foregroundStyle(color.opacity(0.08))
                .offset(x: 8, y: 8)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color.opacity(0.7))
                Spacer()
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(
                    colors: [color.opacity(0.18), color.opacity(0.08)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(color.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: color.opacity(0.08), radius: 4, x: 0, y: 2)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - ReviewStatsCard

private struct ReviewStatsCard: View {
    @Environment(DataStore.self) private var store
    @Binding var statsTab: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            briefGrid
        }
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Color(NSColor.controlBackgroundColor))
                RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.07), lineWidth: 1)
            }
        )
    }

    // MARK: 活动简介 — 4 格数据
    private var briefGrid: some View {
        let sessions   = store.sessions
        let totalDays  = Set(sessions.map { Calendar.current.startOfDay(for: $0.date) }).count
        let totalItems = sessions.reduce(0) { $0 + $1.items.reduce(0) { $0 + $1.lessonIds.count } }
        let (curStreak, _) = streakStats()

        return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
            statCell(icon: "calendar.badge.checkmark", value: "\(sessions.count)", label: "总复习次数", color: .blue)
            statCell(icon: "sun.max.fill",             value: "\(totalDays)",      label: "活跃天数",  color: .orange)
            statCell(icon: "books.vertical.fill",      value: "\(totalItems)",     label: "累计课时",  color: .purple)
            statCell(icon: "flame.fill",               value: "\(curStreak)天",    label: "当前连续",  color: .red)
        }
    }

    private func statCell(icon: String, value: String, label: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13)).foregroundStyle(color)
                .frame(width: 26, height: 26).background(color.opacity(0.12)).clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.7)
                Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func streakStats() -> (current: Int, longest: Int) {
        let cal  = Calendar.current
        let days = Set(store.sessions.map { cal.startOfDay(for: $0.date) }).sorted(by: >)
        guard !days.isEmpty else { return (0, 0) }
        var current = 0
        var prev = cal.startOfDay(for: Date())
        for day in days {
            if (cal.dateComponents([.day], from: day, to: prev).day ?? 99) <= 1 { current += 1; prev = day }
            else { break }
        }
        let sorted = days.sorted()
        var longest = 1, run = 1
        for i in 1..<sorted.count {
            if cal.dateComponents([.day], from: sorted[i-1], to: sorted[i]).day == 1 { run += 1; longest = max(longest, run) }
            else { run = 1 }
        }
        return (current, max(longest, current))
    }
}

// MARK: - Activity Heatmap (综合实力 tab)

private struct ActivityHeatmap: View {
    @Environment(DataStore.self) private var store

    private static let weeks    = 26
    private static let rows     = 7
    private static let gap: CGFloat  = 3
    private static let labelH: CGFloat  = 18  // 月份行高
    private static let legendH: CGFloat = 20  // 图例行高
    private static let weekLabelW: CGFloat = 26 // 星期列宽
    // 只在第 1（Mon）、3（Wed）、5（Fri）行显示星期标签（0-indexed）
    private static let weekLabels: [Int: String] = [1: "Mon", 3: "Wed", 5: "Fri"]

    @State private var hoveredDay: Date? = nil
    @State private var hoveredPos: CGPoint = .zero

    private func tooltipLabel(for day: Date) -> String {
        let fmt = DateFormatter(); fmt.dateFormat = "MMM d"
        return fmt.string(from: day)
    }

    private var dailyCounts: [Date: Int] {
        let cal = Calendar.current
        var counts: [Date: Int] = [:]
        for s in store.sessions {
            let day = cal.startOfDay(for: s.date)
            counts[day, default: 0] += s.items.reduce(0) { $0 + $1.lessonIds.count }
        }
        return counts
    }

    private var columns: [[Date]] {
        let cal   = Calendar.current
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        comps.weekday = 2   // 周一起
        let startOfThisWeek = cal.date(from: comps)!
        let gridStart = cal.date(byAdding: .weekOfYear, value: -(Self.weeks - 1), to: startOfThisWeek)!
        let today = cal.startOfDay(for: Date())
        var cols: [[Date]] = []
        var weekStart = gridStart
        for _ in 0..<Self.weeks {
            var week: [Date] = []
            for d in 0..<7 {
                let day = cal.date(byAdding: .day, value: d, to: weekStart)!
                week.append(day <= today ? day : Date.distantFuture)
            }
            cols.append(week)
            weekStart = cal.date(byAdding: .weekOfYear, value: 1, to: weekStart)!
        }
        return cols
    }

    private func cellColor(for day: Date, counts: [Date: Int]) -> Color {
        guard day != .distantFuture else { return .clear }
        let n = counts[day] ?? 0
        if n == 0 { return Color.primary.opacity(0.08) }
        let intensity = min(Double(n) / 8.0, 1.0)
        return Color.accentColor.opacity(0.25 + intensity * 0.75)
    }

    private func monthLabels(step: CGFloat) -> [(colIndex: Int, label: String)] {
        var result: [(Int, String)] = []
        let cal = Calendar.current
        let fmt = DateFormatter(); fmt.dateFormat = "MMM"
        var lastMonth = -1
        for (i, col) in columns.enumerated() {
            let day = col.first { $0 != .distantFuture } ?? .distantFuture
            guard day != .distantFuture else { continue }
            let m = cal.component(.month, from: day)
            if m != lastMonth { result.append((i, fmt.string(from: day))); lastMonth = m }
        }
        return result
    }

    var body: some View {
        GeometryReader { geo in
            let wlw      = Self.weekLabelW
            let gridW    = geo.size.width - wlw
            let totalGapW = Self.gap * CGFloat(Self.weeks - 1)
            let totalGapH = Self.gap * CGFloat(Self.rows - 1)
            let gridH    = geo.size.height - Self.labelH - Self.legendH - Self.gap * 2
            let cellW    = (gridW - totalGapW) / CGFloat(Self.weeks)
            let cellH    = max(4, (gridH - totalGapH) / CGFloat(Self.rows))
            let cell     = min(cellW, cellH)
            let step     = cell + Self.gap
            let counts   = dailyCounts

            VStack(alignment: .leading, spacing: Self.gap) {

                // ── 月份标签行（左侧留出星期列宽）
                HStack(spacing: 0) {
                    Color.clear.frame(width: wlw, height: Self.labelH)
                    ZStack(alignment: .topLeading) {
                        Color.clear.frame(height: Self.labelH)
                        ForEach(monthLabels(step: step), id: \.colIndex) { item in
                            Text(item.label)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .offset(x: CGFloat(item.colIndex) * step)
                        }
                    }
                }

                // ── 星期标签 + 热力格
                HStack(alignment: .top, spacing: 0) {
                    // 左侧星期列
                    VStack(alignment: .trailing, spacing: Self.gap) {
                        ForEach(0..<7, id: \.self) { ri in
                            Text(Self.weekLabels[ri] ?? "")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .frame(width: wlw - 4, height: cell, alignment: .trailing)
                        }
                    }
                    .padding(.trailing, 4)

                    // 热力格区域
                    HStack(alignment: .top, spacing: Self.gap) {
                        ForEach(columns.indices, id: \.self) { ci in
                            VStack(spacing: Self.gap) {
                                ForEach(0..<7, id: \.self) { ri in
                                    let day = columns[ci][ri]
                                    RoundedRectangle(cornerRadius: max(2, cell * 0.18))
                                        .fill(cellColor(for: day, counts: counts))
                                        .frame(width: cell, height: cell)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: max(2, cell * 0.18))
                                                .stroke(hoveredDay == day && day != .distantFuture
                                                        ? Color.primary.opacity(0.5) : Color.clear,
                                                        lineWidth: 1)
                                        )
                                        .onHover { inside in
                                            hoveredDay = (inside && day != .distantFuture) ? day : nil
                                        }
                                }
                            }
                        }
                    }
                    .onContinuousHover { phase in
                        if case .active(let loc) = phase { hoveredPos = loc }
                    }
                }

                // ── 图例：Less ●●●●● More
                HStack(spacing: 4) {
                    Spacer()
                    Text("Less").font(.system(size: 9)).foregroundStyle(.secondary)
                    ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { lvl in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(lvl == 0
                                  ? Color.primary.opacity(0.08)
                                  : Color.accentColor.opacity(0.25 + lvl * 0.75))
                            .frame(width: cell, height: cell)
                    }
                    Text("More").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                .frame(height: Self.legendH)
            }
            .overlay(alignment: .topLeading) {
                if let day = hoveredDay {
                    HeatmapTooltip(label: tooltipLabel(for: day))
                        .offset(x: wlw + hoveredPos.x + 10,
                                y: (hoveredPos.y + Self.labelH - 24).clamped(to: 0...200))
                        .allowsHitTesting(false)
                        .animation(.easeInOut(duration: 0.1), value: hoveredDay)
                }
            }
        }
    }
}

private struct HeatmapTooltip: View {
    let label: String
    var body: some View {
        Text(label)
            .font(.system(size: 11))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color(NSColor.windowBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
