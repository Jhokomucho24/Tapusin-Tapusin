import SwiftUI
import Observation

@Observable
final class Store {
    var products: [Product] = []
    var tasks: [TaskItem] = []
    var tags: [Tag] = []
    /// Start of the current day. Ticks at midnight so date-based counts and lists refresh.
    var currentDay = Date().startOfDay

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let logosDir: URL
    @ObservationIgnored private let notesDir: URL
    @ObservationIgnored private var logoCache: [String: NSImage] = [:]
    @ObservationIgnored private var pendingSave: DispatchWorkItem?

    private struct Snapshot: Codable {
        var products: [Product]
        var tasks: [TaskItem]
        var tags: [Tag]?
    }

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("Tapusin-Tapusin", isDirectory: true)
        // Carry data over from the app's previous name.
        let legacyDir = support.appendingPathComponent("Muchotask", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path),
           FileManager.default.fileExists(atPath: legacyDir.path) {
            try? FileManager.default.moveItem(at: legacyDir, to: dir)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("data.json")
        logosDir = dir.appendingPathComponent("Logos", isDirectory: true)
        try? FileManager.default.createDirectory(at: logosDir, withIntermediateDirectories: true)
        notesDir = dir.appendingPathComponent("Notes", isDirectory: true)
        try? FileManager.default.createDirectory(at: notesDir, withIntermediateDirectories: true)
        load()
        startDayTicker()
    }

    @ObservationIgnored private var dayTimer: Timer?

