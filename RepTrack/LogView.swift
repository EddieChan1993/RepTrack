import SwiftUI

struct LogView: View {
    @Environment(DataStore.self) private var store
    @State private var editingSession: ReviewSession?

    private var grouped: [(key: String, sessions: [ReviewSession])] {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy年MM月"
        let dict = Dictionary(grouping: store.sessions) { fmt.string(from: $0.date) }
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
                Text("\(store.sessions.count) 条记录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.secondary.opacity(0.1), in: Capsule())
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
                List {
                    ForEach(grouped, id: \.key) { group in
                        Section(group.key) {
                            ForEach(group.sessions) { session in
                                SessionRow(session: session) {
                                    editingSession = session
                                } onDelete: {
                                    store.deleteSession(session.id)
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .sheet(item: $editingSession) { session in
            AddSessionView(existing: session)
        }
    }
}

struct SessionRow: View {
    @Environment(DataStore.self) private var store
    let session: ReviewSession
    let onEdit: () -> Void
    let onDelete: () -> Void

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
                            .background(levelColor(item.levelId), in: RoundedRectangle(cornerRadius: 4))

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
