import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum NoteBlock {
    case title, heading, body
}

enum NoteListKind {
    case bullet, number

    var format: NSTextList.MarkerFormat { self == .bullet ? .disc : .decimal }
}

enum NoteStyle {
    static let bodyFont = NSFont.systemFont(ofSize: 13.5)
    static let titleFont = NSFont.systemFont(ofSize: 20, weight: .bold)
    static let headingFont = NSFont.systemFont(ofSize: 15.5, weight: .semibold)

    static func font(for block: NoteBlock) -> NSFont {
        switch block {
        case .title: titleFont
        case .heading: headingFont
        case .body: bodyFont
        }
    }

    static func block(of font: NSFont?) -> NoteBlock {
        guard let size = font?.pointSize else { return .body }
        if size >= 19 { return .title }
        if size >= 15 { return .heading }
        return .body
    }

    static func paragraphStyle(block: NoteBlock = .body, list: NSTextList? = nil) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineHeightMultiple = 1.15
        p.paragraphSpacing = block == .body ? 4 : 2
        p.paragraphSpacingBefore = block == .body ? 0 : 8
        if let list {
            p.textLists = [list]
            p.tabStops = [NSTextTab(textAlignment: .left, location: 6), NSTextTab(textAlignment: .left, location: 24)]
            p.headIndent = 24
            p.paragraphSpacing = 2
        }
        return p
    }

    static func attributes(block: NoteBlock = .body, list: NSTextList? = nil) -> [NSAttributedString.Key: Any] {
        [
            .font: font(for: block),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle(block: block, list: list),
        ]
    }

    // MARK: Checklist

    static let unchecked = "☐"
    static let checked = "☑"
    private static let checkGreen = NSColor(red: 0.27, green: 0.66, blue: 0.43, alpha: 1)

    static var checklistParagraph: NSParagraphStyle {
        let p = paragraphStyle().mutableCopy() as! NSMutableParagraphStyle
        p.headIndent = 21
        p.paragraphSpacing = 3
        return p
    }

    static func checkboxAttributes(checked: Bool) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: checked ? checkGreen : NSColor.secondaryLabelColor,
            .paragraphStyle: checklistParagraph,
        ]
    }

    static var checklistBodyAttributes: [NSAttributedString.Key: Any] {
        var attrs = attributes()
        attrs[.paragraphStyle] = checklistParagraph
        return attrs
    }

    /// "☐ " (box + space) to put at the start of a checklist paragraph.
    static func checkboxPrefix(checked: Bool = false) -> NSAttributedString {
        let out = NSMutableAttributedString(string: checked ? self.checked : unchecked,
                                            attributes: checkboxAttributes(checked: checked))
        out.append(NSAttributedString(string: " ", attributes: checklistBodyAttributes))
        return out
    }

    /// 2 when `line` starts with "☐ " or "☑ ", otherwise 0.
    static func checklistPrefixLength(in line: NSString) -> Int {
        (line.hasPrefix(unchecked + " ") || line.hasPrefix(checked + " ")) ? 2 : 0
    }

    static func marker(_ list: NSTextList, number: Int) -> String {
        "\t\(list.marker(forItemNumber: number))\t"
    }

    /// RTFD keeps a paragraph's list but drops the visible "\t•\t" marker text, so restore it after loading.
    static func restoreListMarkers(in text: NSMutableAttributedString) {
        let ns = text.string as NSString
        var paragraphs: [NSRange] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byParagraphs, .substringNotRequired]) { _, r, _, _ in
            paragraphs.append(r)
        }
        for r in paragraphs.reversed() where r.length > 0 || r.location < text.length {
            guard r.location < text.length,
                  let style = text.attribute(.paragraphStyle, at: r.location, effectiveRange: nil) as? NSParagraphStyle,
                  let list = style.textLists.first,
                  markerLength(in: (text.string as NSString).substring(with: r) as NSString) == 0
            else { continue }
            let number = text.itemNumber(in: list, at: r.location)
            var attrs = text.attributes(at: r.location, effectiveRange: nil)
            attrs.removeValue(forKey: .attachment)
            text.insert(NSAttributedString(string: marker(list, number: number), attributes: attrs), at: r.location)
        }
    }

    /// Length of a "\t•\t" style list marker at the start of `line`, or 0.
    static func markerLength(in line: NSString) -> Int {
        guard line.length >= 2, line.character(at: 0) == 9 else { return 0 }
        let r = line.range(of: "\t", options: [], range: NSRange(location: 1, length: min(line.length - 1, 8)))
        return r.location == NSNotFound ? 0 : r.location + 1
    }
}

