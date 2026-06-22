import SwiftUI

struct LogView: View {
    @Environment(DataStore.self) private var store
    let defaultLevelId: String
    var scrollToDate: Binding<Date?> = .constant(nil)
    @State private var editingSession: ReviewSession?
    @State private var pendingClearGroup: (key: String, ids: [UUID])?
    @State private var listRefreshID = 0
    @State private var showAdd = false
    @State private var addHovered = false
    @State private var noLogDateLabel = ""
    @State private var showNoLogAlert = false
    @State private var highlightedSessionId: UUID? = nil

    private var grouped: [(key: String, sessions: [ReviewSession])] {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy年MM月"
        let existingLevelIds = Set(store.levels.map(\.id))
        let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        // 只显示最近一年且至少有一个 item 对应现有 tab 的 session
        let visible = store.sessions.compactMap { session -> ReviewSession? in
            guard session.date >= oneYearAgo else { return nil }
            let filtered = session.items.filter { existingLevelIds.contains($0.levelId) }
            guard !filtered.isEmpty else { return nil }
            var copy = session
            copy.items = filtered
            return copy
        }
        let dict = Dictionary(grouping: visible) { fmt.string(from: $0.date) }
        return dict.map { (key: $0.key, sessions: $0.value) }
                   .sorted { $0.key > $1.key }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "book.pages")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                    Text("复习日志")
                        .font(.headline)
                }
                Spacer()
                Text("\(grouped.flatMap(\.sessions).count) 条记录（近一年）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.secondary.opacity(0.1), in: Capsule())
                Button { showAdd = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(addHovered ? Color.accentColor : Color.accentColor.opacity(0.7))
                        .scaleEffect(addHovered ? 1.12 : 1.0)
                        .animation(.easeInOut(duration: 0.12), value: addHovered)
                }
                .buttonStyle(.plain)
                .onHover { addHovered = $0 }
                .help("添加复习记录 (⌘N)")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.accentColor.opacity(0.06))

            Divider()

            if store.sessions.isEmpty {
                ContentUnavailableView(
                    "暂无复习记录",
                    systemImage: "book.closed",
                    description: Text("点击「添加」开始记录第一次复习")
                )
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(grouped, id: \.key) { group in
                            Section {
                                ForEach(group.sessions) { session in
                                    SessionRow(session: session,
                                               isHighlighted: highlightedSessionId == session.id) {
                                        editingSession = session
                                    } onDelete: {
                                        store.deleteSession(session.id)
                                    }
                                    .id(session.id)
                                }
                            } header: {
                                MonthSectionHeader(title: group.key, count: group.sessions.count) {
                                    pendingClearGroup = (group.key, group.sessions.map(\.id))
                                }
                            }
                        }
                    }
                    .id(listRefreshID)
                    .listStyle(.inset)
                    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                        listRefreshID += 1
                    }
                    .onChange(of: store.levels.count) { _, _ in
                        listRefreshID += 1
                    }
                    .onChange(of: scrollToDate.wrappedValue) { _, date in
                        guard let date else { return }
                        scrollToDate.wrappedValue = nil
                        let cal = Calendar.current
                        if let session = store.sessions.first(where: { cal.isDate($0.date, inSameDayAs: date) }) {
                            withAnimation(.easeIn(duration: 0.1)) { highlightedSessionId = session.id }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                withAnimation { proxy.scrollTo(session.id, anchor: .center) }
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                                withAnimation(.easeOut(duration: 1.2)) { highlightedSessionId = nil }
                            }
                        } else {
                            let fmt = DateFormatter()
                            fmt.locale = Locale(identifier: "zh_CN")
                            fmt.dateFormat = "MM月dd日"
                            noLogDateLabel = fmt.string(from: date)
                            showNoLogAlert = true
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showAdd) { AddSessionView(defaultLevelId: defaultLevelId) }
        .sheet(item: $editingSession) { session in
            AddSessionView(existing: session, defaultLevelId: defaultLevelId)
        }
        .alert("\(noLogDateLabel) 无复习记录", isPresented: $showNoLogAlert) {
            Button("好") { }
        } message: {
            Text("这一天没有复习记录，可点击「+」手动添加。")
        }
        .keyboardShortcut("n", modifiers: .command)
        .confirmationDialog(
            "清空 \(pendingClearGroup?.key ?? "") 的全部记录？",
            isPresented: Binding(
                get: { pendingClearGroup != nil },
                set: { if !$0 { pendingClearGroup = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除 \(pendingClearGroup?.ids.count ?? 0) 条记录", role: .destructive) {
                if let g = pendingClearGroup {
                    store.deleteSessions(Set(g.ids))
                }
                pendingClearGroup = nil
            }
        } message: {
            Text("该操作不可撤销，本月所有复习记录将被永久删除。")
        }
    }
}

