import Foundation

/// Detects whether a word belongs to English or Ukrainian language
final class LanguageDetector {

    enum Language {
        case english
        case ukrainian
        case unknown
    }

    struct DetectionResult {
        let language: Language
        let confidence: Double // 0.0 to 1.0
    }

    private var englishWords: Set<String> = []
    private var ukrainianWords: Set<String> = []

    // Common Ukrainian bigrams (high frequency) — expanded for inline detection
    private let ukrainianBigrams: Set<String> = [
        // н-
        "на", "но", "ні", "не", "нь", "нт", "нк", "нд", "ну", "ня", "нц", "нч",
        // п-
        "пр", "по", "па", "пе", "пі", "пу", "пл", "пн",
        // р-
        "ро", "ра", "ре", "ри", "рі", "ру", "рн", "рю", "ря",
        // с-
        "ст", "сь", "ся", "сп", "сл", "ск", "сн", "сі", "со", "са", "се", "св", "су", "сц",
        // к-
        "ко", "ка", "ки", "ку", "кі", "кл", "кр", "кт",
        // т-
        "ти", "то", "та", "те", "ту", "тр", "тв", "ті",
        // л-
        "ла", "ло", "ли", "ле", "лі", "лю", "ль", "лк",
        // в-
        "ва", "во", "ви", "ве", "ві", "вс", "вн", "вл", "вк", "вч", "вт", "вр", "ву",
        // з-
        "за", "зо", "зі", "зу", "зе", "зм", "зн", "зв", "зр", "зд", "зб", "зк",
        // д-
        "ді", "да", "до", "де", "ду", "дн", "др", "дж", "дк", "дл",
        // м-
        "мо", "ма", "ми", "ме", "мі", "мн", "му",
        // б-
        "бу", "бі", "ба", "бо", "бе", "бр", "бл",
        // г-
        "го", "гр", "га", "ги", "гу", "гі", "гл",
        // Vowel combinations & endings (critical for verb forms)
        "ум", "ам", "ом", "ем", "ім",           // -умати, -амо, -ому, -емо, -імо
        "аю", "ую", "ою", "ію", "ею",           // 1st person: думаю, купую
        "ає", "ує", "іє", "оє",                 // 3rd person: думає, купує
        "єш", "єт", "єм",                       // думаєш, думає(т), думаємо
        "юч", "ющ",                              // present participle
        "ай", "ій", "ой", "уй", "ей",           // imperative/adjective endings
        "яю", "яє", "яч",                       // verbs: міняю, міняє
        "жу", "жи", "же",                       // ходжу, біжи, може
        "шу", "ша", "ше", "ши",                 // пишу, наша, більше, пиши
        "щу", "ща", "ще", "щи", "що",           // шукаю, площа, ще
        // Standard bigrams
        "ів", "ов", "ор", "ол", "ос", "об", "от", "оп", "ож", "ом",
        "ан", "ен", "ін", "он", "ун",
        "ар", "ер", "ир", "ір", "ур",
        "ав", "ев", "ов", "ув", "ів",
        "аб", "аг", "ад", "аз", "ал", "ап", "ас", "ат", "аф", "ах", "ач", "аш",
        "уд", "уж", "ук", "ул", "ум", "ун", "ур", "ус", "ут", "уч",
        "ьк", "нн", "ть", "тт", "сс",
        "їх", "їм", "ої", "єї", "ій",
        "як", "яв", "ям", "ян", "яч", "яз", "ял",
        "хо", "хі", "ху", "ха",
        "чо", "чі", "чу", "ча", "че", "чн", "чк",
        "ші", "шк", "шн", "шл",
        "юр", "юч", "юб",
        "ці", "ца", "цю",
        "ок", "ак", "ук", "ик", "ід", "од", "ат", "ет", "ит", "от", "ут",
    ]

