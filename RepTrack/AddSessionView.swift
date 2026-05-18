import SwiftUI

// Pending entry: stores raw lesson numbers (not IDs).
// ensureLesson is only called at save time to avoid creating ghost lessons.
private struct PendingEntry: Identifiable {
    var id = UUID()
    var date: Date
    var levelId: String
    var lessonNumbers: [String]  // raw numbers, e.g. "011", "43"
}

struct AddSessionView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let existing: ReviewSession?

    // ── Shared form state ─────────────────────────────────────
    @State private var selectedLevelId = ""
    @State private var lessonInput = ""
    @State private var error = ""

    // ── Add mode ──────────────────────────────────────────────
    @State private var entryDate = Date()
    @State private var entries: [PendingEntry] = []

    // ── Edit mode ─────────────────────────────────────────────
    @State private var editDate = Date()
    @State private var editItems: [ReviewItem] = []

    init(existing: ReviewSession? = nil) {
        self.existing = existing
    }

    private var isEditMode: Bool { existing != nil }
    private var currentLevel: Level? { store.levels.first { $0.id == selectedLevelId } }
    private var canAddEntry: Bool {
        !selectedLevelId.isEmpty && !lessonInput.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isEditMode ? "编辑复习记录" : "添加复习记录")
                    .font(.title2).fontWeight(.semibold)
                Spacer()
                Button("取消") { dismiss() }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 12)

            Divider()

            Form {
                if isEditMode {
                    Section {
                        DatePicker("日期", selection: $editDate, displayedComponents: .date)
                    }
                }

                Section("课程条目") {
                    if !isEditMode {
                        DatePicker("日期", selection: $entryDate, displayedComponents: .date)
                    }

                    Picker("等级", selection: $selectedLevelId) {
                        Text("选择等级…").tag("")
                        ForEach(store.levels) { lv in Text(lv.id).tag(lv.id) }
                    }

                    HStack(spacing: 8) {
                        TextField("课程编号，逗号分隔（如：43, 44）", text: $lessonInput)
                            .onSubmit { addEntry() }
                        Button("添加") { addEntry() }
                            .disabled(!canAddEntry)
                            .buttonStyle(.borderedProminent)
                    }

                    if !error.isEmpty {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }

                    if let level = currentLevel, !level.lessons.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(level.lessons.sorted { lessonNumberLess($0.number, $1.number) }) { lesson in
                                    Button { appendChip(paddedDisplay(lesson.number)) } label: {
                                        Text(lesson.displayName)
                                            .font(.caption)
                                            .padding(.horizontal, 8).padding(.vertical, 4)
                                            .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                let pendingIsEmpty = isEditMode ? editItems.isEmpty : entries.isEmpty
                if !pendingIsEmpty {
                    Section(isEditMode ? "当前记录" : "本次记录") {
                        if isEditMode {
                            ForEach(editItems) { item in
                                EditItemRow(item: item, store: store) {
                                    editItems.removeAll { $0.id == item.id }
                                }
                            }
                        } else {
                            ForEach(entries) { entry in
                                PendingEntryRow(entry: entry, store: store) {
                                    entries.removeAll { $0.id == entry.id }
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                if !isEditMode {
                    Text(entrySummary).font(.caption).foregroundStyle(.secondary)
                }
                Button(isEditMode ? "保存修改" : "保存记录") { save() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isEditMode ? editItems.isEmpty : entries.isEmpty)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
        .frame(width: 520, height: 580)
        .onAppear {
            if let e = existing {
                editDate = e.date
                editItems = e.items
            }
            if selectedLevelId.isEmpty, let first = store.levels.first {
                selectedLevelId = first.id
            }
        }
    }

    // MARK: - Helpers

    private var entrySummary: String {
        let days = Set(entries.map { Calendar.current.startOfDay(for: $0.date) }).count
        let lessons = entries.reduce(0) { $0 + $1.lessonNumbers.count }
        if days > 1 { return "\(days) 个日期，共 \(lessons) 课" }
        return lessons > 0 ? "共 \(lessons) 课" : ""
    }

    private func appendChip(_ number: String) {
        let current = lessonInput.trimmingCharacters(in: .whitespaces)
        lessonInput = current.isEmpty ? number : "\(current), \(number)"
    }

    private func addEntry() {
        error = ""
        guard !selectedLevelId.isEmpty else { error = "请先选择等级"; return }

        let parts = lessonInput.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { error = "请输入课程编号"; return }

        // Collect raw numbers — do NOT call ensureLesson here
        var numbers: [String] = []
        for raw in parts {
            let n = normalizeNumber(raw)
            if !numbers.contains(where: { sameNumber($0, n) }) {
                numbers.append(n)
            }
        }
        numbers.sort { lessonNumberLess($0, $1) }

        if isEditMode {
            // Edit mode: resolve to lesson IDs immediately (lessons already exist)
            var lessonIds: [String] = []
            for n in numbers {
                let lesson = store.ensureLesson(number: n, levelId: selectedLevelId)
                if !lessonIds.contains(lesson.id) { lessonIds.append(lesson.id) }
            }
            let sorted = lessonIds.sorted { a, b in
                let na = store.levels.flatMap(\.lessons).first { $0.id == a }?.number ?? a
                let nb = store.levels.flatMap(\.lessons).first { $0.id == b }?.number ?? b
                return lessonNumberLess(na, nb)
            }
            if let idx = editItems.firstIndex(where: { $0.levelId == selectedLevelId }) {
                for lid in sorted where !editItems[idx].lessonIds.contains(lid) {
                    editItems[idx].lessonIds.append(lid)
                }
                editItems[idx].lessonIds.sort { a, b in
                    let na = store.levels.flatMap(\.lessons).first { $0.id == a }?.number ?? a
                    let nb = store.levels.flatMap(\.lessons).first { $0.id == b }?.number ?? b
                    return lessonNumberLess(na, nb)
                }
            } else {
                editItems.append(ReviewItem(levelId: selectedLevelId, lessonIds: sorted))
            }
        } else {
            // Add mode: just store raw numbers, no DataStore mutation
            let cal = Calendar.current
            if let idx = entries.firstIndex(where: {
                cal.isDate($0.date, inSameDayAs: entryDate) && $0.levelId == selectedLevelId
            }) {
                for n in numbers where !entries[idx].lessonNumbers.contains(where: { sameNumber($0, n) }) {
                    entries[idx].lessonNumbers.append(n)
                }
                entries[idx].lessonNumbers.sort { lessonNumberLess($0, $1) }
            } else {
                entries.append(PendingEntry(date: entryDate, levelId: selectedLevelId, lessonNumbers: numbers))
            }
        }
        lessonInput = ""
    }

    private func save() {
        // Flush any typed-but-not-yet-added input before saving
        if canAddEntry { addEntry() }

        if let e = existing {
            store.updateSession(ReviewSession(id: e.id, date: editDate, items: editItems))
        } else {
            let cal = Calendar.current
            let grouped = Dictionary(grouping: entries) { cal.startOfDay(for: $0.date) }
            for (day, dayEntries) in grouped.sorted(by: { $0.key < $1.key }) {
                var levelMap: [String: [String]] = [:]
                for entry in dayEntries {
                    for number in entry.lessonNumbers {
                        // Only now do we call ensureLesson (may create if truly new)
                        let lesson = store.ensureLesson(number: number, levelId: entry.levelId)
                        if !(levelMap[entry.levelId, default: []].contains(lesson.id)) {
                            levelMap[entry.levelId, default: []].append(lesson.id)
                        }
                    }
                }
                let items = levelMap.map { (lvId, ids) -> ReviewItem in
                    let sorted = ids.sorted { a, b in
                        let na = store.levels.flatMap(\.lessons).first { $0.id == a }?.number ?? a
                        let nb = store.levels.flatMap(\.lessons).first { $0.id == b }?.number ?? b
                        return lessonNumberLess(na, nb)
                    }
                    return ReviewItem(levelId: lvId, lessonIds: sorted)
                }.sorted { a, b in
                    let ia = store.levels.firstIndex { $0.id == a.levelId } ?? Int.max
                    let ib = store.levels.firstIndex { $0.id == b.levelId } ?? Int.max
                    return ia < ib
                }
                store.addSession(ReviewSession(date: day, items: items))
            }
        }
        dismiss()
    }
}

// MARK: - Row views

private struct PendingEntryRow: View {
    let entry: PendingEntry
    let store: DataStore
    let onRemove: () -> Void

    private var dateLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(entry.date) { return "今天" }
        if cal.isDateInYesterday(entry.date) { return "昨天" }
        let f = DateFormatter(); f.dateFormat = "MM/dd"
        return f.string(from: entry.date)
    }

    // Look up by number without creating anything
    private func lessonName(_ number: String) -> String {
        if let lesson = store.levels.first(where: { $0.id == entry.levelId })?
            .lessons.first(where: { sameNumber($0.number, number) }) {
            return lesson.displayName
        }
        return paddedDisplay(number)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(dateLabel)
                .font(.caption2).fontWeight(.medium)
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Color.secondary.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))

            Text(entry.levelId)
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(levelColor(entry.levelId), in: RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                ForEach(entry.lessonNumbers, id: \.self) { n in
                    Text(lessonName(n)).font(.callout).foregroundStyle(.primary)
                }
            }

            Spacer()
            Button { onRemove() } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct EditItemRow: View {
    let item: ReviewItem
    let store: DataStore
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            Text(item.levelId)
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(levelColor(item.levelId), in: RoundedRectangle(cornerRadius: 4))

            let lessons: [Lesson] = item.lessonIds.compactMap { lid in
                let tail = lid.components(separatedBy: "-").last ?? lid
                return store.levels
                    .first { $0.id == item.levelId }?
                    .lessons.first {
                        $0.id == lid || $0.number == tail ||
                        (Int($0.number) != nil && Int($0.number) == Int(tail))
                    }
            }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(lessons) { lesson in
                    Text(lesson.displayName).font(.callout).foregroundStyle(.primary)
                }
            }

            Spacer()
            Button { onRemove() } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}
