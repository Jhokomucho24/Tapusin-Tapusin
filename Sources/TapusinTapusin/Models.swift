import SwiftUI

enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case todo, inProgress, blocked, done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .todo: "To Do"
        case .inProgress: "In Progress"
        case .blocked: "Blocked"
        case .done: "Done"
        }
    }

    var color: Color {
        switch self {
        case .todo: .gray
        case .inProgress: Theme.progress
        case .blocked: Theme.red
        case .done: Theme.green
        }
    }

    var icon: String {
        switch self {
        case .todo: "circle"
        case .inProgress: "circle.lefthalf.filled"
        case .blocked: "exclamationmark.octagon.fill"
        case .done: "checkmark.circle.fill"
        }
    }

    /// The status a single click moves to.
    var next: TaskStatus {
        switch self {
        case .todo: .inProgress
        case .inProgress: .done
        case .blocked: .inProgress
        case .done: .todo
        }
    }
}

enum Priority: Int, Codable, CaseIterable, Identifiable {
    case none = -1, low, medium, high

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .none: "None"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    var color: Color {
        switch self {
        case .none, .low: .secondary
        case .medium: .orange
        case .high: Theme.red
        }
    }

    /// Filled bars in the 3-bar priority meter.
    var bars: Int { rawValue + 1 }
}

enum ProductPalette {
    static let colors: [(name: String, color: Color)] = [
        ("Blue", .blue), ("Purple", .purple), ("Pink", .pink), ("Red", .red),
        ("Orange", .orange), ("Yellow", .yellow), ("Green", .green), ("Teal", .teal), ("Gray", .gray),
    ]

    static func color(_ index: Int) -> Color {
        colors[((index % colors.count) + colors.count) % colors.count].color
    }
}

struct Product: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var colorIndex: Int
    var createdAt = Date()
    /// File name inside the Logos folder; nil shows the letter badge.
    var logoFile: String?

    var color: Color { ProductPalette.color(colorIndex) }
    var tint: Color { color.opacity(0.18) }

    /// Letter shown in the product's badge ("Product A" → "A").
    var initial: String {
        let trimmed = name.hasPrefix("Product ") ? String(name.dropFirst("Product ".count)) : name
        return trimmed.first.map { String($0).uppercased() } ?? "?"
    }
}

struct Tag: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var colorIndex: Int

    var color: Color { ProductPalette.color(colorIndex) }
}

struct TaskItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var productID: UUID
    var title: String
    var notes = ""
    var status: TaskStatus = .todo
    var priority: Priority = .none
    var deadline: Date?
    var createdAt = Date()
    var completedAt: Date?
    /// Manual order set by drag and drop; nil falls back to priority order.
    var sortIndex: Double?
    /// Checklist progress from the note ("☐ / ☑" items); nil when the note has no checklist.
    var checklistDone: Int?
    var checklistTotal: Int?
    /// Optional so data saved before tags existed still loads.
    var tagIDs: [UUID]?

    var tags: [UUID] { tagIDs ?? [] }

    var isDone: Bool { status == .done }

    /// Whole days from today to the deadline (negative when past).
    var daysUntilDeadline: Int? {
        guard let deadline else { return nil }
        return Calendar.current.dateComponents([.day], from: Date().startOfDay, to: deadline.startOfDay).day
    }

    var isOverdue: Bool { !isDone && (daysUntilDeadline ?? 0) < 0 }
    var isDueToday: Bool { !isDone && daysUntilDeadline == 0 }
}

enum SmartList: String, CaseIterable, Identifiable {
    case today, all, overdue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .all: "All tasks"
        case .overdue: "Overdue"
        }
    }

    var emptyMessage: String {
        switch self {
        case .today: "Nothing due today."
        case .all: "No tasks yet."
        case .overdue: "No overdue tasks. Nice."
        }
    }
}

enum ViewMode: String {
    case full, compact
}

enum SidebarSelection: Hashable {
    case smart(SmartList)
    case product(UUID)
    case tag(UUID)
}

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }

    func adding(days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: startOfDay) ?? self
    }
}

// MARK: Theme preferences

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

enum AccentChoice: String, CaseIterable, Identifiable {
    case graphite, blue, purple, pink, orange, green

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    /// Graphite follows the text color (black in light, white in dark), matching the original design.
    var color: Color {
        switch self {
        case .graphite: .primary
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .orange: .orange
        case .green: Theme.green
        }
    }

    /// Text drawn on top of `color`.
    var onColor: Color {
        self == .graphite ? Color(nsColor: .windowBackgroundColor) : .white
    }
}

private struct AppAccentKey: EnvironmentKey {
    static let defaultValue = AccentChoice.graphite
}

extension EnvironmentValues {
    var appAccent: AccentChoice {
        get { self[AppAccentKey.self] }
        set { self[AppAccentKey.self] = newValue }
    }
}