/// Bridges the SwiftUI formatting toolbar to the AppKit text view.
@Observable
final class NoteController {
    @ObservationIgnored weak var textView: NSTextView?

    var block: NoteBlock = .body
    var list: NoteListKind?
    var isChecklist = false
    var isBold = false
    var isItalic = false
    var isUnderline = false
    var isStrikethrough = false

    // MARK: State

    func refresh() {
        guard let tv = textView else { return }
        let attrs = tv.typingAttributes
        let font = attrs[.font] as? NSFont
        block = NoteStyle.block(of: font)
        let traits = font.map { NSFontManager.shared.traits(of: $0) } ?? []
        isBold = block == .body && traits.contains(.boldFontMask)
        isItalic = traits.contains(.italicFontMask)
        isUnderline = (attrs[.underlineStyle] as? Int ?? 0) != 0
        isStrikethrough = (attrs[.strikethroughStyle] as? Int ?? 0) != 0
        list = currentList(in: tv).map { $0.markerFormat == .decimal ? .number : .bullet }
        let ns = tv.string as NSString
        let para = ns.paragraphRange(for: NSRange(location: min(tv.selectedRange().location, ns.length), length: 0))
        isChecklist = NoteStyle.checklistPrefixLength(in: ns.substring(with: para) as NSString) > 0
    }

    private func currentList(in tv: NSTextView) -> NSTextList? {
        let storage = tv.textStorage!
        let para = (tv.string as NSString).paragraphRange(for: tv.selectedRange())
        let style: NSParagraphStyle?
        if para.location < storage.length {
            style = storage.attribute(.paragraphStyle, at: para.location, effectiveRange: nil) as? NSParagraphStyle
        } else {
            style = tv.typingAttributes[.paragraphStyle] as? NSParagraphStyle
        }
        return style?.textLists.first
    }

    // MARK: Helpers

    private func paragraphs(in tv: NSTextView) -> (whole: NSRange, ranges: [NSRange]) {
        let ns = tv.string as NSString
        let whole = ns.paragraphRange(for: tv.selectedRange())
        var ranges: [NSRange] = []
        ns.enumerateSubstrings(in: whole, options: [.byParagraphs, .substringNotRequired]) { _, r, _, _ in
            ranges.append(r)
        }
        if ranges.isEmpty { ranges = [NSRange(location: whole.location, length: 0)] }
        return (whole, ranges)
    }

    /// Replaces `range` with `text` as one undoable edit.
    private func replace(_ tv: NSTextView, _ range: NSRange, with text: NSAttributedString, caret: Int? = nil) {
        guard tv.shouldChangeText(in: range, replacementString: text.string) else { return }
        tv.textStorage?.replaceCharacters(in: range, with: text)
        tv.didChangeText()
        if let caret { tv.setSelectedRange(NSRange(location: caret, length: 0)) }
    }

    @discardableResult
    private func removeMarker(in text: NSMutableAttributedString, at location: Int, length: Int) -> Int {
        let line = (text.string as NSString).substring(with: NSRange(location: location, length: length)) as NSString
        var m = NoteStyle.markerLength(in: line)
        if m == 0 { m = NoteStyle.checklistPrefixLength(in: line) }
        if m > 0 { text.deleteCharacters(in: NSRange(location: location, length: m)) }
        return m
    }

    private func caretAtEnd(of range: NSRange, length: Int, in tv: NSTextView) -> Int {
        let end = range.location + length
        let ns = tv.string as NSString
        return end > range.location && end <= ns.length && ns.character(at: end - 1) == 10 ? end - 1 : end
    }

    private func focus() {
        guard let tv = textView else { return }
        tv.window?.makeFirstResponder(tv)
        refresh()
    }