    // Common English bigrams (high frequency) — expanded for inline detection
    private let englishBigrams: Set<String> = [
        "th", "he", "in", "er", "an", "re", "on", "at", "en",
        "nd", "ti", "es", "or", "te", "of", "ed", "is", "it",
        "al", "ar", "st", "to", "nt", "ng", "se", "ha", "as",
        "ou", "io", "le", "ve", "co", "me", "de", "hi", "ri",
        "ro", "ic", "ne", "ea", "ra", "ce", "li", "ch", "ll",
        "be", "ma", "si", "om", "ur", "ca", "el", "ta", "la",
        "ns", "ge", "ly", "sh", "wh", "oo", "ee", "ck",
        // Expanded for inline detection (common word-start and mid-word bigrams)
        "wo", "wa", "we", "wi", "no", "do", "go", "so", "ho",
        "ba", "bo", "bu", "da", "di", "dr", "fa", "fe", "fi",
        "fo", "fr", "fu", "gr", "gu", "ke", "ki", "kn", "lo",
        "mi", "mo", "mu", "na", "ni", "nu", "pa", "pe", "pi",
        "po", "pr", "pu", "ru", "sa", "sc", "sk", "sl", "sm",
        "sn", "sp", "sq", "su", "sw", "sy", "tr", "tu", "tw",
        "ty", "un", "up", "us", "vi", "ye", "ab", "ac", "ad",
        "ag", "am", "ap", "ay", "bi", "bl", "br", "cl", "cr",
        "cu", "em", "ev", "ex", "fl", "id", "il", "im", "op",
        "ot", "ov", "ow", "ph", "pl", "qu", "wr", "if", "my",
    ]

    init() {
        loadDictionaries()
    }

    private func loadDictionaries() {
        // Try multiple locations for resource files
        let possibleBasePaths = [
            // Next to the executable
            URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().path(percentEncoded: false),
            // SPM build resource bundle
            Bundle.main.resourcePath,
            // Relative to working directory
            FileManager.default.currentDirectoryPath + "/Resources",
            // Hardcoded fallback for development
            URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources").path(percentEncoded: false),
        ].compactMap { $0 }

        for basePath in possibleBasePaths {
            let enPath = (basePath as NSString).appendingPathComponent("english_words.txt")
            if FileManager.default.fileExists(atPath: enPath) {
                if let content = try? String(contentsOfFile: enPath, encoding: .utf8) {
                    englishWords = Set(content.components(separatedBy: CharacterSet.newlines)
                        .map { $0.trimmingCharacters(in: CharacterSet.whitespaces).lowercased()
                            .replacingOccurrences(of: "\u{2019}", with: "'") }
                        .filter { !$0.isEmpty })
                }
                let ukPath = (basePath as NSString).appendingPathComponent("ukrainian_words.txt")
                if let content = try? String(contentsOfFile: ukPath, encoding: .utf8) {
                    ukrainianWords = Set(content.components(separatedBy: CharacterSet.newlines)
                        .map { $0.trimmingCharacters(in: CharacterSet.whitespaces).lowercased()
                            .replacingOccurrences(of: "\u{2019}", with: "'") }
                        .filter { !$0.isEmpty })
                }
                print("[PuntoSwitcher] Loaded dictionaries from: \(basePath)")
                break
            }
        }

        // Also check the SPM resource bundle
        if englishWords.isEmpty {
            if let bundlePath = Bundle.main.path(forResource: "PuntoSwitcher_PuntoSwitcher", ofType: "bundle"),
               let resourceBundle = Bundle(path: bundlePath) {
                if let enPath = resourceBundle.path(forResource: "english_words", ofType: "txt"),
                   let content = try? String(contentsOfFile: enPath, encoding: .utf8) {
                    englishWords = Set(content.components(separatedBy: CharacterSet.newlines)
                        .map { $0.trimmingCharacters(in: CharacterSet.whitespaces).lowercased()
                            .replacingOccurrences(of: "\u{2019}", with: "'") }
                        .filter { !$0.isEmpty })
                }
                if let ukPath = resourceBundle.path(forResource: "ukrainian_words", ofType: "txt"),
                   let content = try? String(contentsOfFile: ukPath, encoding: .utf8) {
                    ukrainianWords = Set(content.components(separatedBy: CharacterSet.newlines)
                        .map { $0.trimmingCharacters(in: CharacterSet.whitespaces).lowercased()
                            .replacingOccurrences(of: "\u{2019}", with: "'") }
                        .filter { !$0.isEmpty })
                }
                print("[PuntoSwitcher] Loaded dictionaries from resource bundle")
            }
        }

        print("[PuntoSwitcher] Loaded \(englishWords.count) English words, \(ukrainianWords.count) Ukrainian words")
    }