private struct MonthSectionHeader: View {
    let title: String
    let count: Int
    let onClear: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor)
                .frame(width: 3, height: 16)
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.primary)
            Spacer()
            Button { onClear() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.system(size: 9, weight: .semibold))
                    Text("清空本月")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(hovered ? .white : .red.opacity(0.65))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(
                    hovered ? AnyShapeStyle(Color.red.opacity(0.75)) : AnyShapeStyle(Color.red.opacity(0.08)),
                    in: RoundedRectangle(cornerRadius: 5)
                )
                .scaleEffect(hovered ? 1.04 : 1.0)
                .animation(.easeInOut(duration: 0.12), value: hovered)
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 }
        }
    }
}

struct SessionRow: View {
    @Environment(DataStore.self) private var store
    let session: ReviewSession
    var isHighlighted: Bool = false
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var editHovered = false
    @State private var trashHovered = false
    @State private var showDeleteConfirm = false

    private var dateLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MM月dd日  EEEE"
        f.locale = Locale(identifier: "zh_CN")
        return f.string(from: session.date)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(dateLabel).font(.headline)
                    Text("\(session.items.reduce(0) { $0 + $1.lessonIds.count }) 课")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(.secondary.opacity(0.1), in: Capsule())
                    Spacer()
                    Button { onEdit() } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(editHovered ? .white : Color.accentColor.opacity(0.7))
                            .frame(width: 28, height: 28)
                            .background(
                                editHovered ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.accentColor.opacity(0.08)),
                                in: RoundedRectangle(cornerRadius: 7)
                            )
                            .scaleEffect(editHovered ? 1.08 : 1.0)
                            .animation(.easeInOut(duration: 0.12), value: editHovered)
                    }
                    .buttonStyle(.plain)
                    .onHover { editHovered = $0 }
                    Button { showDeleteConfirm = true } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(trashHovered ? .white : .red.opacity(0.6))
                            .frame(width: 28, height: 28)
                            .background(
                                trashHovered ? AnyShapeStyle(Color.red) : AnyShapeStyle(Color.red.opacity(0.07)),
                                in: RoundedRectangle(cornerRadius: 7)
                            )
                            .scaleEffect(trashHovered ? 1.08 : 1.0)
                            .animation(.easeInOut(duration: 0.12), value: trashHovered)
                    }
                    .buttonStyle(.plain)
                    .onHover { trashHovered = $0 }
                }

                ForEach(session.items.sorted { a, b in
                    let ia = store.levels.firstIndex { $0.id == a.levelId } ?? Int.max
                    let ib = store.levels.firstIndex { $0.id == b.levelId } ?? Int.max
                    return ia < ib
                }) { item in
                    HStack(alignment: .top, spacing: 6) {
                        Text(item.levelId)
                            .font(.caption).fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(levelColor(index: store.levels.firstIndex(where: { $0.id == item.levelId }) ?? 0), in: RoundedRectangle(cornerRadius: 4))

                        let lessons = item.lessonIds
                            .compactMap { lid in store.levels.flatMap(\.lessons).first { $0.id == lid } }
                            .sorted { lessonNumberLess($0.number, $1.number) }
                        Text(lessons.map(\.displayName).joined(separator: "  "))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }

        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(isHighlighted ? 0.18 : 0))
        )
        .contentShape(Rectangle())
        .contextMenu {
            Button("编辑") { onEdit() }
            Divider()
            Button("删除", role: .destructive) { showDeleteConfirm = true }
        }
        .confirmationDialog("确定要删除这条复习记录吗？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) { onDelete() }
        }
    }
}