    // MARK: Blocks

    func setBlock(_ block: NoteBlock) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        defer { focus() }
        let (whole, ranges) = paragraphs(in: tv)
        if whole.length == 0 {
            tv.typingAttributes = NoteStyle.attributes(block: block)
            return
        }
        let text = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: whole))
        for r in ranges.reversed() {
            removeMarker(in: text, at: r.location - whole.location, length: r.length)
        }
        let full = NSRange(location: 0, length: text.length)
        text.enumerateAttribute(.font, in: full) { value, r, _ in
            let font = value as? NSFont
            // Keep inline bold/italic when the paragraph is already body text.
            if block != .body || NoteStyle.block(of: font) != .body {
                text.addAttribute(.font, value: NoteStyle.font(for: block), range: r)
            }
        }
        text.addAttribute(.paragraphStyle, value: NoteStyle.paragraphStyle(block: block), range: full)
        text.addAttribute(.foregroundColor, value: NSColor.labelColor, range: full)
        replace(tv, whole, with: text, caret: nil)
        tv.setSelectedRange(NSRange(location: caretAtEnd(of: whole, length: text.length, in: tv), length: 0))
        tv.typingAttributes = NoteStyle.attributes(block: block)
    }

    // MARK: Lists

    func toggleList(_ kind: NoteListKind) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        defer { focus() }
        let (whole, ranges) = paragraphs(in: tv)
        let turningOff = currentList(in: tv)?.markerFormat == kind.format
        let list = NSTextList(markerFormat: kind.format, options: 0)
        let text = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: whole))

        for (i, r) in ranges.enumerated().reversed() {
            let loc = r.location - whole.location
            let removed = removeMarker(in: text, at: loc, length: r.length)
            let ns = text.string as NSString
            if turningOff {
                let para = ns.paragraphRange(for: NSRange(location: loc, length: 0))
                text.addAttribute(.paragraphStyle, value: NoteStyle.paragraphStyle(), range: para)
            } else {
                let marker = NSAttributedString(string: NoteStyle.marker(list, number: i + 1),
                                                attributes: NoteStyle.attributes(list: list))
                text.insert(marker, at: loc)
                let para = (text.string as NSString).paragraphRange(for: NSRange(location: loc, length: 0))
                text.addAttribute(.paragraphStyle, value: NoteStyle.paragraphStyle(list: list), range: para)
                // Lists are body text.
                let contentLength = r.length - removed
                if contentLength > 0 {
                    let content = NSRange(location: loc + marker.length, length: contentLength)
                    text.enumerateAttribute(.font, in: content) { value, fr, _ in
                        if NoteStyle.block(of: value as? NSFont) != .body {
                            text.addAttribute(.font, value: NoteStyle.bodyFont, range: fr)
                        }
                    }
                }
            }
        }
        replace(tv, whole, with: text)
        tv.setSelectedRange(NSRange(location: caretAtEnd(of: whole, length: text.length, in: tv), length: 0))
        tv.typingAttributes = NoteStyle.attributes(list: turningOff ? nil : list)
    }

    // MARK: Checklist

    func toggleChecklist() {
        guard let tv = textView, let storage = tv.textStorage else { return }
        defer { focus() }
        let (whole, ranges) = paragraphs(in: tv)
        let source = storage.string as NSString
        let allChecklist = ranges.allSatisfy {
            $0.length > 0 && NoteStyle.checklistPrefixLength(in: source.substring(with: $0) as NSString) > 0
        }
        let text = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: whole))

        for r in ranges.reversed() {
            let loc = r.location - whole.location
            if allChecklist {
                text.deleteCharacters(in: NSRange(location: loc, length: 2))
                let para = (text.string as NSString).paragraphRange(for: NSRange(location: loc, length: 0))
                text.addAttribute(.paragraphStyle, value: NoteStyle.paragraphStyle(), range: para)
                text.addAttribute(.foregroundColor, value: NSColor.labelColor, range: para)
                text.removeAttribute(.strikethroughStyle, range: para)
            } else {
                let line = (text.string as NSString).substring(with: NSRange(location: loc, length: r.length)) as NSString
                guard NoteStyle.checklistPrefixLength(in: line) == 0 else { continue }
                let removed = removeMarker(in: text, at: loc, length: r.length)
                text.insert(NoteStyle.checkboxPrefix(), at: loc)
                let para = (text.string as NSString).paragraphRange(for: NSRange(location: loc, length: 0))
                text.addAttribute(.paragraphStyle, value: NoteStyle.checklistParagraph, range: para)
                let contentLength = r.length - removed
                if contentLength > 0 {
                    let content = NSRange(location: loc + 2, length: contentLength)
                    text.enumerateAttribute(.font, in: content) { value, fr, _ in
                        if NoteStyle.block(of: value as? NSFont) != .body {
                            text.addAttribute(.font, value: NoteStyle.bodyFont, range: fr)
                        }
                    }
                }
            }
        }
        replace(tv, whole, with: text)
        tv.setSelectedRange(NSRange(location: caretAtEnd(of: whole, length: text.length, in: tv), length: 0))
        tv.typingAttributes = allChecklist ? NoteStyle.attributes() : NoteStyle.checklistBodyAttributes
    }

    /// Ticks or unticks the checkbox at `index`; ticked items are struck through and dimmed.
    func toggleCheckbox(at index: Int) {
        guard let tv = textView, let storage = tv.textStorage, index < storage.length else { return }
        let ns = storage.string as NSString
        let para = ns.paragraphRange(for: NSRange(location: index, length: 0))
        guard index == para.location,
              NoteStyle.checklistPrefixLength(in: ns.substring(with: para) as NSString) > 0 else { return }
        let nowChecked = ns.substring(with: NSRange(location: index, length: 1)) == NoteStyle.unchecked
        let endsWithNewline = para.length > 0 && ns.character(at: NSMaxRange(para) - 1) == 10
        let content = NSRange(location: para.location + 2, length: max(0, para.length - 2 - (endsWithNewline ? 1 : 0)))

        guard tv.shouldChangeText(in: para, replacementString: nil) else { return }
        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: index, length: 1), with: NSAttributedString(
            string: nowChecked ? NoteStyle.checked : NoteStyle.unchecked,
            attributes: NoteStyle.checkboxAttributes(checked: nowChecked)
        ))
        if content.length > 0 {
            if nowChecked {
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: content)
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: content)
            } else {
                storage.removeAttribute(.strikethroughStyle, range: content)
                storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: content)
            }
        }
        storage.endEditing()
        tv.didChangeText()
    }

    // MARK: Inline styles

    func toggleTrait(_ trait: NSFontTraitMask) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        defer { focus() }
        let fm = NSFontManager.shared
        let sel = tv.selectedRange()
        if sel.length == 0 {
            var attrs = tv.typingAttributes
            let font = attrs[.font] as? NSFont ?? NoteStyle.bodyFont
            attrs[.font] = fm.traits(of: font).contains(trait)
                ? fm.convert(font, toNotHaveTrait: trait)
                : fm.convert(font, toHaveTrait: trait)
            tv.typingAttributes = attrs
            return
        }
        var allHave = true
        storage.enumerateAttribute(.font, in: sel) { value, _, _ in
            if let font = value as? NSFont, !fm.traits(of: font).contains(trait) { allHave = false }
        }
        guard tv.shouldChangeText(in: sel, replacementString: nil) else { return }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: sel) { value, r, _ in
            let font = value as? NSFont ?? NoteStyle.bodyFont
            let converted = allHave ? fm.convert(font, toNotHaveTrait: trait) : fm.convert(font, toHaveTrait: trait)
            storage.addAttribute(.font, value: converted, range: r)
        }
        storage.endEditing()
        tv.didChangeText()
    }

    func toggleUnderline() { toggleLine(.underlineStyle) }
    func toggleStrikethrough() { toggleLine(.strikethroughStyle) }

    private func toggleLine(_ key: NSAttributedString.Key) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        defer { focus() }
        let sel = tv.selectedRange()
        if sel.length == 0 {
            var attrs = tv.typingAttributes
            attrs[key] = (attrs[key] as? Int ?? 0) != 0 ? nil : NSUnderlineStyle.single.rawValue
            tv.typingAttributes = attrs
            return
        }
        var allHave = true
        storage.enumerateAttribute(key, in: sel) { value, _, _ in
            if (value as? Int ?? 0) == 0 { allHave = false }
        }
        guard tv.shouldChangeText(in: sel, replacementString: nil) else { return }
        if allHave {
            storage.removeAttribute(key, range: sel)
        } else {
            storage.addAttribute(key, value: NSUnderlineStyle.single.rawValue, range: sel)
        }
        tv.didChangeText()
    }

    // MARK: Images

    func chooseImage() {
        let panel = NSOpenPanel()
        panel.title = "Insert Image"
        panel.prompt = "Insert"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.level = .popUpMenu
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let image = NSImage(contentsOf: url) { insertImage(image) }
        }
    }

    func insertImage(_ image: NSImage) {
        guard let tv = textView, let encoded = ImageUtils.encode(image, maxSide: 1600) else { return }
        let wrapper = FileWrapper(regularFileWithContents: encoded.data)
        wrapper.preferredFilename = "image.\(encoded.ext)"
        let attachment = NSTextAttachment(fileWrapper: wrapper)
        fit(attachment, maxWidth: maxImageWidth)

        let sel = tv.selectedRange()
        let ns = tv.string as NSString
        let out = NSMutableAttributedString()
        if sel.location > 0 && ns.character(at: sel.location - 1) != 10 {
            out.append(NSAttributedString(string: "\n", attributes: NoteStyle.attributes()))
        }
        out.append(NSAttributedString(attachment: attachment))
        out.append(NSAttributedString(string: "\n", attributes: NoteStyle.attributes()))
        out.addAttribute(.paragraphStyle, value: NoteStyle.paragraphStyle(), range: NSRange(location: 0, length: out.length))
        tv.insertText(out, replacementRange: sel)
        focus()
    }

    private var maxImageWidth: CGFloat {
        guard let tv = textView, let container = tv.textContainer else { return 480 }
        let width = tv.bounds.width - tv.textContainerInset.width * 2 - container.lineFragmentPadding * 2
        return max(160, width - 4)
    }

    /// Sizes every image to fit the note's width. Images are drawn by a cell with a pre-sized image.
    func fitAttachments() {
        guard let tv = textView, let storage = tv.textStorage, storage.length > 0 else { return }
        let maxWidth = maxImageWidth
        var changed = false
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            guard let attachment = value as? NSTextAttachment else { return }
            if fit(attachment, maxWidth: maxWidth) { changed = true }
        }
        if changed {
            tv.layoutManager?.invalidateLayout(forCharacterRange: NSRange(location: 0, length: storage.length),
                                               actualCharacterRange: nil)
        }
    }

    @discardableResult
    private func fit(_ attachment: NSTextAttachment, maxWidth: CGFloat) -> Bool {
        guard let data = attachment.fileWrapper?.regularFileContents,
              let image = NSImage(data: data) else { return false }
        // Use pixel size so Retina screenshots aren't shown at double size.
        let rep = image.representations.first
        let pixel = NSSize(width: rep?.pixelsWide ?? Int(image.size.width), height: rep?.pixelsHigh ?? Int(image.size.height))
        let natural = NSSize(width: max(1, pixel.width / 2), height: max(1, pixel.height / 2))
        let width = min(natural.width, maxWidth)
        let target = NSSize(width: width.rounded(), height: (natural.height * width / natural.width).rounded())
        if let cell = attachment.attachmentCell as? NSTextAttachmentCell, cell.image?.size == target { return false }
        image.size = target
        attachment.attachmentCell = NSTextAttachmentCell(imageCell: image)
        return true
    }
}

