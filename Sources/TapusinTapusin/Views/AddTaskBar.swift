import SwiftUI

/// Fixed footer for adding tasks. Understands dates, priority and #product typed inline.
struct AddTaskBar: View {
    @Environment(Store.self) private var store
    @Environment(\.appAccent) private var accent
    /// Product implied by the current view; falls back to the first product.
    let defaultProductID: UUID?
    var deadline: Date?
    /// Tag implied by the current view (e.g. when browsing a tag).
    var defaultTagID: UUID?
    var focus: FocusState<Bool>.Binding

    @Local private var text = ""

    private var defaultTarget: Product? {
        defaultProductID.flatMap(store.product) ?? store.products.first
    }

    var body: some View {
        let parsed = QuickAddParser.parse(text, products: store.products)
        let target = parsed.productID.flatMap(store.product) ?? defaultTarget

        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.tertiary)

            TextField(defaultTarget.map { "Add a task to \($0.name)…" } ?? "Create a product to add tasks", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused(focus)
                .onSubmit { submit(parsed, target: target) }
                .onExitCommand { text = ""; focus.wrappedValue = false }
                .disabled(defaultTarget == nil)
                .help("Type naturally: “Review deck fri !high #sidekick”. Dates: today, tmr, mon, next week, in 3 days, oct 12. Priority: ! !! !!!. Tags: @name.")

            parsedChips(parsed, target: target)

            KeyHint(text: "⌘N")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.card)
                .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(focus.wrappedValue ? accent.color.opacity(0.5) : Color.primary.opacity(0.1),
                              lineWidth: focus.wrappedValue ? 1 : 0.5)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
        }
        .animation(.snappy(duration: 0.18), value: parsed)
        .onReceive(NotificationCenter.default.publisher(for: .focusAddTask)) { _ in
            // Let the popover open and any detail page slide away first.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focus.wrappedValue = true }
        }
    }

    /// Previews what was understood from the text, so it's clear before pressing Return.
    @ViewBuilder
    private func parsedChips(_ parsed: ParsedTask, target: Product?) -> some View {
        HStack(spacing: 4) {
            if let target, parsed.productID != nil {
                chip {
                    ProductBadge(product: target, size: 13)
                    Text(target.name).lineLimit(1)
                }
            }
            if let date = parsed.deadline {
                let preview = TaskItem(productID: UUID(), title: "", deadline: date)
                chip {
                    Image(systemName: "calendar")
                    Text(DueFormat.label(preview))
                }
                .foregroundStyle(DueFormat.color(preview) == .secondary ? Color.secondary : DueFormat.color(preview))
            }
            ForEach(parsed.tagNames, id: \.self) { name in
                let existing = store.tags.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
                TagPill(name: existing?.name ?? name, color: existing?.color ?? .secondary, isNew: existing == nil)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            if let priority = parsed.priority {
                chip {
                    PriorityBars(priority: priority)
                    Text(priority.title)
                }
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    private func chip<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 4, content: content)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(RoundedRectangle(cornerRadius: 5).fill(Theme.fill))
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    private func submit(_ parsed: ParsedTask, target: Product?) {
        guard !parsed.title.isEmpty, let target else { return }
        store.addTask(
            parsed.title,
            to: target.id,
            deadline: parsed.deadline ?? deadline,
            priority: parsed.priority ?? .none,
            tagIDs: (defaultTagID.map { [$0] } ?? []) + parsed.tagNames.map { store.tag(named: $0).id }
        )
        text = ""
        focus.wrappedValue = true
    }
}

extension Notification.Name {
    /// Posted by the global hotkey: close any open task page and focus the add bar.
    static let focusAddTask = Notification.Name("focusAddTask")
}
