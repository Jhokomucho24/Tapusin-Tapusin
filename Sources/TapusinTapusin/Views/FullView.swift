import SwiftUI

/// Study 1a — refined sidebar: smart lists + products on the left, tasks grouped by due date on the right.
/// Clicking a task pushes its detail page over the list.
struct FullView: View {
    @Environment(Store.self) private var store
    @Binding var productToDelete: Product?

    @Local private var selection: SidebarSelection = .smart(.all)
    @Local private var isAddingProduct = false
    @Local private var filter: TaskStatus?
    @Local private var openTaskID: UUID?

    /// Falls back to All tasks if the selected product was deleted.
    private var effectiveSelection: SidebarSelection {
        if case .product(let id) = selection, store.product(id) == nil { return .smart(.all) }
        if case .tag(let id) = selection, store.tag(id) == nil { return .smart(.all) }
        return selection
    }

    /// Picking anything in the sidebar also leaves an open task page.
    private var sidebarSelection: Binding<SidebarSelection> {
        Binding(
            get: { selection },
            set: { newValue in
                if newValue != selection { filter = nil }
                selection = newValue
                closeTask()
            }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(
                selection: sidebarSelection,
                isAddingProduct: $isAddingProduct,
                productToDelete: $productToDelete
            )
            .frame(width: 200)

            ZStack {
                if let openTaskID {
                    TaskDetailView(taskID: openTaskID, backTitle: backTitle, onBack: closeTask)
                        .transition(.push(from: .trailing))
                } else {
                    TaskListPane(
                        selection: effectiveSelection,
                        filter: $filter,
                        isAddingProduct: $isAddingProduct,
                        onOpen: openTask
                    )
                    .transition(.push(from: .leading))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .onReceive(NotificationCenter.default.publisher(for: .focusAddTask)) { _ in closeTask() }
        }
    }

    private var backTitle: String {
        switch effectiveSelection {
        case .product(let id): store.product(id)?.name ?? "Back"
        case .tag(let id): store.tag(id)?.name ?? "Back"
        case .smart(let list): list.title
        }
    }

    private func openTask(_ id: UUID) {
        withAnimation(.snappy(duration: 0.28)) { openTaskID = id }
    }

    private func closeTask() {
        guard openTaskID != nil else { return }
        withAnimation(.snappy(duration: 0.28)) { openTaskID = nil }
    }
}

private struct TaskListPane: View {
    @Environment(Store.self) private var store
    let selection: SidebarSelection
    @Binding var filter: TaskStatus?
    @Binding var isAddingProduct: Bool
    let onOpen: (UUID) -> Void

    @FocusState private var addFocused: Bool

    private var productID: UUID? {
        if case .product(let id) = selection { id } else { nil }
    }

    private static let segments: [(value: TaskStatus?, label: String)] = [
        (nil, "All"), (.todo, "To do"), (.inProgress, "In progress"), (.done, "Done"),
    ]

    var body: some View {
        let all = store.tasks(in: selection)
        let list = (filter.map { f in all.filter { $0.status == f } } ?? all).sorted(by: Store.sortOrder)
        let groups = Dictionary(grouping: list, by: DueBucket.init).sorted { $0.key < $1.key }

        VStack(alignment: .leading, spacing: 0) {
            if store.products.isEmpty && store.tasks.isEmpty {
                WelcomeView { isAddingProduct = true }
            } else {
                header
                    .padding(.horizontal, 22)
                    .padding(.top, 18)
                    .padding(.bottom, 4)

                if list.isEmpty {
                    emptyList
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(groups, id: \.key) { group in
                                groupSection(group.key, tasks: group.value)
                            }
                        }
                        .padding(.horizontal, 22)
                        .padding(.bottom, 16)
                    }
                }

                AddTaskBar(
                    defaultProductID: productID,
                    deadline: selection == .smart(.today) ? Date().startOfDay : nil,
                    defaultTagID: { if case .tag(let id) = selection { id } else { nil } }(),
                    focus: $addFocused
                )
            }
        }
        .background(ShortcutButton(key: "n") { addFocused = true })
    }