// MARK: - Text view

final class NoteTextView: NSTextView {
    weak var controller: NoteController?
    var placeholder = "Write notes…  Type # for a title, ## for a heading, - for a bullet, [] for a checklist. Paste or drop images."

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if flags == .command {
            switch key {
            case "b": controller?.toggleTrait(.boldFontMask); return true
            case "i": controller?.toggleTrait(.italicFontMask); return true
            case "u": controller?.toggleUnderline(); return true
            default: break
            }
        }
        if super.performKeyEquivalent(with: event) { return true }
        // The app has no visible menu bar, so route standard editing shortcuts directly.
        if flags == .command {
            switch key {
            case "x": cut(nil); return true
            case "c": copy(nil); return true
            case "v": paste(nil); return true
            case "a": selectAll(nil); return true
            case "z": undoManager?.undo(); return true
            default: break
            }
        }
        if flags == [.command, .shift] && key == "z" {
            undoManager?.redo()
            return true
        }
        return false
    }

    /// Clicking a ☐ / ☑ at the start of a line toggles it instead of moving the caret.
    override func mouseDown(with event: NSEvent) {
        if let index = checkboxIndex(at: convert(event.locationInWindow, from: nil)) {
            controller?.toggleCheckbox(at: index)
            return
        }
        super.mouseDown(with: event)
    }

    private func checkboxIndex(at point: NSPoint) -> Int? {
        guard let lm = layoutManager, let tc = textContainer, let storage = textStorage, storage.length > 0 else { return nil }
        let p = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = lm.glyphIndex(for: p, in: tc)
        let rect = lm.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: tc)
        guard rect.insetBy(dx: -3, dy: -2).contains(p) else { return nil }
        let index = lm.characterIndexForGlyph(at: glyph)
        let ns = storage.string as NSString
        guard index < ns.length else { return nil }
        let char = ns.substring(with: NSRange(location: index, length: 1))
        guard char == NoteStyle.unchecked || char == NoteStyle.checked else { return nil }
        let para = ns.paragraphRange(for: NSRange(location: index, length: 0))
        return para.location == index ? index : nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty else { return }
        let origin = NSPoint(
            x: textContainerOrigin.x + (textContainer?.lineFragmentPadding ?? 5),
            y: textContainerOrigin.y
        )
        let rect = NSRect(origin: origin, size: NSSize(width: bounds.width - origin.x * 2, height: 60))
        (placeholder as NSString).draw(in: rect, withAttributes: [
            .font: NoteStyle.bodyFont,
            .foregroundColor: NSColor.placeholderTextColor,
        ])
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        super.setFrameSize(newSize)
        if widthChanged { controller?.fitAttachments() }
    }
}

