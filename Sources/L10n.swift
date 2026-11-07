import Foundation

// Localisation. Source strings are the English UI text itself: `tr("Copy")`
// looks "Copy" up in Resources/<code>.lproj/Localizable.strings and falls back
// to the key, so a missing language or a missing entry simply reads English.
//
// Placeholders are `%@` (taken in order) or `%1$@`, `%2$@` (explicit, for
// languages that reorder). Counts go through `trp`, which stores every plural
// form of a language in one value, separated by `|` in CLDR order.

struct Language: Identifiable, Hashable {
    let code: String
    let name: String       // always written in the language itself
    var id: String { code }
}

enum L10n {
    static let system = "system"

    /// The languages the app ships with. English is the built-in fallback.
    static let languages: [Language] = [
        Language(code: "en", name: "English"),
        Language(code: "it", name: "Italiano"),
        Language(code: "de", name: "Deutsch"),
        Language(code: "fr", name: "Français"),
        Language(code: "es", name: "Español"),
        Language(code: "pt", name: "Português"),
        Language(code: "nl", name: "Nederlands"),
        Language(code: "pl", name: "Polski"),
        Language(code: "cs", name: "Čeština"),
        Language(code: "sv", name: "Svenska"),
        Language(code: "da", name: "Dansk"),
        Language(code: "el", name: "Ελληνικά"),
        Language(code: "ru", name: "Русский"),
        Language(code: "uk", name: "Українська"),
        Language(code: "tr", name: "Türkçe"),
        Language(code: "zh-Hans", name: "简体中文"),
        Language(code: "ja", name: "日本語"),
    ]

    /// Code in effect right now (never "system").
    private(set) static var code = "en"
    private static var table: [String: String] = [:]

    /// `choice` is a language code or `system`. A system language the app does
    /// not ship with resolves to English.
    static func select(_ choice: String) {
        let resolved = choice == system ? detect(Locale.preferredLanguages) : choice
        code = languages.contains { $0.code == resolved } ? resolved : "en"
        table = load(code)
    }

    /// First preferred language the app has a translation for, else English.
    static func detect(_ preferred: [String]) -> String {
        for tag in preferred {
            let parts = tag.replacingOccurrences(of: "_", with: "-").split(separator: "-").map(String.init)
            guard let base = parts.first?.lowercased() else { continue }
            if base == "zh" { return "zh-Hans" }   // Traditional readers get Simplified, not English
            if base == "nb" || base == "nn" || base == "no" { continue }
            if languages.contains(where: { $0.code == base }) { return base }
        }
        return "en"
    }

    private static func load(_ code: String) -> [String: String] {
        guard code != "en",
              let path = Bundle.main.path(forResource: "Localizable", ofType: "strings",
                                          inDirectory: nil, forLocalization: code),
              let dict = NSDictionary(contentsOfFile: path) as? [String: String]
        else { return [:] }
        return dict
    }

    static func lookup(_ key: String) -> String { table[key] ?? key }
    static func translation(_ key: String) -> String? { table[key] }

    // MARK: Plurals (CLDR categories, in the order the values list them)

    /// Index of the plural form for `n`, in the order one | few | many | other
    /// as far as the language uses them.
    static func pluralIndex(_ n: Int) -> Int {
        let m10 = n % 10, m100 = n % 100
        switch code {
        case "zh-Hans", "ja": return 0
        case "fr", "pt": return n <= 1 ? 0 : 1
        case "ru", "uk":
            if m10 == 1 && m100 != 11 { return 0 }
            if (2...4).contains(m10) && !(12...14).contains(m100) { return 1 }
            return 2
        case "pl":
            if n == 1 { return 0 }
            if (2...4).contains(m10) && !(12...14).contains(m100) { return 1 }
            return 2
        case "cs": return n == 1 ? 0 : ((2...4).contains(n) ? 1 : 2)
        default: return n == 1 ? 0 : 1
        }
    }

    static func fill(_ text: String, _ args: [Any]) -> String {
        guard !args.isEmpty, text.contains("%") else { return text }
        var out = "", next = 0
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            if chars[i] == "%" {
                if i + 1 < chars.count, chars[i + 1] == "@" {
                    if next < args.count { out += "\(args[next])"; next += 1 }
                    i += 2; continue
                }
                var j = i + 1, digits = ""
                while j < chars.count, chars[j].isNumber { digits.append(chars[j]); j += 1 }
                if !digits.isEmpty, j + 1 < chars.count, chars[j] == "$", chars[j + 1] == "@",
                   let n = Int(digits), (1...args.count).contains(n) {
                    out += "\(args[n - 1])"
                    i = j + 2; continue
                }
            }
            out.append(chars[i]); i += 1
        }
        return out
    }
}

/// Translated text for `key`, with `%@` / `%1$@` placeholders filled from `args`.
func tr(_ key: String, _ args: Any...) -> String {
    L10n.fill(L10n.lookup(key), args)
}

/// Count-dependent text. `other` is the lookup key; `one` is the English
/// singular used when no translation exists. `%@` defaults to `n`.
func trp(_ n: Int, _ one: String, _ other: String, _ args: Any...) -> String {
    let filled = args.isEmpty ? [n] : args
    guard let value = L10n.translation(other) else { return L10n.fill(n == 1 ? one : other, filled) }
    let forms = value.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
    return L10n.fill(forms[min(L10n.pluralIndex(n), forms.count - 1)], filled)
}
