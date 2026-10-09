import Foundation

/// Result of parsing quick-add text like "Fix login fri !high #sidekick".
struct ParsedTask: Equatable {
    var title: String
    var deadline: Date?
    var priority: Priority?
    var productID: UUID?
    /// Names after "@"; created as tags on submit if they don't exist yet.
    var tagNames: [String] = []
}

/// Pulls a due date, priority and product out of free text; whatever is left is the title.
///
/// - Dates: today, tomorrow (tmr, tmrw), mon…sun, next fri, next week, in 3 days, in 2 weeks, oct 12, 12 oct.
///   A leading "on", "by" or "due" is dropped too.
/// - Priority: !, !!, !!! or !low, !med, !high (also !l, !m, !h, p1–p3).
/// - Product: #name, matched by prefix ignoring spaces ("#command" → Command Center).
/// - Tags: @name (any number of them).
enum QuickAddParser {
    static func parse(_ input: String, products: [Product], now: Date = Date()) -> ParsedTask {
        var words = input.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var result = ParsedTask(title: "")
        var kept: [String] = []
        var i = 0

        while i < words.count {
            let lower = words[i].lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ",."))

            if result.productID == nil, lower.hasPrefix("#"), lower.count > 1,
               let product = matchProduct(String(lower.dropFirst()), in: products) {
                result.productID = product.id
                i += 1
                continue
            }

            if lower.hasPrefix("@"), lower.count > 1 {
                let name = String(words[i].dropFirst()).trimmingCharacters(in: CharacterSet(charactersIn: ",."))
                if !name.isEmpty, !result.tagNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                    result.tagNames.append(name)
                }
                i += 1
                continue
            }

            if result.priority == nil, let priority = priorities[lower] {
                result.priority = priority
                i += 1
                continue
            }

            if result.deadline == nil, let (date, length) = matchDate(at: i, in: words, now: now) {
                result.deadline = date
                if let last = kept.last?.lowercased(), ["on", "by", "due"].contains(last) { kept.removeLast() }
                i += length
                continue
            }

            kept.append(words[i])
            i += 1
        }

        words = kept
        result.title = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return result
    }

    // MARK: Products

    private static func matchProduct(_ query: String, in products: [Product]) -> Product? {
        let normalized = { (s: String) in s.lowercased().filter { !$0.isWhitespace } }
        let q = normalized(query)
        return products.first { normalized($0.name) == q }
            ?? products.filter { normalized($0.name).hasPrefix(q) }.min { $0.name.count < $1.name.count }
    }

    // MARK: Priority

    private static let priorities: [String: Priority] = [
        "!": .low, "!l": .low, "!low": .low, "p3": .low,
        "!!": .medium, "!m": .medium, "!med": .medium, "!medium": .medium, "p2": .medium,
        "!!!": .high, "!h": .high, "!high": .high, "p1": .high,
    ]

    // MARK: Dates

    private static let weekdays: [String: Int] = [
        "sun": 1, "sunday": 1, "mon": 2, "monday": 2, "tue": 3, "tues": 3, "tuesday": 3,
        "wed": 4, "wednesday": 4, "thu": 5, "thur": 5, "thurs": 5, "thursday": 5,
        "fri": 6, "friday": 6, "sat": 7, "saturday": 7,
    ]

    private static let months: [String: Int] = [
        "jan": 1, "january": 1, "feb": 2, "february": 2, "mar": 3, "march": 3, "apr": 4, "april": 4,
        "may": 5, "jun": 6, "june": 6, "jul": 7, "july": 7, "aug": 8, "august": 8,
        "sep": 9, "sept": 9, "september": 9, "oct": 10, "october": 10, "nov": 11, "november": 11,
        "dec": 12, "december": 12,
    ]

    /// Returns the date and how many words it used, if a date phrase starts at `index`.
    private static func matchDate(at index: Int, in words: [String], now: Date) -> (Date, Int)? {
        let cal = Calendar.current
        let today = now.startOfDay
        func word(_ offset: Int) -> String? {
            let j = index + offset
            guard j < words.count else { return nil }
            return words[j].lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ",."))
        }
        func days(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: today) ?? today }
        func nextWeekday(_ weekday: Int) -> Date {
            let current = cal.component(.weekday, from: today)
            var delta = (weekday - current + 7) % 7
            if delta == 0 { delta = 7 }
            return days(delta)
        }

        guard let w0 = word(0) else { return nil }

        switch w0 {
        case "today", "tod", "tonight": return (today, 1)
        case "tomorrow", "tmr", "tmrw", "tom": return (days(1), 1)
        default: break
        }

        if let wd = weekdays[w0] { return (nextWeekday(wd), 1) }

        if w0 == "next", let w1 = word(1) {
            if w1 == "week" { return (days(7), 2) }
            if w1 == "month" { return (cal.date(byAdding: .month, value: 1, to: today) ?? today, 2) }
            if let wd = weekdays[w1] {
                // "next fri" means that day in next week, so skip one still in this week.
                let date = nextWeekday(wd)
                let thisWeek = cal.dateInterval(of: .weekOfYear, for: today)
                let inThisWeek = thisWeek?.contains(date) ?? false
                return (inThisWeek ? (cal.date(byAdding: .day, value: 7, to: date) ?? date) : date, 2)
            }
        }

        if w0 == "in", let w1 = word(1), let n = Int(w1), let w2 = word(2) {
            if w2.hasPrefix("day") { return (days(n), 3) }
            if w2.hasPrefix("week") { return (days(n * 7), 3) }
        }

        // "oct 12" or "12 oct"
        if let w1 = word(1) {
            if let m = months[w0], let d = Int(w1), let date = monthDay(m, d, after: today) { return (date, 2) }
            if let d = Int(w0), let m = months[w1], let date = monthDay(m, d, after: today) { return (date, 2) }
        }
        return nil
    }

    /// The next occurrence of month/day on or after today.
    private static func monthDay(_ month: Int, _ day: Int, after today: Date) -> Date? {
        let cal = Calendar.current
        guard (1...31).contains(day) else { return nil }
        var comps = cal.dateComponents([.year], from: today)
        comps.month = month
        comps.day = day
        guard let date = cal.date(from: comps) else { return nil }
        return date < today ? cal.date(byAdding: .year, value: 1, to: date) : date
    }
}