    /// Detect if a word typed in the current layout is actually meant for the other layout.
    /// - Parameters:
    ///   - typedWord: The word as typed by the user
    ///   - currentLayoutIsEnglish: Whether the current input source is English
    /// - Returns: `true` if the word should be switched to the other layout
    func shouldSwitch(typedWord: String, currentLayoutIsEnglish: Bool) -> Bool {
        let word = typedWord.trimmingCharacters(in: .whitespaces)
        guard word.count >= 2 else { return false }

        if currentLayoutIsEnglish {
            // User typed Latin chars but maybe meant Ukrainian
            guard KeyboardLayoutMap.isLatin(word) else { return false }
            let converted = KeyboardLayoutMap.convertToUkrainian(word)
            guard KeyboardLayoutMap.isCyrillic(converted) else { return false }

            let typedResult = detectEnglish(word)
            let convertedResult = detectUkrainian(converted)

            // Switch only if converted word is confidently the other language
            // AND there's a meaningful gap between the two scores
            let gap = convertedResult.confidence - typedResult.confidence
            if convertedResult.confidence > 0.6 && gap > 0.25 {
                return true
            }
        } else {
            // User typed with Ukrainian layout but maybe meant English
            let converted = KeyboardLayoutMap.convertToEnglish(word)
            guard KeyboardLayoutMap.isLatin(converted) else { return false }

            let typedResult = detectUkrainian(word)
            let convertedResult = detectEnglish(converted)

            let gap = convertedResult.confidence - typedResult.confidence
            if convertedResult.confidence > 0.6 && gap > 0.25 {
                return true
            }
        }

        return false
    }

    /// Get the converted version of a word
    func convertWord(_ typedWord: String, currentLayoutIsEnglish: Bool) -> String {
        if currentLayoutIsEnglish {
            return KeyboardLayoutMap.convertToUkrainian(typedWord)
        } else {
            return KeyboardLayoutMap.convertToEnglish(typedWord)
        }
    }

    // MARK: - Inline Detection (2-3 characters)

    /// Check if the buffer typed so far (2+ chars) clearly belongs to the wrong layout.
    /// Uses strict bigram ratio analysis — only switches on high-confidence mismatches.
    func shouldSwitchInline(buffer: String, currentLayoutIsEnglish: Bool) -> Bool {
        guard buffer.count >= 2 else { return false }
        let word = buffer.lowercased()

        if currentLayoutIsEnglish {
            guard KeyboardLayoutMap.isLatin(word) else { return false }

            // If it's a known English word, never switch
            if englishWordMatch(word) { return false }

            let converted = KeyboardLayoutMap.convertToUkrainian(word)
            guard KeyboardLayoutMap.isCyrillic(converted) else { return false }

            // If converted is a known Ukrainian word, strong signal
            if ukrainianWordMatch(converted) && !englishWordMatch(word) {
                return true
            }

            let enRatio = rawBigramRatio(word: word, bigrams: englishBigrams)
            let ukRatio = rawBigramRatio(word: converted, bigrams: ukrainianBigrams)

            if word.count == 2 {
                // Very strict: typed bigram not English at all, converted is valid Ukrainian
                return enRatio == 0.0 && ukRatio > 0.0
            }

            // 3+ chars: current looks bad, converted looks good
            return enRatio < 0.6 && ukRatio > 0.7 && (ukRatio - enRatio) > 0.3
        } else {
            // Ukrainian layout — user might be typing English
            let converted = KeyboardLayoutMap.convertToEnglish(word)
            guard KeyboardLayoutMap.isLatin(converted) else { return false }

            if ukrainianWordMatch(word) { return false }

            if englishWordMatch(converted) && !ukrainianWordMatch(word) {
                return true
            }

            let ukRatio = rawBigramRatio(word: word, bigrams: ukrainianBigrams)
            let enRatio = rawBigramRatio(word: converted, bigrams: englishBigrams)

            if word.count == 2 {
                return ukRatio == 0.0 && enRatio > 0.0
            }

            return ukRatio < 0.6 && enRatio > 0.7 && (enRatio - ukRatio) > 0.3
        }
    }

