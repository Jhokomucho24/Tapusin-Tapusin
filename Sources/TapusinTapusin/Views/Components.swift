import SwiftUI
import UniformTypeIdentifiers

/// `@State` is a macro in the current SDK whose plugin ships only with Xcode.
/// Aliasing the underlying property wrapper lets the app build with Command Line Tools alone.
typealias Local<Value> = SwiftUI.State<Value>

enum Theme {
    static let red = Color(red: 0.80, green: 0.24, blue: 0.21)
    static let amber = Color(red: 0.72, green: 0.47, blue: 0.13)
    static let progress = Color(red: 0.91, green: 0.64, blue: 0.22)
    static let green = Color(red: 0.27, green: 0.66, blue: 0.43)
    static let card = dynamic(light: .white, dark: NSColor(white: 0.19, alpha: 1))
    static let hairline = Color.primary.opacity(0.07)
    static let fill = Color.primary.opacity(0.05)
    /// Opaque panel background: solid white in light mode, solid dark gray in dark mode.
    static let surface = dynamic(light: .white, dark: NSColor(white: 0.13, alpha: 1))

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

// MARK: Status checkbox

/// Round checkbox: empty for To Do, half-filled for In Progress, green check for Done.
/// Click advances the status; right-click picks any status.
struct StatusCheck: View {
    let status: TaskStatus
    var size: CGFloat = 17
    let onChange: (TaskStatus) -> Void

    var body: some View {
        Button {
            onChange(status.next)
        } label: {
            ZStack {
                switch status {
                case .todo:
                    Circle().strokeBorder(Color(nsColor: .tertiaryLabelColor), lineWidth: 1.5)
                case .inProgress:
                    Circle().strokeBorder(Theme.progress, lineWidth: 1.5)
                    RightHalfCircle().fill(Theme.progress).padding(3.5)
                case .blocked:
                    Circle().strokeBorder(Theme.red, lineWidth: 1.5)
                    Image(systemName: "minus")
                        .font(.system(size: size * 0.5, weight: .heavy))
                        .foregroundStyle(Theme.red)
                case .done:
                    Circle().fill(Theme.green)
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.5, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("\(status.title) — click to mark \(status.next.title)")
        .contextMenu {
            ForEach(TaskStatus.allCases) { s in
                Button { onChange(s) } label: { Label(s.title, systemImage: s.icon) }
            }
        }
    }
}

private struct RightHalfCircle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        p.move(to: c)
        p.addArc(center: c, radius: min(rect.width, rect.height) / 2,
                 startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
        p.closeSubpath()
        return p
    }
}

// MARK: Product marks

/// The product's logo, or a tinted square with its letter when no logo is set.
struct ProductBadge: View {
    @Environment(Store.self) private var store
    let product: Product
    var size: CGFloat = 16
    var circle = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: circle ? size / 2 : size * 0.3, style: .continuous)
        if let logo = store.logo(for: product) {
            // Square-ish logos fill the badge; wide or tall ones fit inside it.
            let ratio = logo.size.width / max(logo.size.height, 1)
            Image(nsImage: logo)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: (0.8...1.25).contains(ratio) ? .fill : .fit)
                .frame(width: size, height: size)
                .background(Color.white)
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        } else {
            Text(product.initial)
                .font(.system(size: size * 0.56, weight: .bold))
                .foregroundStyle(product.color)
                .frame(width: size, height: size)
                .background(shape.fill(product.tint))
        }
    }
}

/// Product avatar you can click to upload a logo, or drop an image onto.
struct EditableProductAvatar: View {
    @Environment(Store.self) private var store
    let product: Product
    var size: CGFloat = 28

    @Local private var isHovering = false
    @Local private var isDropTargeted = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        Button {
            DispatchQueue.main.async { LogoPicker.choose(for: product, store: store) }
        } label: {
            ProductBadge(product: product, size: size)
                .overlay {
                    if isHovering || isDropTargeted {
                        ZStack {
                            shape.fill(Color.black.opacity(0.45))
                            Image(systemName: "camera.fill")
                                .font(.system(size: size * 0.38))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .overlay(shape.strokeBorder(Color.accentColor, lineWidth: isDropTargeted ? 2 : 0))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help(product.logoFile == nil ? "Upload a logo (click or drop an image)" : "Change logo (click or drop an image)")
        .contextMenu { ProductLogoMenuItems(product: product) }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            return store.setLogo(product.id, from: url)
        } isTargeted: { isDropTargeted = $0 }
    }
}

/// "Set Logo…" / "Remove Logo" items for a product's context menu.
struct ProductLogoMenuItems: View {
    @Environment(Store.self) private var store
    let product: Product

    var body: some View {
        Button(product.logoFile == nil ? "Set Logo…" : "Change Logo…") {
            // Let the context menu close before the modal panel opens.
            DispatchQueue.main.async { LogoPicker.choose(for: product, store: store) }
        }
        if product.logoFile != nil {
            Button("Remove Logo") { store.removeLogo(product.id) }
        }
    }
}

enum LogoPicker {
    static func choose(for product: Product, store: Store) {
        let panel = NSOpenPanel()
        panel.title = "Choose a logo for \(product.name)"
        panel.prompt = "Use as Logo"
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        // Keep the panel above the menu bar popover.
        panel.level = .popUpMenu
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            store.setLogo(product.id, from: url)
        }
    }
}

// MARK: Drag and drop

/// Task drags carry "tapusin-task:<uuid>" as plain text so stray text drops are ignored.
enum TaskDrag {
    private static let prefix = "tapusin-task:"

