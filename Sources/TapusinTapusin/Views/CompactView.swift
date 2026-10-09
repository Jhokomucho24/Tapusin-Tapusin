import SwiftUI

/// Study 1b — compact popover: date header, product chips, flat task list, add bar pinned to the bottom.
/// Clicking a task pushes its detail page over the whole popover.
struct CompactView: View {
    @Environment(Store.self) private var store
    @Binding var productToDelete: Product?

    @Local private var chip: UUID?
    @Local private var openTaskID: UUID?

    /// Ignores a chip whose product was deleted.
    private var activeChip: UUID? {
        chip.flatMap { store.product($0) != nil ? $0 : nil }
    }

    var body: some View {
        ZStack {
            if let openTaskID {
                TaskDetailView(taskID: openTaskID, backTitle: "Tasks", onBack: closeTask)
                    .transition(.push(from: .trailing))
            } else {
                CompactListPage(productToDelete: $productToDelete, chip: $chip, onOpen: openTask)
                    .transition(.push(from: .leading))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onReceive(NotificationCenter.default.publisher(for: .focusAddTask)) { _ in closeTask() }
    }

    private func openTask(_ id: UUID) {
        withAnimation(.snappy(duration: 0.28)) { openTaskID = id }
    }

    private func closeTask() {
        withAnimation(.snappy(duration: 0.28)) { openTaskID = nil }
    }
}

private struct CompactListPage: View {
    @Environment(Store.self) private var store
    @Environment(\.appAccent) private var accent
    @Binding var productToDelete: Product?
    @Binding var chip: UUID?
    let onOpen: (UUID) -> Void

    @Local private var isAddingProduct = false
    @Local private var newProductName = ""
    @FocusState private var addFocused: Bool
    @FocusState private var productFieldFocused: Bool

    private var activeChip: UUID? {
        chip.flatMap { store.product($0) != nil ? $0 : nil }
    }

    var body: some View {
        let list = (activeChip.map { id in store.tasks.filter { $0.productID == id } } ?? store.tasks)
            .sorted(by: Store.sortOrder)

        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                header
                chips.padding(.top, 14)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 4)

            if store.products.isEmpty && !isAddingProduct {
                WelcomeView { startAddingProduct() }
            } else if list.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("No tasks yet. Add one below.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        let overdue = list.filter(\.isOverdue)
                        if !overdue.isEmpty {
                            OverdueBanner(count: overdue.count) {
                                store.snooze(Set(overdue.map(\.id)), days: 0)
                            }
                            .padding(.bottom, 4)
                        }
                        ForEach(list) { task in
                            CompactTaskRow(task: task) {
                                onOpen(task.id)
                            } onDropBefore: { dropped in
                                let bucket = DueBucket(task)
                                store.reorder(dropped, before: task.id, in: list.filter { DueBucket($0) == bucket })
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
            }

            AddTaskBar(defaultProductID: activeChip, deadline: Date().startOfDay, focus: $addFocused)
        }
        .background {
            ShortcutButton(key: "n") { addFocused = true }
            ShortcutButton(key: "n", modifiers: [.command, .shift]) { startAddingProduct() }
        }
    }

    // MARK: Header

    private var header: some View {
        let now = Date()
        let done = store.tasks.filter(\.isDone).count
        let total = store.tasks.count
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(now.formatted(.dateTime.weekday(.wide)))
                    .font(.system(size: 20, weight: .semibold))
                    .kerning(-0.2)
                Spacer()
                Text("\(done) of \(total) done")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Text(now.formatted(.dateTime.month(.wide).day()))
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.06))
                    Capsule()
                        .fill(accent.color)
                        .frame(width: total == 0 ? 0 : geo.size.width * CGFloat(done) / CGFloat(total))
                }
            }
            .frame(height: 4)
            .padding(.top, 12)
            .animation(.snappy, value: done)
        }
    }

    // MARK: Chips

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ChipButton(label: "All", product: nil, isSelected: activeChip == nil) { chip = nil }
                ForEach(store.products) { product in
                    ChipButton(label: product.name, product: product, isSelected: activeChip == product.id) {
                        chip = product.id
                    }
                    .contextMenu {
                        ProductLogoMenuItems(product: product)
                        ProductColorMenu(product: product)
                        Divider()
                        Button("Delete…", role: .destructive) { productToDelete = product }
                    }
                    .productDropTarget(product, store: store)
                }
                if isAddingProduct {
                    TextField("Product name", text: $newProductName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($productFieldFocused)
                        .frame(width: 110)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Capsule().strokeBorder(accent.color.opacity(0.6)))
                        .onSubmit(commitNewProduct)
                        .onExitCommand { isAddingProduct = false; newProductName = "" }
                } else {
                    Button(action: startAddingProduct) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Theme.fill))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("New product (⇧⌘N)")
                }
            }
            .padding(.bottom, 2)
        }
    }

    // MARK: Actions

    private func startAddingProduct() {
        isAddingProduct = true
        DispatchQueue.main.async { productFieldFocused = true }
    }

    private func commitNewProduct() {
        let name = newProductName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            chip = store.addProduct(named: name).id
        }
        newProductName = ""
        isAddingProduct = false
    }
}

private struct ChipButton: View {
    @Environment(\.appAccent) private var accent
    let label: String
    let product: Product?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let product {
                    ProductBadge(product: product, size: 16, circle: true)
                }
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? accent.onColor : Color.secondary)
            .padding(.leading, product == nil ? 12 : 4)
            .padding(.trailing, product == nil ? 12 : 10)
            .frame(height: 26)
            .background(Capsule().fill(isSelected ? accent.color : Theme.fill))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// "2 overdue · Move to today" strip at the top of the compact list.
private struct OverdueBanner: View {
    let count: Int
    let moveToToday: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
            Text("\(count) overdue")
            Spacer()
            Button("Move to today", action: moveToToday)
                .buttonStyle(.plain)
                .fontWeight(.semibold)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Theme.red)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.red.opacity(0.08)))
    }
}

private struct CompactTaskRow: View {
    @Environment(Store.self) private var store
    @Environment(\.appAccent) private var accent
    let task: TaskItem
    let onOpen: () -> Void
    let onDropBefore: (UUID) -> Void

    @Local private var isHovering = false
    @Local private var isDropTargeted = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            StatusCheck(status: task.status) { store.setStatus(task.id, $0) }
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(task.title)
                        .font(.system(size: 13))
                        .foregroundStyle(task.isDone ? .tertiary : .primary)
                        .strikethrough(task.isDone, color: .secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if task.priority == .high && !task.isDone {
                        Circle().fill(Theme.red).frame(width: 6, height: 6)
                            .help("High priority")
                    }
                }
                HStack(spacing: 6) {
                    if let product = store.product(task.productID) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(product.color)
                            .frame(width: 7, height: 7)
                        Text(product.name)
                    }
                    Text("·").foregroundStyle(.quaternary)
                    Text(DueFormat.label(task)).foregroundStyle(DueFormat.color(task))
                    TaskTagsView(task: task)
                    if task.checklistTotal != nil {
                        Text("·").foregroundStyle(.quaternary)
                        ChecklistBadge(task: task)
                    } else if !task.notes.isEmpty {
                        Image(systemName: "text.alignleft").foregroundStyle(.tertiary)
                    }
                }
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 3)
                .opacity(isHovering ? 1 : 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovering ? Color.primary.opacity(0.035) : .clear)
        )
        .overlay(alignment: .top) {
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
