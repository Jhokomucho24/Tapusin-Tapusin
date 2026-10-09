import SwiftUI

/// Inner page for one task: title, properties, and a rich note. Opened by clicking a task row.
struct TaskDetailView: View {
    @Environment(Store.self) private var store
    let taskID: UUID
    let backTitle: String
    let onBack: () -> Void

    @Local private var controller = NoteController()
    @Local private var openPicker: PickerKind?

    private enum PickerKind { case status, priority, due, product, tags }

    var body: some View {
        if let task = store.tasks.first(where: { $0.id == taskID }) {
            content(task)
        } else {
            Color.clear.onAppear(perform: onBack)
        }
    }

    private func content(_ task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar(task)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    StatusCheck(status: task.status, size: 20) { store.setStatus(task.id, $0) }
                        .padding(.top, 3)
                    TextField("Untitled task", text: store.binding(for: task).title, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 20, weight: .semibold))
                        .strikethrough(task.isDone, color: .secondary)
                        .foregroundStyle(task.isDone ? .secondary : .primary)
                        .lineLimit(1...3)
                }
                properties(task)
            }
            .padding(.horizontal, 22)
            .padding(.top, 2)
            .padding(.bottom, 12)

            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)

            NoteEditor(taskID: task.id, fallbackText: task.notes, controller: controller, store: store)
                .id(task.id)
                .padding(.horizontal, 17)
                .frame(maxHeight: .infinity)

            FormatToolbar(controller: controller)
        }
        .background {
            ShortcutButton(key: .escape, modifiers: []) { onBack() }
            ShortcutButton(key: "[") { onBack() }
        }
    }

    // MARK: Top bar

    private func topBar(_ task: TaskItem) -> some View {
        HStack(spacing: 10) {
            BackButton(title: backTitle, action: onBack)
            Spacer()
            Text(metaText(task))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Menu {
                Button("Delete Task", role: .destructive) {
                    store.deleteTask(task.id)
                    onBack()
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(.secondary)
        }
        .padding(.leading, 12)
        .padding(.trailing, 16)
        .frame(height: 40)
    }

    private func metaText(_ task: TaskItem) -> String {
        if let done = task.completedAt {
            return "Done \(done.formatted(.dateTime.month(.abbreviated).day()))"
        }
        return "Created \(task.createdAt.formatted(.dateTime.month(.abbreviated).day()))"
    }

    // MARK: Properties

    private func pickerBinding(_ kind: PickerKind) -> Binding<Bool> {
        Binding(get: { openPicker == kind }, set: { openPicker = $0 ? kind : nil })
    }

    private func update(_ task: TaskItem, _ change: (inout TaskItem) -> Void) {
        var t = task
        change(&t)
        store.updateTask(t)
    }

    private func properties(_ task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            propertyChips(task)
            tagChip(task)
        }
    }

    private func tagChip(_ task: TaskItem) -> some View {
        let tags = store.tags(for: task)
        return PropertyChip(isPresented: pickerBinding(.tags)) {
            HStack(spacing: 4) {
                if tags.isEmpty {
                    Image(systemName: "tag")
                    Text("Add tags")
                } else {
                    Image(systemName: "tag").foregroundStyle(.secondary)
                    ForEach(tags) { TagPill(name: $0.name, color: $0.color) }
                }
            }
            .foregroundStyle(.secondary)
        } content: {
            TagPicker(task: task)
        }
    }

    private func propertyChips(_ task: TaskItem) -> some View {
        HStack(spacing: 6) {
            PropertyChip(isPresented: pickerBinding(.status)) {
                HStack(spacing: 5) {
                    Image(systemName: task.status.icon).foregroundStyle(task.status.color)
                    Text(task.status.title)
                }
            } content: {
                ForEach(TaskStatus.allCases) { s in
                    OptionRow(title: s.title, isSelected: task.status == s) {
                        Image(systemName: s.icon).foregroundStyle(s.color)
                    } action: {
                        store.setStatus(task.id, s)
                        openPicker = nil
                    }
                }
            }

            PropertyChip(isPresented: pickerBinding(.priority)) {
                HStack(spacing: 5) {
                    PriorityBars(priority: task.priority)
                    Text(task.priority == .none ? "No priority" : task.priority.title)
                }
            } content: {
                ForEach(Priority.allCases.reversed()) { p in
                    OptionRow(title: p.title, isSelected: task.priority == p) {
                        PriorityBars(priority: p)
                    } action: {
                        update(task) { $0.priority = p }
                        openPicker = nil
                    }
                }
            }

            PropertyChip(isPresented: pickerBinding(.due)) {
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                    Text(DueFormat.label(task))
                }
                .foregroundStyle(task.deadline == nil ? Color.secondary : DueFormat.color(task) == .secondary ? Color.primary : DueFormat.color(task))
            } content: {
                dueOptions(task)
            }

            if let product = store.product(task.productID) {
                PropertyChip(isPresented: pickerBinding(.product)) {
                    HStack(spacing: 5) {
                        ProductBadge(product: product, size: 14)
                        Text(product.name).lineLimit(1)
                    }
                } content: {
                    ForEach(store.products) { p in
                        OptionRow(title: p.name, isSelected: p.id == product.id) {
                            ProductBadge(product: p, size: 16)
                        } action: {
                            update(task) { $0.productID = p.id }
                            openPicker = nil
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dueOptions(_ task: TaskItem) -> some View {
        let quick: [(String, Int)] = [("Today", 0), ("Tomorrow", 1), ("Next week", 7)]
        ForEach(quick, id: \.0) { title, days in
            let date = Date().adding(days: days)
            OptionRow(title: title, isSelected: task.deadline.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false) {
                Text(date.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } action: {
                update(task) { $0.deadline = date }
                openPicker = nil
            }
        }
        if task.deadline != nil {
            OptionRow(title: "No date") {
                update(task) { $0.deadline = nil }
                openPicker = nil
            }
        }
        Divider().padding(.vertical, 4)
        DatePicker(
            "Deadline",
            selection: Binding(
                get: { task.deadline ?? Date() },
                set: { newValue in update(task) { $0.deadline = newValue.startOfDay } }
            ),
            displayedComponents: .date
        )
        .datePickerStyle(.graphical)
        .labelsHidden()
        .padding(.horizontal, 4)
    }
}

private struct BackButton: View {
    let title: String
    let action: () -> Void

    @Local private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)
            }
            .foregroundStyle(isHovering ? .primary : .secondary)
            .padding(.horizontal, 6)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 6).fill(isHovering ? Color.primary.opacity(0.05) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Back (Esc)")
    }
}
