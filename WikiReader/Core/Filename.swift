import Foundation

enum Filename {
    static func make(title: String, date: Date = Date()) -> String {
        let stamp = timestamp(date)
        let slug = slugify(title)
        return slug.isEmpty ? "\(stamp).md" : "\(stamp)-\(slug).md"
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: date)
    }

    static func slugify(_ string: String, maxLength: Int = 50) -> String {
        let mapped = string.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        var slug = String(mapped)
        while slug.contains("--") {
            slug = slug.replacingOccurrences(of: "--", with: "-")
        }
        slug = trimHyphens(slug)
        if slug.count > maxLength {
            slug = trimHyphens(String(slug.prefix(maxLength)))
        }
        return slug
    }

    private static func trimHyphens(_ string: String) -> String {
        string.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
