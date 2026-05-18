import SwiftUI

struct ManageLevelsView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var newLevelId = ""
    @State private var expandedLevel = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("管理课程").font(.title2).fontWeight(.semibold)
                Spacer()
                Button("完成") { dismiss() }.buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 12)

            Divider()

            List {
                ForEach(store.levels) { level in
                    LevelSection(level: level, isExpanded: expandedLevel == level.id) {
                        expandedLevel = expandedLevel == level.id ? "" : level.id
                    }
                }
                .onDelete { idx in
                    idx.forEach { store.deleteLevel(store.levels[$0].id) }
                }

                Section("添加等级") {
                    HStack {
                        TextField("等级名（如 S4-XK）", text: $newLevelId)
                            .onSubmit { addLevel() }
                        Button("添加") { addLevel() }
                            .disabled(newLevelId.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .listStyle(.inset)
        }
        .frame(width: 480, height: 520)
    }

    private func addLevel() {
        let id = newLevelId.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else { return }
        store.addLevel(id: id)
        newLevelId = ""
        expandedLevel = id
    }
}

struct LevelSection: View {
    @Environment(DataStore.self) private var store
    let level: Level
    let isExpanded: Bool
    let toggle: () -> Void

    @State private var newNumber = ""
    @State private var newTitle = ""
    @State private var editingLesson: Lesson?
    @State private var editTitle = ""

    var body: some View {
        DisclosureGroup(isExpanded: Binding(get: { isExpanded }, set: { _ in toggle() })) {
            ForEach(level.lessons) { lesson in
                HStack {
                    if editingLesson?.id == lesson.id {
                        TextField("课程名称", text: $editTitle)
                            .onSubmit { commitEdit(lesson: lesson) }
                        Button("保存") { commitEdit(lesson: lesson) }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                        Button("取消") { editingLesson = nil }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    } else {
                        Text(lesson.number).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
                        Text(lesson.title.isEmpty ? "（未命名）" : lesson.title)
                            .foregroundStyle(lesson.title.isEmpty ? .tertiary : .primary)
                        Spacer()
                        let count = store.reviewCount(for: lesson.id)
                        if count > 0 {
                            Text("×\(count)")
                                .font(.caption).foregroundStyle(.orange)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.orange.opacity(0.1), in: Capsule())
                        }
                        Button {
                            editTitle = lesson.title
                            editingLesson = lesson
                        } label: {
                            Image(systemName: "pencil").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
                .swipeActions {
                    Button("删除", role: .destructive) {
                        store.deleteLesson(lessonId: lesson.id, levelId: level.id)
                    }
                }
            }

            // Add lesson row
            HStack(spacing: 8) {
                TextField("编号", text: $newNumber).frame(width: 70)
                TextField("课程名称（可选）", text: $newTitle)
                Button("添加") { addLesson() }
                    .disabled(newNumber.trimmingCharacters(in: .whitespaces).isEmpty)
                    .buttonStyle(.bordered).controlSize(.small)
            }
            .padding(.top, 4)
        } label: {
            HStack {
                Text(level.id).fontWeight(.semibold)
                Spacer()
                Text("\(level.lessons.count) 课")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func addLesson() {
        let num = normalizeNumber(newNumber)
        guard !num.isEmpty else { return }
        store.addLesson(number: num, title: newTitle.trimmingCharacters(in: .whitespaces), to: level.id)
        newNumber = ""
        newTitle = ""
    }

    private func commitEdit(lesson: Lesson) {
        store.updateLessonTitle(editTitle, lessonId: lesson.id, levelId: level.id)
        editingLesson = nil
    }
}