    static func provider(_ id: UUID) -> NSItemProvider {
        NSItemProvider(object: (prefix + id.uuidString) as NSString)
    }

    static func loadTaskID(_ providers: [NSItemProvider], _ completion: @escaping (UUID) -> Void) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = object as? String, text.hasPrefix(prefix),
                  let id = UUID(uuidString: String(text.dropFirst(prefix.count))) else { return }
            DispatchQueue.main.async { completion(id) }
        }
        return true
    }
}

extension View {
    /// A product accepts a dragged task (moves it there) or an image file (becomes its logo).
    func productDropTarget(_ product: Product, store: Store, isTargeted: Binding<Bool>? = nil) -> some View {
        onDrop(of: [.fileURL, .plainText], isTargeted: isTargeted) { providers in
            if let file = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
                _ = file.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { store.setLogo(product.id, from: url) }
                }
                return true
            }
            return TaskDrag.loadTaskID(providers) { store.moveTask($0, toProduct: product.id) }
        }
    }
}

// MARK: Tags

struct TagPill: View {
    let name: String
    let color: Color
    /// Dashed outline for a tag that will be created on save.
    var isNew = false

    var body: some View {
        Text(name)
            .font(.system(size: 10.5, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .frame(height: 17)
            .background(Capsule().fill(color.opacity(isNew ? 0.06 : 0.14)))
            .overlay(
                Capsule().strokeBorder(color.opacity(0.5), style: StrokeStyle(lineWidth: 0.8, dash: [2, 2]))
                    .opacity(isNew ? 1 : 0)
            )
    }
}

/// A task's tags as pills, showing at most `limit` and "+N" for the rest.
struct TaskTagsView: View {
    @Environment(Store.self) private var store
    let task: TaskItem
    var limit = 2

    var body: some View {
        let tags = store.tags(for: task)
        if !tags.isEmpty {
            HStack(spacing: 4) {
                ForEach(tags.prefix(limit)) { TagPill(name: $0.name, color: $0.color) }
                if tags.count > limit {
                    Text("+\(tags.count - limit)")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .help(tags.dropFirst(limit).map(\.name).joined(separator: ", "))
                }
            }
        }
    }
}

/// Searchable tag list with "Create …" for the task page's Tags chip.
struct TagPicker: View {
    @Environment(Store.self) private var store
    let task: TaskItem

    @Local private var query = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let matches = store.tags.filter { trimmed.isEmpty || $0.name.localizedCaseInsensitiveContains(trimmed) }
        let exact = store.tags.contains { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }

        VStack(alignment: .leading, spacing: 0) {
            TextField("Search or create a tag…", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit {
                    if let first = matches.first, !trimmed.isEmpty, exact || matches.count == 1 {
                        store.toggleTag(first.id, on: task.id)
                    } else if !trimmed.isEmpty {
                        store.addTag(store.tag(named: trimmed).id, to: task.id)
                    }
                    query = ""
                }
                .padding(4)

            ForEach(matches) { tag in
                OptionRow(title: tag.name, isSelected: task.tags.contains(tag.id)) {
                    Image(systemName: "tag.fill").font(.system(size: 11)).foregroundStyle(tag.color)
                } action: {
                    store.toggleTag(tag.id, on: task.id)
                }
            }
            if !trimmed.isEmpty && !exact {
                OptionRow(title: "Create “\(trimmed)”") {
                    Image(systemName: "plus").font(.system(size: 11)).foregroundStyle(.secondary)
                } action: {
                    store.addTag(store.tag(named: trimmed).id, to: task.id)
                    query = ""
                }
            }
            if store.tags.isEmpty && trimmed.isEmpty {
                Text("Type a name to create your first tag.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
        }
        .frame(width: 230)
        .onAppear { isFocused = true }
    }
}

/// "2/5" checklist progress from the task's note.
struct ChecklistBadge: View {
    let task: TaskItem

    var body: some View {
        if let total = task.checklistTotal, let done = task.checklistDone {
            let complete = done == total
            HStack(spacing: 3) {
                Image(systemName: complete ? "checkmark.circle.fill" : "checklist")
                    .font(.system(size: 10))
                Text("\(done)/\(total)").monospacedDigit()
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(complete ? Theme.green : Color.secondary)
            .help("\(done) of \(total) checklist items done")
        }
    }
}

struct ColorDot: View {
    let color: Color
    var size: CGFloat = 9

    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
    }
}

/// Three ascending bars; red when high priority.
struct PriorityBars: View {
    let priority: Priority

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(barColor(i))
                    .frame(width: 3, height: CGFloat(5 + i * 3))
            }
        }
        .frame(width: 13, height: 11, alignment: .bottom)
        .help("\(priority.title) priority")
    }

    private func barColor(_ index: Int) -> Color {
        guard index < priority.bars else { return Color.primary.opacity(0.1) }
        return priority == .high ? Theme.red : Color.secondary
    }
}

// MARK: Due dates

enum DueBucket: Int, Comparable {
    case overdue, today, tomorrow, thisWeek, later, noDate, earlier