    private func startDayTicker() {
        dayTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            let today = Date().startOfDay
            if today != self.currentDay { self.currentDay = today }
        }
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(Snapshot.self, from: data) else { return }
        products = snapshot.products
        tasks = snapshot.tasks
        tags = snapshot.tags ?? []
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    func saveNow() {
        pendingSave?.cancel()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(Snapshot(products: products, tasks: tasks, tags: tags)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: Products

    func product(_ id: UUID) -> Product? {
        products.first { $0.id == id }
    }

    @discardableResult
    func addProduct(named name: String) -> Product {
        let product = Product(name: name, colorIndex: products.count)
        products.append(product)
        scheduleSave()
        return product
    }

    func renameProduct(_ id: UUID, to name: String) {
        guard let i = products.firstIndex(where: { $0.id == id }) else { return }
        products[i].name = name
        scheduleSave()
    }

    func setColor(_ id: UUID, index: Int) {
        guard let i = products.firstIndex(where: { $0.id == id }) else { return }
        products[i].colorIndex = index
        scheduleSave()
    }

    func deleteProduct(_ id: UUID) {
        removeLogoFile(product(id)?.logoFile)
        for task in tasks where task.productID == id { removeNoteFile(task.id) }
        products.removeAll { $0.id == id }
        tasks.removeAll { $0.productID == id }
        scheduleSave()
    }

    // MARK: Tags

    func tag(_ id: UUID) -> Tag? {
        tags.first { $0.id == id }
    }

    /// Finds a tag by name (case-insensitive) or creates it.
    @discardableResult
    func tag(named name: String) -> Tag {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = tags.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return existing
        }
        let tag = Tag(name: trimmed, colorIndex: (tags.count + 3) % ProductPalette.colors.count)
        tags.append(tag)
        scheduleSave()
        return tag
    }

    func renameTag(_ id: UUID, to name: String) {
        guard let i = tags.firstIndex(where: { $0.id == id }) else { return }
        tags[i].name = name
        scheduleSave()
    }

    func setTagColor(_ id: UUID, index: Int) {
        guard let i = tags.firstIndex(where: { $0.id == id }) else { return }
        tags[i].colorIndex = index
        scheduleSave()
    }

    func deleteTag(_ id: UUID) {
        tags.removeAll { $0.id == id }
        for i in tasks.indices where tasks[i].tags.contains(id) {
            tasks[i].tagIDs = tasks[i].tags.filter { $0 != id }
        }
        scheduleSave()
    }

    func addTag(_ tagID: UUID, to taskID: UUID) {
        updateTasks([taskID]) { task in
            if !task.tags.contains(tagID) { task.tagIDs = task.tags + [tagID] }
        }
    }

    func toggleTag(_ tagID: UUID, on taskID: UUID) {
        updateTasks([taskID]) { task in
            task.tagIDs = task.tags.contains(tagID) ? task.tags.filter { $0 != tagID } : task.tags + [tagID]
        }
    }

    /// Tags in the order they were created, skipping deleted ones.
    func tags(for task: TaskItem) -> [Tag] {
        task.tags.compactMap(tag)
    }

    // MARK: Logos

    func logo(for product: Product) -> NSImage? {
        guard let file = product.logoFile else { return nil }
        if let cached = logoCache[file] { return cached }
        guard let image = NSImage(contentsOf: logosDir.appendingPathComponent(file)) else { return nil }
        logoCache[file] = image
        return image
    }

    /// Downscales the image to a small PNG in the Logos folder and assigns it to the product.
    @discardableResult
    func setLogo(_ id: UUID, from url: URL) -> Bool {
        guard let i = products.firstIndex(where: { $0.id == id }),
              let image = NSImage(contentsOf: url),
              let data = ImageUtils.encode(image, maxSide: 128, allowJPEG: false)?.data else { return false }
        let file = "\(id.uuidString)-\(UUID().uuidString.prefix(8)).png"
        do {
            try data.write(to: logosDir.appendingPathComponent(file), options: .atomic)
        } catch {
            return false
        }
        removeLogoFile(products[i].logoFile)
        products[i].logoFile = file
        scheduleSave()
        return true
    }

    func removeLogo(_ id: UUID) {
        guard let i = products.firstIndex(where: { $0.id == id }) else { return }
        removeLogoFile(products[i].logoFile)
        products[i].logoFile = nil
        scheduleSave()
    }

    private func removeLogoFile(_ file: String?) {
        guard let file else { return }
        logoCache[file] = nil
        try? FileManager.default.removeItem(at: logosDir.appendingPathComponent(file))
    }

    // MARK: Notes

    private func noteURL(_ id: UUID) -> URL {
        notesDir.appendingPathComponent("\(id.uuidString).rtfd")
    }

    /// Rich note body (text, headings, lists, images) stored as flat RTFD.
    func loadNote(_ id: UUID) -> NSAttributedString? {
        guard let data = try? Data(contentsOf: noteURL(id)) else { return nil }
        return NSAttributedString(rtfd: data, documentAttributes: nil)
    }

    /// Writes the note and refreshes the task's plain-text preview.
    func saveNote(_ id: UUID, _ text: NSAttributedString) {
        let range = NSRange(location: 0, length: text.length)
        if text.length == 0 {
            removeNoteFile(id)
        } else if let data = text.rtfd(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]) {
            try? data.write(to: noteURL(id), options: .atomic)
        }

        var preview = text.string
            .replacingOccurrences(of: "\u{FFFC}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if preview.isEmpty && text.length > 0 && text.containsAttachments(in: range) { preview = "Image" }
        preview = String(preview.prefix(280))
        // Checklist items are paragraphs starting with ☐ or ☑.
        var done = 0, total = 0
        (text.string as NSString).enumerateSubstrings(in: range, options: .byParagraphs) { line, _, _, _ in
            if line?.hasPrefix("☐") == true { total += 1 }
            if line?.hasPrefix("☑") == true { total += 1; done += 1 }
        }
        if let i = tasks.firstIndex(where: { $0.id == id }) {
            let newDone = total > 0 ? done : nil
            let newTotal = total > 0 ? total : nil
            if tasks[i].notes != preview || tasks[i].checklistDone != newDone || tasks[i].checklistTotal != newTotal {
                tasks[i].notes = preview
                tasks[i].checklistDone = newDone
                tasks[i].checklistTotal = newTotal
                scheduleSave()
            }
        }
    }

    private func removeNoteFile(_ id: UUID) {
        try? FileManager.default.removeItem(at: noteURL(id))
    }

    func openCount(for productID: UUID) -> Int {
        tasks.filter { $0.productID == productID && !$0.isDone }.count
    }

    // MARK: Tasks

    func addTask(_ title: String, to productID: UUID, deadline: Date? = nil, priority: Priority = .none, tagIDs: [UUID] = []) {
        var task = TaskItem(productID: productID, title: title, priority: priority, deadline: deadline)
        task.tagIDs = tagIDs.isEmpty ? nil : tagIDs
        tasks.append(task)
        scheduleSave()
    }

    /// Changes the same field on several tasks in one save.
    func updateTasks(_ ids: Set<UUID>, _ change: (inout TaskItem) -> Void) {
        for i in tasks.indices where ids.contains(tasks[i].id) {
            change(&tasks[i])
        }
        scheduleSave()
    }

    func moveTask(_ id: UUID, toProduct productID: UUID) {
        updateTasks([id]) { $0.productID = productID }
    }

    func snooze(_ ids: Set<UUID>, days: Int) {
        let date = Date().adding(days: days)
        updateTasks(ids) { $0.deadline = date }
    }

    /// Drag-and-drop reorder: puts `id` before `targetID` (or at the end) of `group` and renumbers it.
    /// Dropping into a different date group gives the task that group's deadline.
    func reorder(_ id: UUID, before targetID: UUID?, in group: [TaskItem]) {
        guard id != targetID, tasks.contains(where: { $0.id == id }) else { return }
        let joiningGroup = !group.contains { $0.id == id }
        let anchor = group.first { $0.id == targetID } ?? group.last
        var ids = group.map(\.id).filter { $0 != id }
        ids.insert(id, at: targetID.flatMap { ids.firstIndex(of: $0) } ?? ids.count)
        for (n, taskID) in ids.enumerated() {
            guard let i = tasks.firstIndex(where: { $0.id == taskID }) else { continue }
            tasks[i].sortIndex = Double(n)
            if taskID == id, joiningGroup, let anchor { tasks[i].deadline = anchor.deadline }
        }
        scheduleSave()
    }

    func updateTask(_ task: TaskItem) {
        guard let i = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var task = task
        if task.status != tasks[i].status {
            task.completedAt = task.status == .done ? Date() : nil
        }
        tasks[i] = task
        scheduleSave()
    }

    func setStatus(_ id: UUID, _ status: TaskStatus) {
        guard var task = tasks.first(where: { $0.id == id }) else { return }
        task.status = status
        updateTask(task)
    }

    func deleteTask(_ id: UUID) {
        removeNoteFile(id)
        tasks.removeAll { $0.id == id }
        scheduleSave()
    }

    func binding(for task: TaskItem) -> Binding<TaskItem> {
        Binding(
            get: { self.tasks.first { $0.id == task.id } ?? task },
            set: { self.updateTask($0) }
        )
    }

    // MARK: Queries

    func tasks(in selection: SidebarSelection) -> [TaskItem] {
        switch selection {
        case .product(let id):
            return tasks.filter { $0.productID == id }
        case .tag(let id):
            return tasks.filter { $0.tags.contains(id) }
        case .smart(.today):
            _ = currentDay
            return tasks.filter { $0.isDueToday || $0.isOverdue }
        case .smart(.overdue):
            _ = currentDay
            return tasks.filter(\.isOverdue)
        case .smart(.all):
            return tasks
        }
    }

    var overdueCount: Int { _ = currentDay; return tasks.filter(\.isOverdue).count }
    var dueTodayCount: Int { _ = currentDay; return tasks.filter(\.isDueToday).count }

    /// Shown as the menu bar badge.
    var attentionCount: Int { overdueCount + dueTodayCount }

    var openCount: Int { tasks.filter { !$0.isDone }.count }

    /// Open before done, then deadline (none last), then priority, then oldest.
    static func sortOrder(_ a: TaskItem, _ b: TaskItem) -> Bool {
        if a.isDone != b.isDone { return !a.isDone }
        switch (a.deadline?.startOfDay, b.deadline?.startOfDay) {
        case let (x?, y?) where x != y: return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: break
        }
        // Hand-ordered tasks keep their order and sit above ones never moved.
        switch (a.sortIndex, b.sortIndex) {
        case let (x?, y?) where x != y: return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: break
        }
        if a.priority != b.priority { return a.priority.rawValue > b.priority.rawValue }
        return a.createdAt < b.createdAt
    }
}

enum ImageUtils {
    /// Downscales to `maxSide` pixels; JPEG for opaque images when allowed, PNG otherwise.
    static func encode(_ image: NSImage, maxSide: CGFloat, allowJPEG: Bool = true) -> (data: Data, ext: String)? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = min(1, maxSide / CGFloat(max(cg.width, cg.height)))
        let width = max(1, Int(CGFloat(cg.width) * scale))
        let height = max(1, Int(CGFloat(cg.height) * scale))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let output = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: output)
        let opaque = [.none, .noneSkipFirst, .noneSkipLast].contains(cg.alphaInfo)
        if allowJPEG && opaque, let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
            return (jpeg, "jpg")
        }
        return rep.representation(using: .png, properties: [:]).map { ($0, "png") }
    }
}
