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
    @State private var selectedEntryId: UUID? = nil

    // ── Edit mode ─────────────────────────────────────────────
    @State private var editDate = Date()
    @State private var editItems: [ReviewItem] = []
    @State private var selectedEditItemId: UUID? = nil
    @State private var cancelHovered = false
    @State private var saveHovered = false

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
                Button("取消") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(cancelHovered ? .primary : .secondary)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(cancelHovered ? AnyShapeStyle(Color.secondary.opacity(0.12)) : AnyShapeStyle(Color.clear),
                                in: RoundedRectangle(cornerRadius: 7))
                    .scaleEffect(cancelHovered ? 1.04 : 1.0)
                    .animation(.easeInOut(duration: 0.12), value: cancelHovered)
                    .contentShape(RoundedRectangle(cornerRadius: 7))
                    .onHover { cancelHovered = $0 }
                    .focusable(false)
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 12)

            Divider()

            Form {
                if isEditMode {
                    Section {
                        DatePicker("日期", selection: $editDate, displayedComponents: .date)
                    }
                }

                Section {
                    if !isEditMode {
                        DatePicker("日期", selection: $entryDate, displayedComponents: .date)
                    }

                    Picker("内容", selection: $selectedLevelId) {
                        ForEach(store.levels) { lv in Text(lv.id).tag(lv.id) }
                    }

                    if !error.isEmpty {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }

                    if let level = currentLevel, !level.lessons.isEmpty {
                        VStack(alignment: .trailing, spacing: 10) {
                            FlowLayout(spacing: 6) {
                                ForEach(level.lessons.sorted { lessonNumberLess($0.number, $1.number) }) { lesson in
                                    LessonChip(
                                        lesson: lesson,
                                        levelId: level.id,
                                        isSelected: isChipSelected(lesson)
                                    ) { appendChip(paddedDisplay(lesson.number)) }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(spacing: 8) {
                                Spacer()
                                if !lessonInput.isEmpty {
                                    ClearButton { lessonInput = "" }
                                }
                                AddButton(enabled: canAddEntry) { addEntry() }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                let pendingIsEmpty = isEditMode ? editItems.isEmpty : entries.isEmpty
                if !pendingIsEmpty {
                    Section(isEditMode ? "当前记录" : "本次记录") {
                        if isEditMode {
                            ForEach(editItems) { item in
                                EditItemRow(
                                    item: item,
                                    store: store,
                                    isSelected: selectedEditItemId == item.id,
                                    onSelect: {
                                        selectedEditItemId = item.id
                                        selectedLevelId = item.levelId
                                        // 把该条记录的课时编号填入 lessonInput，芯片同步高亮
                                        let numbers = item.lessonIds.compactMap { lid -> String? in
                                            store.levels.first { $0.id == item.levelId }?
                                                .lessons.first { $0.id == lid }?.number
                                        }
                                        lessonInput = numbers.map { paddedDisplay($0) }.joined(separator: ", ")
                                    },
                                    onRemove: {
                                        if selectedEditItemId == item.id {
                                            selectedEditItemId = nil
                                            lessonInput = ""
                                        }
                                        editItems.removeAll { $0.id == item.id }
                                    }
                                )
                            }
                        } else {
                            ForEach(entries) { entry in
                                PendingEntryRow(
                                    entry: entry,
                                    store: store,
                                    isSelected: selectedEntryId == entry.id,
                                    onSelect: {
                                        selectedEntryId = entry.id
                                        entryDate = entry.date
                                        selectedLevelId = entry.levelId
                                        lessonInput = entry.lessonNumbers
                                            .map { paddedDisplay($0) }
                                            .joined(separator: ", ")
                                    },
                                    onRemove: {
                                        if selectedEntryId == entry.id { selectedEntryId = nil }
                                        entries.removeAll { $0.id == entry.id }
                                    }
                                )
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
                let saveDisabled = isEditMode ? editItems.isEmpty : entries.isEmpty
                Button(isEditMode ? "保存修改" : "保存记录") { save() }
                    .buttonStyle(.plain)
                    .fontWeight(.semibold)
                    .foregroundStyle(saveDisabled ? Color.secondary : .white)
                    .padding(.horizontal, 20).padding(.vertical, 8)
                    .background(
                        saveDisabled
                            ? AnyShapeStyle(Color.secondary.opacity(0.15))
                            : AnyShapeStyle(Color.accentColor.opacity(saveHovered ? 0.75 : 1.0)),
                        in: RoundedRectangle(cornerRadius: 9)
                    )
                    .scaleEffect((!saveDisabled && saveHovered) ? 1.04 : 1.0)
                    .animation(.easeInOut(duration: 0.12), value: saveHovered)
                    .onHover { if !saveDisabled { saveHovered = $0 } }
                    .disabled(saveDisabled)
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
            // 取消所有组件的自动聚焦状态
            DispatchQueue.main.async {
                NSApp.keyWindow?.makeFirstResponder(nil)
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
        var parts = lessonInput.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let idx = parts.firstIndex(where: { sameNumber($0, number) }) {
            parts.remove(at: idx)
        } else {
            parts.append(number)
        }
        lessonInput = parts.joined(separator: ", ")
    }

    private func isChipSelected(_ lesson: Lesson) -> Bool {
        lessonInput.split(separator: ",")
            .map { normalizeNumber(String($0)) }
            .contains { sameNumber($0, lesson.number) }
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
            if let selId = selectedEditItemId,
               let idx = editItems.firstIndex(where: { $0.id == selId }) {
                // 选中状态：直接替换该条的课时
                editItems[idx].levelId = selectedLevelId
                editItems[idx].lessonIds = sorted
                selectedEditItemId = nil
            } else if let idx = editItems.firstIndex(where: { $0.levelId == selectedLevelId }) {
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
            // 若当前有选中记录，直接替换该条的课时
            if let selId = selectedEntryId,
               let idx = entries.firstIndex(where: { $0.id == selId }) {
                entries[idx].date = entryDate
                entries[idx].levelId = selectedLevelId
                entries[idx].lessonNumbers = numbers
                selectedEntryId = nil
            } else if let idx = entries.firstIndex(where: {
                cal.isDate($0.date, inSameDayAs: entryDate) && $0.levelId == selectedLevelId
            }) {
                // 同日期同等级：追加不重复的课
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

// MARK: - Chip & button components

private struct LessonChip: View {
    let lesson: Lesson
    let levelId: String
    let isSelected: Bool
    let onTap: () -> Void
    @State private var hovered = false

    var body: some View {
        Button { onTap() } label: {
            Text(lesson.displayName)
                .font(.caption)
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(
                    isSelected
                        ? AnyShapeStyle(levelColor(levelId).opacity(hovered ? 0.75 : 1.0))
                        : AnyShapeStyle(Color.secondary.opacity(hovered ? 0.22 : 0.10)),
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? levelColor(levelId).opacity(0.4) : Color.clear, lineWidth: 1)
                )
                .scaleEffect(hovered ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: hovered)
                .animation(.easeInOut(duration: 0.1), value: isSelected)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

private struct ClearButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button { action() } label: {
            Text("清除")
                .fontWeight(.medium)
                .foregroundStyle(hovered ? .white : Color.secondary)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(
                    hovered ? AnyShapeStyle(Color.secondary.opacity(0.5)) : AnyShapeStyle(Color.secondary.opacity(0.12)),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .scaleEffect(hovered ? 1.04 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: hovered)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

private struct AddButton: View {
    let enabled: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button { action() } label: {
            Text("添加")
                .fontWeight(.medium)
                .foregroundStyle(enabled ? .white : Color.secondary)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(
                    enabled
                        ? AnyShapeStyle(Color.accentColor.opacity(hovered ? 0.75 : 1.0))
                        : AnyShapeStyle(Color.secondary.opacity(0.12)),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .scaleEffect(enabled && hovered ? 1.04 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: hovered)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { if enabled { hovered = $0 } }
    }
}

// MARK: - Row views

private struct RemoveButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button { action() } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(hovered ? .white : Color.secondary.opacity(0.6))
                .frame(width: 26, height: 26)
                .background(
                    hovered ? AnyShapeStyle(Color.secondary.opacity(0.5)) : AnyShapeStyle(Color.clear),
                    in: Circle()
                )
                .scaleEffect(hovered ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: hovered)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

private struct PendingEntryRow: View {
    let entry: PendingEntry
    let store: DataStore
    var isSelected: Bool = false
    var onSelect: (() -> Void)? = nil
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
            RemoveButton { onRemove() }
        }
        .padding(isSelected ? 6 : 0)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect?() }
        .animation(.easeInOut(duration: 0.12), value: isSelected)
    }
}

private struct EditItemRow: View {
    let item: ReviewItem
    let store: DataStore
    var isSelected: Bool = false
    var onSelect: (() -> Void)? = nil
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
            RemoveButton { onRemove() }
        }
        .padding(isSelected ? 6 : 0)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect?() }
        .animation(.easeInOut(duration: 0.12), value: isSelected)
    }
}
