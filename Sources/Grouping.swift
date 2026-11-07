import Foundation

/// Windows' "Group by" buckets. The labels, membership and order follow
/// File Explorer's own: Name A-Z with # for anything that does not start
/// with a letter, Type by the same name the Type column shows, Date
/// modified in relative-day buckets, Size in Explorer's named ranges.
enum Grouping {
    static var dateLabels: [String] { ["Today", "Yesterday", "Earlier this week", "Last week",
                             "Earlier this month", "Last month", "Earlier this year",
                             "A long time ago"].map { tr($0) } }
    static var sizeLabels: [String] { ["Tiny", "Small", "Medium", "Large", "Huge", "Gigantic",
                             "Empty", "Unspecified"].map { tr($0) } }

    static func key(_ item: FileItem, by mode: String) -> String {
        switch mode {
        case "Name":
            guard let f = item.name.uppercased().first else { return "#" }
            return ("A"..."Z").contains(f) ? String(f) : "#"
        case "Type":
            return item.typeName
        case "Date modified":
            return dateLabel(item.modified)
        case "Size":
            guard !item.isDirectory || item.isPackage else { return tr("Unspecified") }
            return Grouping.sizeLabel(item.size)
        default:
            return ""
        }
    }

    /// Explorer's named ranges, byte thresholds at the binary sizes.
    static func sizeLabel(_ bytes: Int64) -> String {
        if bytes == 0 { return tr("Empty") }
        if bytes < 10_240 { return tr("Tiny") }
        if bytes < 102_400 { return tr("Small") }
        if bytes < 1_048_576 { return tr("Medium") }
        if bytes < 16_777_216 { return tr("Large") }
        if bytes < 1_073_741_824 { return tr("Huge") }
        return tr("Gigantic")
    }

    /// Bucket order on screen. Canonical labels keep their defined order;
    /// anything unexpected (accents, unknown kinds) sorts after, alphabetically.
    static func ordered(_ titles: Set<String>, by mode: String) -> [String] {
        let canon: [String]
        switch mode {
        case "Name": canon = (65...90).map { String(UnicodeScalar($0)!) } + ["#"]
        case "Date modified": canon = dateLabels
        case "Size": canon = sizeLabels
        default: return titles.sorted()
        }
        let known = canon.filter { titles.contains($0) }
        let rest = titles.subtracting(known).sorted()
        return known + rest
    }

    static func dateLabel(_ date: Date, now: Date = Date(),
                          calendar: Calendar = .current) -> String {
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: day, to: today).day ?? 0
        if days <= 0 { return tr("Today") }
        if days == 1 { return tr("Yesterday") }
        // Calendar week, starting on the locale's first weekday, like Explorer.
        let weekday = calendar.component(.weekday, from: today)
        let sinceWeekStart = (weekday - calendar.firstWeekday + 7) % 7
        if days <= sinceWeekStart { return tr("Earlier this week") }
        if days <= sinceWeekStart + 7 { return tr("Last week") }
        let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today))!
        if day >= thisMonth { return tr("Earlier this month") }
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: thisMonth)!
        if day >= lastMonth { return tr("Last month") }
        let thisYear = calendar.date(from: calendar.dateComponents([.year], from: today))!
        if day >= thisYear { return tr("Earlier this year") }
        return tr("A long time ago")
    }
}
