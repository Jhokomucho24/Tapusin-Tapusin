import SwiftUI

@main
struct TapusinTapusinApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // The UI lives in an AppKit status item + panel (see MenuBarController); this scene is never shown.
    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store()
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let saved = UserDefaults.standard.string(forKey: "appearance").flatMap(AppearanceMode.init) {
            NSApp.appearance = saved.nsAppearance
        }
        menuBar = MenuBarController(store: store)
        GlobalHotKey.shared.action = { MenuBarPanel.toggleForQuickAdd() }
        GlobalHotKey.shared.register(HotKeyChoice.saved)
        Notifier.shared.start(store: store)
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
    }
}

/// Owns the menu bar icon and the dropdown panel, so the app can open/close it directly
/// (the global shortcut and notifications need that; SwiftUI's MenuBarExtra has no API for it).
final class MenuBarController: NSObject {
    private let store: Store
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel: DropdownPanel

    init(store: Store) {
        self.store = store
        panel = DropdownPanel(rootView: AnyView(RootView().environment(store)))
        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
            button.toolTip = "Tapusin-Tapusin"
        }
        updateIcon()
        observeIcon()
        MenuBarPanel.controller = self

        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.close()
        }
    }

    var isOpen: Bool { panel.isVisible }

    @objc private func statusItemClicked() {
        isOpen ? close() : open()
    }

    func open() {
        guard let button = statusItem.button, let window = button.window else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        panel.show(below: anchor)
        button.highlight(true)
    }

    func close() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        statusItem.button?.highlight(false)
    }

    // MARK: Icon

    private func updateIcon() {
        statusItem.button?.image = MenuBarIcon.make(
            count: store.attentionCount,
            overdue: store.overdueCount > 0,
            allDone: !store.tasks.isEmpty && store.openCount == 0
        )
    }

    /// Re-draws the icon whenever the counts it shows change.
    private func observeIcon() {
        withObservationTracking {
            _ = store.attentionCount
            _ = store.overdueCount
            _ = store.openCount
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.updateIcon()
                self?.observeIcon()
            }
        }
    }
}

/// Borderless panel styled like a menu bar dropdown. It sizes itself to the SwiftUI content.
final class DropdownPanel: NSPanel {
    private var anchor: NSRect?

    init(rootView: AnyView) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 800, height: 540),
                   styleMask: [.borderless], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let content = rootView
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5)
            )
        let host = NSHostingController(rootView: AnyView(content))
        host.sizingOptions = [.preferredContentSize]
        contentViewController = host

        NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: self, queue: .main) { [weak self] _ in
            self?.reposition()
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Esc (when nothing inside handled it) closes the dropdown.
    override func cancelOperation(_ sender: Any?) {
        MenuBarPanel.controller?.close()
    }

    func show(below anchor: NSRect) {
        self.anchor = anchor
        reposition()
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    /// Centers under the menu bar icon, kept on screen; called again when the content resizes.
    private func reposition() {
        guard let anchor else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = frame.size
        let x = min(max(anchor.midX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
        let y = anchor.minY - size.height - 6
        setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
    }
}

/// Menu bar icon: checklist glyph, a red pill when anything is overdue, dimmed when everything is done.
/// Drawn lazily so the glyph matches the menu bar's own light/dark appearance.
enum MenuBarIcon {
    static func make(count: Int, overdue: Bool, allDone: Bool) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let symbol = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Tapusin-Tapusin")?
            .withSymbolConfiguration(config) ?? NSImage()
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        let text = count > 0 ? "\(count)" as NSString : nil
        let textSize = text?.size(withAttributes: [.font: font]) ?? .zero
        let pillWidth = max(15, textSize.width + 8)
        let height: CGFloat = 18
        let width = symbol.size.width + (text == nil ? 0 : 3 + pillWidth)

        let image = NSImage(size: NSSize(width: ceil(width), height: height), flipped: false) { _ in
            let dark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let ink = (dark ? NSColor.white : NSColor.black).withAlphaComponent(allDone ? 0.45 : 1)

            let symbolRect = NSRect(x: 0, y: (height - symbol.size.height) / 2, width: symbol.size.width, height: symbol.size.height)
            tinted(symbol, ink).draw(in: symbolRect)

            if let text {
                let pill = NSRect(x: symbol.size.width + 3, y: (height - 15) / 2, width: pillWidth, height: 15)
                let color: NSColor
                if overdue {
                    NSColor.systemRed.setFill()
                    NSBezierPath(roundedRect: pill, xRadius: 7.5, yRadius: 7.5).fill()
                    color = .white
                } else {
                    color = ink
                }
                let origin = NSPoint(x: pill.midX - textSize.width / 2, y: pill.midY - textSize.height / 2)
                text.draw(at: origin, withAttributes: [.font: font, .foregroundColor: color])
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}
