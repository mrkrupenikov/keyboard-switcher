import Foundation

/// Bidirectional mapping between English QWERTY and Ukrainian keyboard layouts
/// based on physical key positions.
struct KeyboardLayoutMap {

    // MARK: - English → Ukrainian (by key position)

    static let englishToUkrainian: [Character: Character] = [
        // Top row
        "q": "й", "w": "ц", "e": "у", "r": "к", "t": "е",
        "y": "н", "u": "г", "i": "ш", "o": "щ", "p": "з",
        "[": "х", "]": "ї", "\\": "ґ",
        // Home row
        "a": "ф", "s": "і", "d": "в", "f": "а", "g": "п",
        "h": "р", "j": "о", "k": "л", "l": "д", ";": "ж",
        "'": "є",
        // Bottom row
        "z": "я", "x": "ч", "c": "с", "v": "м", "b": "и",
        "n": "т", "m": "ь", ",": "б", ".": "ю", "/": ".",
        // Top row uppercase
        "Q": "Й", "W": "Ц", "E": "У", "R": "К", "T": "Е",
        "Y": "Н", "U": "Г", "I": "Ш", "O": "Щ", "P": "З",
        "{": "Х", "}": "Ї", "|": "Ґ",
        // Home row uppercase
        "A": "Ф", "S": "І", "D": "В", "F": "А", "G": "П",
        "H": "Р", "J": "О", "K": "Л", "L": "Д", ":": "Ж",
        "\"": "Є",
        // Bottom row uppercase
        "Z": "Я", "X": "Ч", "C": "С", "V": "М", "B": "И",
        "N": "Т", "M": "Ь", "<": "Б", ">": "Ю", "?": ",",
        // Numbers and symbols (same positions, but some differ)
        "`": "'", "~": "₴",
    ]

    // MARK: - Ukrainian → English (reverse mapping)

    static let ukrainianToEnglish: [Character: Character] = {
        var map: [Character: Character] = [:]
        for (en, uk) in englishToUkrainian {
            map[uk] = en
        }
        return map
    }()

    /// Convert a word typed in English layout to what it would be in Ukrainian layout
    static func convertToUkrainian(_ word: String) -> String {
        return String(word.map { englishToUkrainian[$0] ?? $0 })
    }

    /// Convert a word typed in Ukrainian layout to what it would be in English layout
    static func convertToEnglish(_ word: String) -> String {
        return String(word.map { ukrainianToEnglish[$0] ?? $0 })
    }

    /// Check if a string contains only Latin characters (plus common punctuation)
    static func isLatin(_ text: String) -> Bool {
        return text.allSatisfy { $0.isASCII || $0 == "\u{2019}" || $0 == "'" || $0 == "-" }
    }

    /// Check if a string contains Cyrillic characters
    static func isCyrillic(_ text: String) -> Bool {
        return text.contains { char in
            guard let scalar = char.unicodeScalars.first else { return false }
            return (0x0400...0x04FF).contains(scalar.value)
        }
    }
}