// MARK: - SwiftUI wrapper

struct NoteEditor: NSViewRepresentable {
    let taskID: UUID
    let fallbackText: String
    let controller: NoteController
    let store: Store

    func makeCoordinator() -> Coordinator {
        Coordinator(taskID: taskID, controller: controller, store: store)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        // TextKit 1 for mature list + attachment behavior.
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)

        let tv = NoteTextView(frame: .zero, textContainer: container)
        tv.minSize = .zero
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.isRichText = true
        tv.importsGraphics = true
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.isAutomaticLinkDetectionEnabled = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.textContainerInset = NSSize(width: 0, height: 10)
        tv.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand,
        ]

        if let note = store.loadNote(taskID) {
            let text = NSMutableAttributedString(attributedString: note)
            NoteStyle.restoreListMarkers(in: text)
            storage.setAttributedString(text)
        } else if !fallbackText.isEmpty {
            storage.setAttributedString(NSAttributedString(string: fallbackText, attributes: NoteStyle.attributes()))
        }
        tv.typingAttributes = NoteStyle.attributes()

        tv.delegate = context.coordinator
        tv.controller = controller
        controller.textView = tv
        context.coordinator.textView = tv
        scroll.documentView = tv

        DispatchQueue.main.async {
            self.controller.fitAttachments()
            self.controller.refresh()
        }
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.flush()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let taskID: UUID
        let controller: NoteController
        let store: Store
        weak var textView: NSTextView?
        private var pendingSave: DispatchWorkItem?

        init(taskID: UUID, controller: NoteController, store: Store) {
            self.taskID = taskID
            self.controller = controller
            self.store = store
        }

        func flush() {
            guard let pendingSave else { return }
            pendingSave.cancel()
            self.pendingSave = nil
            save()
        }

        private func save() {
            guard let tv = textView else { return }
            store.saveNote(taskID, NSAttributedString(attributedString: tv.attributedString()))
        }

        func textDidChange(_ notification: Notification) {
            textView?.needsDisplay = true
            controller.fitAttachments()
            pendingSave?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.pendingSave = nil
                self?.save()
            }
            pendingSave = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            controller.refresh()
        }

        /// Markdown-style shortcuts: "# ", "## ", "- ", "* ", "1. ".
        func textView(_ tv: NSTextView, shouldChangeTextIn range: NSRange, replacementString string: String?) -> Bool {
            guard string == " ", range.length == 0 else { return true }
            let ns = tv.string as NSString
            let para = ns.paragraphRange(for: NSRange(location: range.location, length: 0))
            let prefix = ns.substring(with: NSRange(location: para.location, length: range.location - para.location))
            let apply: (NoteController) -> Void
            switch prefix {
            case "#": apply = { $0.setBlock(.title) }
            case "##": apply = { $0.setBlock(.heading) }
            case "-", "*": apply = { $0.toggleList(.bullet) }
            case "1.": apply = { $0.toggleList(.number) }
            case "[]", "[ ]": apply = { $0.toggleChecklist() }
            case "[x]", "[X]": apply = { c in
                c.toggleChecklist()
                c.toggleCheckbox(at: para.location)
            }
            default: return true
            }
            DispatchQueue.main.async { [controller] in
                let r = NSRange(location: para.location, length: (prefix as NSString).length)
                if tv.shouldChangeText(in: r, replacementString: "") {
                    tv.textStorage?.replaceCharacters(in: r, with: "")
                    tv.didChangeText()
                }
                tv.setSelectedRange(NSRange(location: para.location, length: 0))
                apply(controller)
            }
            return false
        }

        func textView(_ tv: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard let storage = tv.textStorage else { return false }
            let sel = tv.selectedRange()
            guard sel.length == 0 else { return false }
            let ns = tv.string as NSString
            let para = ns.paragraphRange(for: sel)
            let style: NSParagraphStyle? = para.location < storage.length
                ? storage.attribute(.paragraphStyle, at: para.location, effectiveRange: nil) as? NSParagraphStyle
                : tv.typingAttributes[.paragraphStyle] as? NSParagraphStyle
            let line = ns.substring(with: para).trimmingCharacters(in: .newlines) as NSString
            let markerLength = NoteStyle.markerLength(in: line)
            let checklistLength = NoteStyle.checklistPrefixLength(in: line)

            if checklistLength > 0 {
                if selector == #selector(NSResponder.insertNewline(_:)) {
                    let content = line.substring(from: checklistLength).trimmingCharacters(in: .whitespaces)
                    if content.isEmpty {
                        // Return on an empty item ends the checklist.
                        endListItem(tv, para: para, markerLength: line.length)
                        return true
                    }
                    let text = NSMutableAttributedString(string: "\n", attributes: NoteStyle.checklistBodyAttributes)
                    text.append(NoteStyle.checkboxPrefix())
                    tv.insertText(text, replacementRange: sel)
                    tv.typingAttributes = NoteStyle.checklistBodyAttributes
                    return true
                }
                if selector == #selector(NSResponder.deleteBackward(_:)), sel.location == para.location + checklistLength {
                    endListItem(tv, para: para, markerLength: checklistLength)
                    return true
                }
            }

            if selector == #selector(NSResponder.insertNewline(_:)) {
                if let list = style?.textLists.first, markerLength > 0 {
                    let content = line.substring(from: markerLength).trimmingCharacters(in: .whitespaces)
                    if content.isEmpty {
                        // Return on an empty item ends the list.
                        endListItem(tv, para: para, markerLength: line.length)
                        return true
                    }
                    let next = storage.itemNumber(in: list, at: para.location) + 1
                    let text = NSAttributedString(string: "\n" + NoteStyle.marker(list, number: next),
                                                  attributes: NoteStyle.attributes(list: list))
                    tv.insertText(text, replacementRange: sel)
                    return true
                }
                let font = (para.location < storage.length && para.length > 0)
                    ? storage.attribute(.font, at: para.location, effectiveRange: nil) as? NSFont
                    : tv.typingAttributes[.font] as? NSFont
                let block = NoteStyle.block(of: font)
                if block != .body {
                    // After a title or heading, continue in body text.
                    tv.insertText(NSAttributedString(string: "\n", attributes: NoteStyle.attributes(block: block)),
                                  replacementRange: sel)
                    tv.typingAttributes = NoteStyle.attributes()
                    controller.refresh()
                    return true
                }
            }

            if selector == #selector(NSResponder.deleteBackward(_:)),
               markerLength > 0, sel.location == para.location + markerLength {
                // Backspace right after a bullet removes the bullet.
                endListItem(tv, para: para, markerLength: markerLength)
                return true
            }
            return false
        }

        private func endListItem(_ tv: NSTextView, para: NSRange, markerLength: Int) {
            let r = NSRange(location: para.location, length: markerLength)
            guard tv.shouldChangeText(in: r, replacementString: "") else { return }
            tv.textStorage?.replaceCharacters(in: r, with: "")
            let remaining = (tv.string as NSString).paragraphRange(for: NSRange(location: para.location, length: 0))
            if remaining.length > 0 {
                tv.textStorage?.addAttribute(.paragraphStyle, value: NoteStyle.paragraphStyle(), range: remaining)
                tv.textStorage?.removeAttribute(.strikethroughStyle, range: remaining)
                tv.textStorage?.addAttribute(.foregroundColor, value: NSColor.labelColor, range: remaining)
            }
            tv.didChangeText()
            tv.setSelectedRange(NSRange(location: para.location, length: 0))
            tv.typingAttributes = NoteStyle.attributes()
            controller.refresh()
        }
    }
}

