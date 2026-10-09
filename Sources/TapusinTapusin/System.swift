import AppKit
import Carbon.HIToolbox
import UserNotifications

// MARK: - Global hotkey

enum HotKeyChoice: String, CaseIterable, Identifiable {
    case off, optionSpace, controlOptionSpace, optionCommandT

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .optionSpace: "⌥ Space"
        case .controlOptionSpace: "⌃⌥ Space"
        case .optionCommandT: "⌥⌘ T"
        }
    }

    fileprivate var keyCode: UInt32 {
        switch self {
        case .off: 0
        case .optionSpace, .controlOptionSpace: UInt32(kVK_Space)
        case .optionCommandT: UInt32(kVK_ANSI_T)
        }
    }

    fileprivate var modifiers: UInt32 {
        switch self {
        case .off: 0
        case .optionSpace: UInt32(optionKey)
        case .controlOptionSpace: UInt32(controlKey | optionKey)
        case .optionCommandT: UInt32(optionKey | cmdKey)
        }
    }

    static let defaultsKey = "hotKey"

    static var saved: HotKeyChoice {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(HotKeyChoice.init) ?? .optionSpace
    }
}

/// System-wide shortcut via Carbon's RegisterEventHotKey (needs no Accessibility permission).
final class GlobalHotKey {
    static let shared = GlobalHotKey()

    var action: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    func register(_ choice: HotKeyChoice) {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        guard choice != .off else { return }
        installHandler()
        let id = EventHotKeyID(signature: OSType(0x4D55_4348), id: 1) // "MUCH"
        RegisterEventHotKey(choice.keyCode, choice.modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    private func installHandler() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { GlobalHotKey.shared.action?() }
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }
}

// MARK: - Menu bar panel

/// Entry points for opening the dropdown from the hotkey and notifications.
enum MenuBarPanel {
    static weak var controller: MenuBarController?

    /// Global shortcut: open with the add bar focused, or close if already open.
    static func toggleForQuickAdd() {
        guard let controller else { return }
        if controller.isOpen && NSApp.isActive {
            controller.close()
            return
        }
        controller.open()
        NotificationCenter.default.post(name: .focusAddTask, object: nil)
    }

    static func open() {
        controller?.open()
    }
}

// MARK: - Notifications

enum NotifyPrefs {
    static let summaryKey = "notifySummary"
    static let summaryHourKey = "notifySummaryHour"
    static let overdueKey = "notifyOverdue"

    static var summary: Bool { UserDefaults.standard.object(forKey: summaryKey) as? Bool ?? true }
    static var summaryHour: Int { UserDefaults.standard.object(forKey: summaryHourKey) as? Int ?? 9 }
    static var overdue: Bool { UserDefaults.standard.object(forKey: overdueKey) as? Bool ?? true }
}

/// Morning summary and "just became overdue" alerts. The app is always running, so it checks every minute.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    private weak var store: Store?
    private var timer: Timer?
    private let center = UNUserNotificationCenter.current()
    private let lastSummaryKey = "lastSummaryDay"
    private let alertedKey = "overdueAlerted"

    func start(store: Store) {
        self.store = store
        center.delegate = self
        requestPermissionIfNeeded()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.check() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.check() }
    }

    func requestPermissionIfNeeded() {
        guard NotifyPrefs.summary || NotifyPrefs.overdue else { return }
        center.requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error { NSLog("Tapusin-Tapusin: notification permission error: \(error)") }
        }
    }

    private func check() {
        guard let store else { return }
        let now = Date()
        let today = now.startOfDay
        let defaults = UserDefaults.standard

        if NotifyPrefs.summary,
           Calendar.current.component(.hour, from: now) >= NotifyPrefs.summaryHour,
           (defaults.object(forKey: lastSummaryKey) as? Date).map({ $0 < today }) ?? true {
            defaults.set(today, forKey: lastSummaryKey)
            sendSummary(store: store, skipIfEmpty: true)
        }

        if NotifyPrefs.overdue {
            // Only tasks that became overdue today (due yesterday), each alerted once.
            var alerted = Set(defaults.stringArray(forKey: alertedKey) ?? [])
            let fresh = store.tasks.filter { $0.isOverdue && $0.daysUntilDeadline == -1 && !alerted.contains($0.id.uuidString) }
            if !fresh.isEmpty {
                let body = fresh.prefix(4).map { "• \($0.title)" }.joined(separator: "\n")
                post(title: fresh.count == 1 ? "1 task is now overdue" : "\(fresh.count) tasks are now overdue",
                     body: body + (fresh.count > 4 ? "\n…and \(fresh.count - 4) more" : ""),
                     id: "overdue-\(today.timeIntervalSince1970)")
                fresh.forEach { alerted.insert($0.id.uuidString) }
                let live = Set(store.tasks.map(\.id.uuidString))
                defaults.set(Array(alerted.intersection(live)), forKey: alertedKey)
            }
        }
    }

    /// Today's plan: overdue first, then due today, highest priority first.
    func sendSummary(store: Store, skipIfEmpty: Bool = false) {
        let due = store.tasks(in: .smart(.today)).sorted(by: Store.sortOrder)
        if due.isEmpty && skipIfEmpty { return }
        let overdue = due.filter(\.isOverdue).count
        let title: String
        if due.isEmpty {
            title = "Nothing due today"
        } else {
            title = "Good morning — \(due.count) task\(due.count == 1 ? "" : "s") today"
        }
        var lines: [String] = []
        if overdue > 0 { lines.append("\(overdue) overdue · \(due.count - overdue) due today") }
        lines += due.prefix(4).map { task in
            let product = store.product(task.productID)?.name ?? ""
            return "• \(task.title)\(product.isEmpty ? "" : " — \(product)")"
        }
        if due.count > 4 { lines.append("…and \(due.count - 4) more") }
        post(title: title, body: lines.isEmpty ? "Enjoy the clear day." : lines.joined(separator: "\n"), id: "summary-\(Date().timeIntervalSince1970)")
    }

    private func post(title: String, body: String, id: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { error in
            if let error { NSLog("Tapusin-Tapusin: notification failed: \(error)") }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async { MenuBarPanel.open() }
        completionHandler()
    }
}