    static func < (a: DueBucket, b: DueBucket) -> Bool { a.rawValue < b.rawValue }

    init(_ task: TaskItem) {
        guard let days = task.daysUntilDeadline else { self = .noDate; return }
        switch days {
        case ..<0: self = task.isDone ? .earlier : .overdue
        case 0: self = .today
        case 1: self = .tomorrow
        case 2...6: self = .thisWeek
        default: self = .later
        }
    }

    var title: String {
        switch self {
        case .overdue: "Overdue"
        case .today: "Today"
        case .tomorrow: "Tomorrow"
        case .thisWeek: "This week"
        case .later: "Later"
        case .noDate: "No date"
        case .earlier: "Earlier"
        }
    }
}

enum DueFormat {
    static func label(_ task: TaskItem) -> String {
        guard let deadline = task.deadline, let days = task.daysUntilDeadline else { return "No date" }
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case ..<(-1): return "\(-days) days ago"
        case 2...6: return deadline.formatted(.dateTime.weekday(.wide))
        default: return deadline.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    static func color(_ task: TaskItem) -> Color {
        if task.isOverdue { return Theme.red }
        if task.isDueToday { return Theme.amber }
        return .secondary
    }
}

// MARK: Controls

/// Pill segmented control from the 1a header.
struct SegmentedPills<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let isOn = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isOn ? .primary : .secondary)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isOn ? Theme.card : .clear)
                                .shadow(color: .black.opacity(isOn ? 0.1 : 0), radius: 1, y: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.fill))
    }
}

/// A small rounded chip that opens a popover of options.
struct PropertyChip<Label: View, Content: View>: View {
    @Binding var isPresented: Bool
    @ViewBuilder let label: () -> Label
    @ViewBuilder let content: () -> Content

    @Local private var isHovering = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            label()
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(isHovering || isPresented ? 0.08 : 0.05))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(5)
                .frame(minWidth: 170)
        }
    }
}

/// One selectable row inside a PropertyChip popover.
struct OptionRow<Leading: View>: View {
    let title: String
    var isSelected = false
    @ViewBuilder let leading: () -> Leading
    let action: () -> Void

    @Local private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                leading().frame(width: 16)
                Text(title).font(.system(size: 13))
                Spacer(minLength: 12)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 5).fill(isHovering ? Color.primary.opacity(0.07) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

extension OptionRow where Leading == EmptyView {
    init(title: String, isSelected: Bool = false, action: @escaping () -> Void) {
        self.init(title: title, isSelected: isSelected, leading: { EmptyView() }, action: action)
    }
}

/// Small keycap hint, e.g. ⌘N.
struct KeyHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
    }
}

extension View {
    /// Status / priority / deadline / delete actions shared by every task row.
    func taskContextMenu(_ task: TaskItem, store: Store) -> some View {
        contextMenu {
            if task.isOverdue {
                Button("Move to Today") { store.snooze([task.id], days: 0) }
            }
            if !task.isDone && (task.isOverdue || task.isDueToday) {
                Button("Snooze to Tomorrow") { store.snooze([task.id], days: 1) }
                Divider()
            }
            Menu("Status") {
                ForEach(TaskStatus.allCases) { s in
                    Button(s.title + (task.status == s ? "  ✓" : "")) { store.setStatus(task.id, s) }
                }
            }
            if !store.tags.isEmpty {
                Menu("Tags") {
                    ForEach(store.tags) { tag in
                        Button(tag.name + (task.tags.contains(tag.id) ? "  ✓" : "")) {
                            store.toggleTag(tag.id, on: task.id)
                        }
                    }
                }
            }
            Menu("Priority") {
                ForEach(Priority.allCases) { p in
                    Button(p.title + (task.priority == p ? "  ✓" : "")) {
                        var t = task; t.priority = p; store.updateTask(t)
                    }
                }
            }
            Menu("Deadline") {
                Button("Today") { var t = task; t.deadline = Date().startOfDay; store.updateTask(t) }
                Button("Tomorrow") { var t = task; t.deadline = Date().adding(days: 1); store.updateTask(t) }
                Button("Next week") { var t = task; t.deadline = Date().adding(days: 7); store.updateTask(t) }
                Divider()
                Button("No date") { var t = task; t.deadline = nil; store.updateTask(t) }
            }
            Divider()
            Button("Delete Task", role: .destructive) { store.deleteTask(task.id) }
        }
    }
}

/// Invisible button that only exists to register a keyboard shortcut.
struct ShortcutButton: View {
    let key: KeyEquivalent
    var modifiers: EventModifiers = .command
    let action: () -> Void

    var body: some View {
        Button("", action: action)
            .keyboardShortcut(key, modifiers: modifiers)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }
}