    /// Raw bigram match ratio (0.0 to 1.0) — used for inline detection
    private func rawBigramRatio(word: String, bigrams: Set<String>) -> Double {
        let chars = Array(word.lowercased())
        guard chars.count >= 2 else { return 0.0 }
        var matches = 0
        let total = chars.count - 1
        for i in 0..<total {
            let bigram = String(chars[i...i+1])
            if bigrams.contains(bigram) {
                matches += 1
            }
        }
        return Double(matches) / Double(total)
    }

    // MARK: - Private Detection Methods

    private func detectEnglish(_ word: String) -> DetectionResult {
        let lower = word.lowercased()
        var confidence: Double = 0.0

        // Dictionary check (strongest signal) — also try common stems and collapsed repeats
        if englishWordMatch(lower) {
            confidence = 0.95
            return DetectionResult(language: .english, confidence: confidence)
        }

        // Bigram analysis
        let bigramScore = bigramScore(word: lower, bigrams: englishBigrams)
        confidence = max(confidence, bigramScore)

        // Check for common English patterns (suffix match = likely English)
        if lower.hasSuffix("ing") || lower.hasSuffix("tion") || lower.hasSuffix("ness") ||
           lower.hasSuffix("ment") || lower.hasSuffix("able") || lower.hasSuffix("ible") ||
           lower.hasSuffix("ly") || lower.hasSuffix("ed") || lower.hasSuffix("er") ||
           lower.hasSuffix("est") || lower.hasSuffix("ous") || lower.hasSuffix("ful") ||
           lower.hasSuffix("less") || lower.hasSuffix("ize") || lower.hasSuffix("ise") ||
           lower.hasSuffix("ary") || lower.hasSuffix("ory") || lower.hasSuffix("ive") ||
           lower.hasSuffix("al") || lower.hasSuffix("ence") || lower.hasSuffix("ance") {
            confidence = max(confidence, 0.75)
        }

        // Common English short suffixes: -s, -es, -'s (plurals/possessives)
        if (lower.hasSuffix("s") || lower.hasSuffix("es")) && lower.count >= 3 {
            confidence = max(confidence, 0.5)
        }

        // Penalize if it looks like garbage (too many consonants in a row)
        if hasExcessiveConsonantClusters(lower, language: .english) {
            confidence *= 0.3
        }

        return DetectionResult(language: .english, confidence: confidence)
    }

    /// Check if the word matches a dictionary entry after removing common English suffixes
    private func englishStemMatch(_ word: String) -> Bool {
        let suffixes = ["s", "es", "ed", "ing", "er", "est", "ly", "ment",
                        "ness", "tion", "sion", "able", "ible", "ful", "less",
                        "ize", "ise", "ous", "ive", "al", "en", "ary", "ory"]
        for suffix in suffixes {
            if word.count > suffix.count + 1 && word.hasSuffix(suffix) {
                let stem = String(word.dropLast(suffix.count))
                if englishWords.contains(stem) { return true }
                // Handle doubling: "running" → "run" (drop extra consonant)
                if stem.count >= 2 && stem.last == stem[stem.index(before: stem.endIndex)] {
                    let shortened = String(stem.dropLast())
                    if englishWords.contains(shortened) { return true }
                }
                // Handle e-dropping: "making" → "make" (add back 'e')
                if englishWords.contains(stem + "e") { return true }
            }
        }
        // Also try removing just 's' for plurals like "works" → "work"
        if word.hasSuffix("s") && word.count >= 3 {
            let stem = String(word.dropLast())
            if englishWords.contains(stem) { return true }
        }
        return false
    }