// MARK: - Formatting toolbar

struct FormatToolbar: View {
    let controller: NoteController

    var body: some View {
        HStack(spacing: 2) {
            textButton("Title", isOn: controller.block == .title, help: "Title (# space)") { controller.setBlock(.title) }
            textButton("Heading", isOn: controller.block == .heading, help: "Heading (## space)") { controller.setBlock(.heading) }
            textButton("Body", isOn: controller.block == .body && controller.list == nil && !controller.isChecklist, help: "Body text") { controller.setBlock(.body) }
            separator
            iconButton("bold", isOn: controller.isBold, help: "Bold (⌘B)") { controller.toggleTrait(.boldFontMask) }
            iconButton("italic", isOn: controller.isItalic, help: "Italic (⌘I)") { controller.toggleTrait(.italicFontMask) }
            iconButton("underline", isOn: controller.isUnderline, help: "Underline (⌘U)") { controller.toggleUnderline() }
            iconButton("strikethrough", isOn: controller.isStrikethrough, help: "Strikethrough") { controller.toggleStrikethrough() }
            separator
            iconButton("list.bullet", isOn: controller.list == .bullet, help: "Bulleted list (- space)") { controller.toggleList(.bullet) }
            iconButton("list.number", isOn: controller.list == .number, help: "Numbered list (1. space)") { controller.toggleList(.number) }
            iconButton("checklist", isOn: controller.isChecklist, help: "Checklist ([] space) — click a box to tick it") { controller.toggleChecklist() }
            separator
            iconButton("photo", isOn: false, help: "Insert image (or paste / drop one)") {
                DispatchQueue.main.async { controller.chooseImage() }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.1))
            .frame(width: 1, height: 16)
            .padding(.horizontal, 4)
    }

    private func textButton(_ title: String, isOn: Bool, help: String, action: @escaping () -> Void) -> some View {
        ToolbarButton(isOn: isOn, help: help, action: action) {
            Text(title).font(.system(size: 12, weight: isOn ? .semibold : .medium))
                .padding(.horizontal, 7)
        }
    }

    private func iconButton(_ symbol: String, isOn: Bool, help: String, action: @escaping () -> Void) -> some View {
        ToolbarButton(isOn: isOn, help: help, action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium)).frame(width: 26)
        }
    }
}

private struct ToolbarButton<Label: View>: View {
    let isOn: Bool
    let help: String
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @Local private var isHovering = false

    var body: some View {
        Button(action: action) {
            label()
                .foregroundStyle(isOn ? .primary : .secondary)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isOn ? Color.primary.opacity(0.1) : isHovering ? Color.primary.opacity(0.05) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help)
    }
}