    private var header: some View {
        HStack(spacing: 12) {
            switch selection {
            case .product(let id):
                if let product = store.product(id) {
                    EditableProductAvatar(product: product, size: 28)
                }
                Text(store.product(id)?.name ?? "Product").headerTitle()
            case .tag(let id):
                Image(systemName: "tag.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(store.tag(id)?.color ?? .secondary)
                Text(store.tag(id)?.name ?? "Tag").headerTitle()
            case .smart(let list):
                Text(list.title).headerTitle()
            }
            SegmentedPills(options: Self.segments, selection: $filter)
        }
    }

    private func groupSection(_ bucket: DueBucket, tasks: [TaskItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupHeader(bucket: bucket) {
                store.reorder($0, before: nil, in: tasks)
            } moveAllToToday: {
                store.snooze(Set(tasks.filter(\.isOverdue).map(\.id)), days: 0)
            }

            VStack(spacing: 0) {
                ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                    if index > 0 {
                        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 1)
                    }
                    FullTaskRow(task: task, showProduct: productID == nil) {
                        onOpen(task.id)
                    } onDropBefore: { dropped in
                        store.reorder(dropped, before: task.id, in: tasks)
                    }
                }
            }
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
        }
    }

    private var emptyList: some View {
        VStack(spacing: 6) {
            Image(systemName: filter == nil ? "checkmark.circle" : "line.3.horizontal.decrease.circle")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
            Text(emptyMessage)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyMessage: String {
        if filter != nil { return "No tasks with this status." }
        switch selection {
        case .product: return "No tasks yet. Add one below."
        case .tag: return "No tasks with this tag. Add one below, or drag tasks onto the tag."
        case .smart(let list): return list.emptyMessage
        }
    }
}

/// Date group label. Dropping a task here moves it to the end of the group (taking its date).
private struct GroupHeader: View {
    @Environment(\.appAccent) private var accent
    let bucket: DueBucket
    let onDropTask: (UUID) -> Void
    let moveAllToToday: () -> Void

    @Local private var isDropTargeted = false

    var body: some View {
        HStack {
            Text(bucket.title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(bucket == .overdue ? Theme.red : Color.secondary)
            Spacer()
            if bucket == .overdue {
                Button("Move all to today", action: moveAllToToday)
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.red)
                    .help("Reschedule every overdue task in this list to today")
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 14)
        .padding(.bottom, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(accent.color.opacity(isDropTargeted ? 0.1 : 0))
        )
        .onDrop(of: [.plainText], isTargeted: $isDropTargeted) { TaskDrag.loadTaskID($0, onDropTask) }
    }
}

private struct FullTaskRow: View {
    @Environment(Store.self) private var store
    @Environment(\.appAccent) private var accent
    let task: TaskItem
    let showProduct: Bool
    let onOpen: () -> Void
    let onDropBefore: (UUID) -> Void

    @Local private var isHovering = false
    @Local private var isDropTargeted = false

    var body: some View {
        HStack(spacing: 10) {
            StatusCheck(status: task.status) { store.setStatus(task.id, $0) }

            Text(task.title)
                .foregroundStyle(task.isDone ? .tertiary : .primary)
                .strikethrough(task.isDone, color: .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)

            if task.checklistTotal != nil {
                ChecklistBadge(task: task)
            } else if !task.notes.isEmpty {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .help(task.notes)
            }

            Spacer(minLength: 8)

            if showProduct, let product = store.product(task.productID) {
                HStack(spacing: 6) {
                    ProductBadge(product: product, size: 14)
                    Text(product.name).lineLimit(1)
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }

            PriorityBars(priority: task.priority)

            Text(DueFormat.label(task))
                .font(.system(size: 12))
                .foregroundStyle(DueFormat.color(task))
                .frame(minWidth: 64, alignment: .trailing)

            TaskTagsView(task: task)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .opacity(isHovering ? 1 : 0)
        }
        .font(.system(size: 13))
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .padding(.vertical, 9)
        .background(isHovering ? Color.primary.opacity(0.03) : .clear)
        .overlay(alignment: .top) {
            // Insertion line while another task is dragged over this row.
            Rectangle().fill(accent.color).frame(height: 2).opacity(isDropTargeted ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { isHovering = $0 }
        .onDrag { TaskDrag.provider(task.id) }
        .onDrop(of: [.plainText], isTargeted: $isDropTargeted) { TaskDrag.loadTaskID($0, onDropBefore) }
        .taskContextMenu(task, store: store)
    }
}

struct WelcomeView: View {
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "checklist")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("Welcome to Tapusin-Tapusin")
                .font(.system(size: 17, weight: .semibold))
            Text("Create a product, then add tasks to it.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Button("Create your first product", action: onCreate)
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension Text {
    func headerTitle() -> some View {
        font(.system(size: 20, weight: .semibold))
            .kerning(-0.2)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
