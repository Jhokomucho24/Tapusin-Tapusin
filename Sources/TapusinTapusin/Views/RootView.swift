import ServiceManagement
import SwiftUI

struct RootView: View {
    @Environment(Store.self) private var store
    @AppStorage("viewMode") private var mode: ViewMode = .full
    @AppStorage("appearance") private var appearance: AppearanceMode = .system
    @AppStorage("accent") private var accent: AccentChoice = .graphite
    @Local private var productToDelete: Product?

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch mode {
                case .full: FullView(productToDelete: $productToDelete)
                case .compact: CompactView(productToDelete: $productToDelete)
                }
            }
            .frame(maxHeight: .infinity)

            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
            FooterBar(mode: $mode)
        }
        .frame(width: mode == .full ? 800 : 380, height: mode == .full ? 540 : 580)
        .background(Theme.surface)
        .overlay {
            if let product = productToDelete {
                DeleteProductConfirm(product: product, taskCount: store.tasks(in: .product(product.id)).count) {
                    productToDelete = nil
                } onDelete: {
                    store.deleteProduct(product.id)
                    productToDelete = nil
                }
            }
        }
        .environment(\.appAccent, accent)
        .tint(accent == .graphite ? nil : accent.color)
        .onAppear { NSApp.appearance = appearance.nsAppearance }
        .onChange(of: appearance) { NSApp.appearance = appearance.nsAppearance }
        .background {
            ShortcutButton(key: "1") { mode = .full }
            ShortcutButton(key: "2") { mode = .compact }
        }
    }
}

private struct FooterBar: View {
    @Environment(Store.self) private var store
    @Binding var mode: ViewMode
    @AppStorage("appearance") private var appearance: AppearanceMode = .system
    @AppStorage("accent") private var accent: AccentChoice = .graphite
    @AppStorage(HotKeyChoice.defaultsKey) private var hotKey: HotKeyChoice = .optionSpace
    @AppStorage(NotifyPrefs.summaryKey) private var notifySummary = true
    @AppStorage(NotifyPrefs.summaryHourKey) private var summaryHour = 9
    @AppStorage(NotifyPrefs.overdueKey) private var notifyOverdue = true
    @Local private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        HStack(spacing: 12) {
            if mode == .full {
                Text("Tapusin-Tapusin").fontWeight(.medium)
            }
            summary
            Spacer()
            ViewSwitcher(mode: $mode)
            Menu {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                }
                Picker("Accent", selection: $accent) {
                    ForEach(AccentChoice.allCases) { Text($0.title).tag($0) }
                }
                Divider()
                Picker("Quick add shortcut", selection: $hotKey) {
                    ForEach(HotKeyChoice.allCases) { Text($0.title).tag($0) }
                }
                Menu("Notifications") {
                    Toggle("Morning summary", isOn: $notifySummary)
                    Picker("Summary time", selection: $summaryHour) {
                        ForEach([7, 8, 9, 10, 11], id: \.self) { hour in
                            Text(hourLabel(hour)).tag(hour)
                        }
                    }
                    .disabled(!notifySummary)
                    Toggle("Alert when a task becomes overdue", isOn: $notifyOverdue)
                    Divider()
                    Button("Send today’s summary now") { Notifier.shared.sendSummary(store: store) }
                }
                Divider()
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            Button("Quit") {
                store.saveNow()
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
        }
        .font(.system(size: 11.5))
        .foregroundStyle(.secondary)
        .onChange(of: hotKey) { GlobalHotKey.shared.register(hotKey) }
        .onChange(of: notifySummary) { Notifier.shared.requestPermissionIfNeeded() }
        .onChange(of: notifyOverdue) { Notifier.shared.requestPermissionIfNeeded() }
        .padding(.horizontal, mode == .full ? 12 : 14)
        .frame(height: mode == .full ? 28 : 30)
    }

    @ViewBuilder private var summary: some View {
        let open = store.openCount
        let overdue = store.overdueCount
        HStack(spacing: 6) {
            Text(open > 0 ? "\(open) open" : "All caught up")
            if overdue > 0 {
                Text("· \(overdue) overdue").foregroundStyle(Theme.red)
            }
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        var comps = DateComponents()
        comps.hour = hour
        let date = Calendar.current.date(from: comps) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Tapusin-Tapusin: launch at login failed: \(error)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

/// Footer toggle between the 1a sidebar layout and the 1b compact popover.
private struct ViewSwitcher: View {
    @Binding var mode: ViewMode

    var body: some View {
        HStack(spacing: 0) {
            option(.full, icon: "sidebar.left", help: "Sidebar view (⌘1)")
            option(.compact, icon: "list.bullet", help: "Compact view (⌘2)")
        }
        .padding(1.5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.fill))
    }

    private func option(_ value: ViewMode, icon: String, help: String) -> some View {
        Button {
            mode = value
        } label: {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(mode == value ? .primary : .secondary)
                .frame(width: 24, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 4.5)
                        .fill(mode == value ? Theme.card : .clear)
                        .shadow(color: .black.opacity(mode == value ? 0.1 : 0), radius: 1, y: 0.5)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct DeleteProductConfirm: View {
    let product: Product
    let taskCount: Int
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .onTapGesture(perform: onCancel)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ProductBadge(product: product, size: 20)
                    Text("Delete “\(product.name)”?")
                        .font(.headline)
                }
                Text(taskCount == 0
                     ? "This product has no tasks."
                     : "This also deletes its \(taskCount) task\(taskCount == 1 ? "" : "s"). You can’t undo this.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .keyboardShortcut(.cancelAction)
                    Button("Delete", role: .destructive, action: onDelete)
                        .keyboardShortcut(.defaultAction)
                        .tint(.red)
                }
            }
            .padding(18)
            .frame(width: 320)
            .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial))
            .shadow(radius: 20, y: 6)
        }
    }
}
