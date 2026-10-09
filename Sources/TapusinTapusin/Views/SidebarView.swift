import SwiftUI

struct SidebarView: View {
    @Environment(Store.self) private var store
    @Environment(\.appAccent) private var accent
    @Binding var selection: SidebarSelection
    @Binding var isAddingProduct: Bool
    @Binding var productToDelete: Product?

    @Local private var newName = ""
    @Local private var renamingID: UUID?
    @Local private var renameText = ""
    @Local private var isAddingTag = false
    @Local private var newTagName = ""
    @Local private var renamingTagID: UUID?
    @FocusState private var focus: Field?

    private enum Field: Hashable { case new, rename, newTag, renameTag }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(SmartList.allCases) { smartRow($0) }

                sectionLabel("Products")

                ForEach(store.products) { productRow($0) }

                if isAddingProduct {
                    newProductField
                }

                Button {
                    isAddingProduct = true
                } label: {
                    HStack(spacing: 8) {
                        Text("+").font(.system(size: 15)).frame(width: 16)
                        Text("New product")
                    }
                    .font(.system(size: 13))
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("New product (⇧⌘N)")

                sectionLabel("Tags")

                ForEach(store.tags) { tagRow($0) }

                if isAddingTag {
                    inlineField(placeholder: "Tag name", text: $newTagName, field: .newTag) {
                        Image(systemName: "tag").font(.system(size: 11)).foregroundStyle(.secondary)
                    } onSubmit: {
                        let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !name.isEmpty { selection = .tag(store.tag(named: name).id) }
                        newTagName = ""
                        isAddingTag = false
                    } onCancel: {
                        newTagName = ""
                        isAddingTag = false
                    }
                }

                Button {
                    isAddingTag = true
                    DispatchQueue.main.async { focus = .newTag }
                } label: {
                    HStack(spacing: 8) {
                        Text("+").font(.system(size: 15)).frame(width: 16)
                        Text("New tag")
                    }
                    .font(.system(size: 13))
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Tags group tasks across products. Drag a task onto a tag to add it.")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
        }
        .background(Color.primary.opacity(0.03))
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color.primary.opacity(0.06)).frame(width: 1)
        }
        .background(ShortcutButton(key: "n", modifiers: [.command, .shift]) { isAddingProduct = true })
        .onChange(of: isAddingProduct) {
            if isAddingProduct {
                DispatchQueue.main.async { focus = .new }
            }
        }
    }

    // MARK: Rows

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 16)
            .padding(.bottom, 4)
    }

    @ViewBuilder
    private func tagRow(_ tag: Tag) -> some View {
        if renamingTagID == tag.id {
            inlineField(placeholder: "Name", text: $renameText, field: .renameTag) {
                Image(systemName: "tag.fill").font(.system(size: 11)).foregroundStyle(tag.color)
            } onSubmit: {
                let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { store.renameTag(tag.id, to: name) }
                renamingTagID = nil
            } onCancel: {
                renamingTagID = nil
            }
        } else {
            SidebarRow(
                isSelected: selection == .tag(tag.id),
                leading: {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(tag.color)
                        .frame(width: 16)
                },
                title: tag.name,
                count: store.tasks(in: .tag(tag.id)).filter { !$0.isDone }.count,
                onDropTask: { store.addTag(tag.id, to: $0) }
            ) {
                selection = .tag(tag.id)
            }
            .contextMenu {
                Button("Rename") {
                    renameText = tag.name
                    renamingTagID = tag.id
                    DispatchQueue.main.async { focus = .renameTag }
                }
                Menu("Color") {
                    ForEach(ProductPalette.colors.indices, id: \.self) { i in
                        Button(ProductPalette.colors[i].name + (tag.colorIndex == i ? "  ✓" : "")) {
                            store.setTagColor(tag.id, index: i)
                        }
                    }
                }
                Divider()
                Button("Delete Tag", role: .destructive) {
                    if selection == .tag(tag.id) { selection = .smart(.all) }
                    store.deleteTag(tag.id)
                }
            }
        }
    }

    private func inlineField<Leading: View>(
        placeholder: String, text: Binding<String>, field: Field,
        @ViewBuilder leading: () -> Leading,
        onSubmit: @escaping () -> Void, onCancel: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            leading().frame(width: 16)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focus, equals: field)
                .onSubmit(onSubmit)
                .onExitCommand(perform: onCancel)
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 7).strokeBorder(accent.color.opacity(0.6)))
    }

    private func smartRow(_ list: SmartList) -> some View {
        let count = store.tasks(in: .smart(list)).filter { !$0.isDone }.count
        return SidebarRow(
            isSelected: selection == .smart(list),
            dimmed: true,
            leading: { SmartListIcon(list: list) },
            title: list.title,
            count: count,
            countColor: list == .overdue && count > 0 ? Theme.red : Color(nsColor: .tertiaryLabelColor),
            // Dropping a task on Today schedules it for today.
            onDropTask: list == .today ? { store.snooze([$0], days: 0) } : nil
        ) {
            selection = .smart(list)
        }
    }

    @ViewBuilder
    private func productRow(_ product: Product) -> some View {
        if renamingID == product.id {
            HStack(spacing: 8) {
                ProductBadge(product: product)
                TextField("Name", text: $renameText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($focus, equals: .rename)
                    .onSubmit { commitRename(product) }
                    .onExitCommand { renamingID = nil }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 7).strokeBorder(accent.color.opacity(0.6)))
        } else {
            SidebarRow(
                isSelected: selection == .product(product.id),
                leading: { ProductBadge(product: product) },
                title: product.name,
                count: store.openCount(for: product.id),
                dropProduct: product
            ) {
                selection = .product(product.id)
            }
            .contextMenu {
                Button("Rename") {
                    renameText = product.name
                    renamingID = product.id
                    DispatchQueue.main.async { focus = .rename }
                }
                ProductLogoMenuItems(product: product)
                ProductColorMenu(product: product)
                Divider()
                Button("Delete…", role: .destructive) { productToDelete = product }
            }
        }
    }

    private var newProductField: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 5)
                .fill(ProductPalette.color(store.products.count).opacity(0.18))
                .frame(width: 16, height: 16)
            TextField("Product name", text: $newName)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focus, equals: .new)
                .onSubmit(commitNewProduct)
                .onExitCommand(perform: cancelNewProduct)
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 7).strokeBorder(accent.color.opacity(0.6)))
    }

    // MARK: Actions

    private func commitNewProduct() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            let product = store.addProduct(named: name)
            selection = .product(product.id)
        }
        cancelNewProduct()
    }

    private func cancelNewProduct() {
        newName = ""
        isAddingProduct = false
    }

    private func commitRename(_ product: Product) {
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { store.renameProduct(product.id, to: name) }
        renamingID = nil
    }
}