    private func detectUkrainian(_ word: String) -> DetectionResult {
        let lower = word.lowercased()
        var confidence: Double = 0.0

        // Must contain Cyrillic
        guard KeyboardLayoutMap.isCyrillic(lower) else {
            return DetectionResult(language: .unknown, confidence: 0.0)
        }

        // Dictionary check (including collapsed repeats like нуууу → ну)
        if ukrainianWordMatch(lower) {
            confidence = 0.95
            return DetectionResult(language: .ukrainian, confidence: confidence)
        }

        // Bigram analysis
        let bigramScore = bigramScore(word: lower, bigrams: ukrainianBigrams)
        confidence = max(confidence, bigramScore)

        // Common Ukrainian suffixes
        if lower.hasSuffix("ти") || lower.hasSuffix("ка") || lower.hasSuffix("ко") ||
           lower.hasSuffix("ні") || lower.hasSuffix("но") || lower.hasSuffix("на") ||
           lower.hasSuffix("ся") || lower.hasSuffix("ій") || lower.hasSuffix("ий") ||
           lower.hasSuffix("ою") || lower.hasSuffix("ів") || lower.hasSuffix("ок") {
            confidence = max(confidence, 0.7)
        }

        // Ukrainian-specific characters give a small boost (not enough alone to trigger switch)
        let ukrainianSpecific: [Character] = ["ї", "є", "ґ"]
        if lower.contains(where: { ukrainianSpecific.contains($0) }) {
            confidence = max(confidence, 0.45)
        }
        // "і" alone is too common from key mapping — only boost slightly
        if lower.contains("і") {
            confidence = max(confidence, 0.3)
        }

        return DetectionResult(language: .ukrainian, confidence: confidence)
    }

    private func bigramScore(word: String, bigrams: Set<String>) -> Double {
        guard word.count >= 2 else { return 0.0 }
        let chars = Array(word)
        var matches = 0
        let total = chars.count - 1

        for i in 0..<total {
            let bigram = String(chars[i...i+1])
            if bigrams.contains(bigram) {
                matches += 1
            }
        }

        let ratio = Double(matches) / Double(total)
        // Scale: 0 matches = 0.1, all matches = 0.8
        return 0.1 + ratio * 0.7
    }

    /// Normalize apostrophes: both ' and ' (curly) become '
    private func normalizeApostrophes(_ word: String) -> String {
        return word.replacingOccurrences(of: "\u{2019}", with: "'")
    }

    /// Collapse repeated letters: "нуууу" → "ну", "дааа" → "да", "wooow" → "wow"
    private func collapseRepeats(_ word: String) -> String {
        var result: [Character] = []
        for ch in word {
            if result.last != ch {
                result.append(ch)
            }
        }
        return String(result)
    }

    /// Check if a word (or its collapsed form) is in the Ukrainian dictionary
    private func ukrainianWordMatch(_ word: String) -> Bool {
        let lower = normalizeApostrophes(word.lowercased())
        if ukrainianWords.contains(lower) { return true }
        let collapsed = collapseRepeats(lower)
        if collapsed != lower && ukrainianWords.contains(collapsed) { return true }
        return false
    }

    /// Check if a word (or its collapsed form) is in the English dictionary
    private func englishWordMatch(_ word: String) -> Bool {
        let lower = normalizeApostrophes(word.lowercased())
        if englishWords.contains(lower) || englishStemMatch(lower) { return true }
        let collapsed = collapseRepeats(lower)
        if collapsed != lower && (englishWords.contains(collapsed) || englishStemMatch(collapsed)) { return true }
        return false
    }

    private func hasExcessiveConsonantClusters(_ word: String, language: Language) -> Bool {
        let englishVowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]
        var consonantRun = 0
        for char in word {
            if englishVowels.contains(char) {
                consonantRun = 0
            } else if char.isLetter {
                consonantRun += 1
                if consonantRun >= 4 {
                    return true
                }
            }
        }
        return false
    }
}