struct ProductColorMenu: View {
    @Environment(Store.self) private var store
    let product: Product

    var body: some View {
        Menu("Color") {
            ForEach(ProductPalette.colors.indices, id: \.self) { i in
                Button(ProductPalette.colors[i].name + (product.colorIndex == i ? "  ✓" : "")) {
                    store.setColor(product.id, index: i)
                }
            }
        }
    }
}

private struct SmartListIcon: View {
    let list: SmartList

    var body: some View {
        Group {
            switch list {
            case .today:
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(lineWidth: 1.5)
                    .overlay(
                        Text("\(Calendar.current.component(.day, from: Date()))")
                            .font(.system(size: 8, weight: .bold))
                    )
            case .all:
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(lineWidth: 1.5)
                    .overlay(alignment: .top) { Rectangle().frame(height: 4) }
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            case .overdue:
                Circle()
                    .strokeBorder(lineWidth: 1.5)
                    .overlay(Text("!").font(.system(size: 9, weight: .bold)))
            }
        }
        .frame(width: 16, height: 16)
    }
}

private struct SidebarRow<Leading: View>: View {
    let isSelected: Bool
    var dimmed = false
    @ViewBuilder let leading: () -> Leading
    let title: String
    let count: Int
    var countColor: Color = Color(nsColor: .tertiaryLabelColor)
    var onDropTask: ((UUID) -> Void)?
    /// Product rows accept tasks (move) and image files (logo).
    var dropProduct: Product?
    let action: () -> Void

    @Environment(Store.self) private var store
    @Environment(\.appAccent) private var accent
    @Local private var isHovering = false
    @Local private var isDropTargeted = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                leading()
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11.5))
                        .monospacedDigit()
                        .foregroundStyle(countColor)
                }
            }
            .foregroundStyle(dimmed && !isSelected ? Color.secondary : Color.primary)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Theme.card : isHovering ? Color.primary.opacity(0.04) : .clear)
                    .shadow(color: .black.opacity(isSelected ? 0.08 : 0), radius: 1, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(accent.color.opacity(0.7), lineWidth: isDropTargeted ? 1.5 : 0)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .modifier(SidebarDrop(product: dropProduct, onDropTask: onDropTask, isTargeted: $isDropTargeted))
    }
}

private struct SidebarDrop: ViewModifier {
    @Environment(Store.self) private var store
    let product: Product?
    let onDropTask: ((UUID) -> Void)?
    @Binding var isTargeted: Bool

    func body(content: Content) -> some View {
        if let product {
            content.productDropTarget(product, store: store, isTargeted: $isTargeted)
        } else if let onDropTask {
            content.onDrop(of: [.plainText], isTargeted: $isTargeted) { TaskDrag.loadTaskID($0, onDropTask) }
        } else {
            content
        }
    }
}
