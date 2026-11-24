import Foundation
import CoreFoundation

/// A single word/character (or phrase unit) paired with its phonetic reading (when applicable).
public struct AnnotatedChar: Equatable {
    public let character: String
    public let phonetic: String

    public init(character: String, phonetic: String) {
        self.character = character
        self.phonetic = phonetic
    }
}

public enum DetectedScript: String, Equatable {
    case latin = "Latin"
    case chinese = "Chinese"
    case japanese = "Japanese"
    case korean = "Korean"
    case arabic = "Arabic"
    case cyrillic = "Cyrillic"
    case thai = "Thai"
    case devanagari = "Devanagari"
    case greek = "Greek"
    case hebrew = "Hebrew"
    case otherNonLatin = "OtherNonLatin"
}

public enum PhoneticConverter {

    /// Detects the primary script of a text line across all world languages.
    public static func detectScript(_ text: String) -> DetectedScript {
        var counts: [DetectedScript: Int] = [:]
        var hasHiraganaOrKatakana = false

        for scalar in text.unicodeScalars {
            let v = scalar.value
            if (0x3040...0x309F).contains(v) || (0x30A0...0x30FF).contains(v) || (0x31F0...0x31FF).contains(v) {
                hasHiraganaOrKatakana = true
                counts[.japanese, default: 0] += 2
            } else if (0xAC00...0xD7AF).contains(v) || (0x1100...0x11FF).contains(v) || (0x3130...0x318F).contains(v) {
                counts[.korean, default: 0] += 2
            } else if (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) || (0xF900...0xFAFF).contains(v) {
                counts[.chinese, default: 0] += 1
            } else if (0x0600...0x06FF).contains(v) || (0x0750...0x077F).contains(v) || (0x08A0...0x08FF).contains(v) || (0xFB50...0xFDFF).contains(v) || (0xFE70...0xFEFF).contains(v) {
                counts[.arabic, default: 0] += 1
            } else if (0x0400...0x052F).contains(v) {
                counts[.cyrillic, default: 0] += 1
            } else if (0x0E00...0x0E7F).contains(v) {
                counts[.thai, default: 0] += 1
            } else if (0x0900...0x097F).contains(v) {
                counts[.devanagari, default: 0] += 1
            } else if (0x0370...0x03FF).contains(v) || (0x1F00...0x1FFF).contains(v) {
                counts[.greek, default: 0] += 1
            } else if (0x0590...0x05FF).contains(v) {
                counts[.hebrew, default: 0] += 1
            } else if (0x0041...0x005A).contains(v) || (0x0061...0x007A).contains(v) || (0x00C0...0x024F).contains(v) || (0x1E00...0x1EFF).contains(v) {
                counts[.latin, default: 0] += 1
            } else if CharacterSet.letters.contains(scalar) {
                counts[.otherNonLatin, default: 0] += 1
            }
        }

        if hasHiraganaOrKatakana {
            return .japanese
        }

        let nonLatinCounts = counts.filter { $0.key != .latin }
        if let topNonLatin = nonLatinCounts.max(by: { $0.value < $1.value }), topNonLatin.value > 0 {
            return topNonLatin.key
        }

        return .latin
    }

    /// Automatically annotates a line of lyrics across all languages:
    /// - Latin-script lines render cleanly without redundant phonetic clutter.
    /// - Non-Latin scripts (Chinese, Japanese, Korean, Arabic, Cyrillic, Thai, Indic, Greek, Hebrew, etc.) are automatically romanized.
    public static func annotate(_ text: String) -> [AnnotatedChar] {
        guard !text.isEmpty else { return [] }

        let script = detectScript(text)
        switch script {
        case .latin:
            return annotateLatinOnly(text)
        case .chinese:
            return annotateChinese(text)
        case .japanese:
            return annotateJapanese(text)
        case .korean:
            return annotateKorean(text)
        case .thai:
            return annotateSegmentedLocale(text, localeIdentifier: "th")
        case .arabic, .cyrillic, .greek, .hebrew, .devanagari, .otherNonLatin:
            return annotateWordLevelAnyLatin(text)
        }
    }

    // MARK: - Latin Script

    private static func annotateLatinOnly(_ text: String) -> [AnnotatedChar] {
        let tokens = tokenizeWordsPreservingSpaces(text)
        return tokens.map { AnnotatedChar(character: $0, phonetic: "") }
    }

    // MARK: - Chinese (Hanzi -> Pinyin with tones)

    private static func annotateChinese(_ text: String) -> [AnnotatedChar] {
        var result: [AnnotatedChar] = []
        for ch in text {
            let s = String(ch)
            if ch.isWhitespace {
                result.append(AnnotatedChar(character: " ", phonetic: ""))
            } else if ch.isPunctuation || ch.isSymbol {
                result.append(AnnotatedChar(character: s, phonetic: ""))
            } else if isCJKIdeograph(ch) {
                let mutable = NSMutableString(string: s)
                CFStringTransform(mutable, nil, kCFStringTransformMandarinLatin, false)
                let py = (mutable as String).trimmingCharacters(in: .whitespaces)
                result.append(AnnotatedChar(character: s, phonetic: py))
            } else {
                result.append(AnnotatedChar(character: s, phonetic: ""))
            }
        }
        return result
    }

    // MARK: - Japanese (Kanji / Hiragana / Katakana -> Word-level Romaji)

    private static func annotateJapanese(_ text: String) -> [AnnotatedChar] {
        let cfText = text as CFString
        let length = CFStringGetLength(cfText)
        guard length > 0 else { return [] }

        let locale = CFLocaleCreate(nil, CFLocaleIdentifier("ja" as CFString))
        let tokenizer = CFStringTokenizerCreate(
            nil,
            cfText,
            CFRangeMake(0, length),
            kCFStringTokenizerUnitWordBoundary,
            locale
        )

        var result: [AnnotatedChar] = []
        var lastEnd: CFIndex = 0

        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)

            if range.location > lastEnd {
                let gap = substring(cfText, from: lastEnd, length: range.location - lastEnd)
                appendGapTokens(gap, to: &result)
            }

            let word = substring(cfText, from: range.location, length: range.length)
            lastEnd = range.location + range.length

            if word.allSatisfy({ $0.isWhitespace }) {
                result.append(AnnotatedChar(character: " ", phonetic: ""))
                continue
            }
            if word.allSatisfy({ $0.isPunctuation || $0.isSymbol }) {
                result.append(AnnotatedChar(character: word, phonetic: ""))
                continue
            }

            if let latinRef = CFStringTokenizerCopyCurrentTokenAttribute(
                tokenizer,
                kCFStringTokenizerAttributeLatinTranscription
            ), let romaji = latinRef as? String, !romaji.isEmpty {
                let cleaned = cleanRomaji(romaji)
                let showPhonetic = !isPureASCII(word)
                result.append(AnnotatedChar(character: word, phonetic: showPhonetic ? cleaned : ""))
            } else {
                let romaji = fallbackJapaneseRomaji(word)
                let showPhonetic = !isPureASCII(word)
                result.append(AnnotatedChar(character: word, phonetic: showPhonetic ? romaji : ""))
            }
        }

        if lastEnd < length {
            let gap = substring(cfText, from: lastEnd, length: length - lastEnd)
            appendGapTokens(gap, to: &result)
        }

        return result
    }

    private static func fallbackJapaneseRomaji(_ word: String) -> String {
        let mutable = NSMutableString(string: word)
        CFStringTransform(mutable, nil, kCFStringTransformHiraganaKatakana, true)
        CFStringTransform(mutable, nil, kCFStringTransformLatinHiragana, false)
        return cleanRomaji(mutable as String)
    }

    private static func cleanRomaji(_ s: String) -> String {
        let mutable = NSMutableString(string: s)
        CFStringTransform(mutable, nil, kCFStringTransformStripCombiningMarks, false)
        return (mutable as String).trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Korean (Hangul -> Revised Romanization)

    private static func annotateKorean(_ text: String) -> [AnnotatedChar] {
        var result: [AnnotatedChar] = []
        for ch in text {
            let s = String(ch)
            if ch.isWhitespace {
                result.append(AnnotatedChar(character: " ", phonetic: ""))
            } else if ch.isPunctuation || ch.isSymbol {
                result.append(AnnotatedChar(character: s, phonetic: ""))
            } else if isHangul(ch) {
                let mutable = NSMutableString(string: s)
                CFStringTransform(mutable, nil, kCFStringTransformLatinHangul, false)
                let rom = (mutable as String).trimmingCharacters(in: .whitespaces)
                result.append(AnnotatedChar(character: s, phonetic: rom))
            } else {
                result.append(AnnotatedChar(character: s, phonetic: ""))
            }
        }
        return result
    }

    // MARK: - Word-Segmented Script (Thai)

    private static func annotateSegmentedLocale(_ text: String, localeIdentifier: String) -> [AnnotatedChar] {
        let cfText = text as CFString
        let length = CFStringGetLength(cfText)
        guard length > 0 else { return [] }

        let locale = CFLocaleCreate(nil, CFLocaleIdentifier(localeIdentifier as CFString))
        let tokenizer = CFStringTokenizerCreate(
            nil,
            cfText,
            CFRangeMake(0, length),
            kCFStringTokenizerUnitWordBoundary,
            locale
        )

        var result: [AnnotatedChar] = []
        var lastEnd: CFIndex = 0

        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            if range.location > lastEnd {
                let gap = substring(cfText, from: lastEnd, length: range.location - lastEnd)
                appendGapTokens(gap, to: &result)
            }

            let word = substring(cfText, from: range.location, length: range.length)
            lastEnd = range.location + range.length

            if word.allSatisfy({ $0.isWhitespace }) {
                result.append(AnnotatedChar(character: " ", phonetic: ""))
            } else if word.allSatisfy({ $0.isPunctuation || $0.isSymbol }) {
                result.append(AnnotatedChar(character: word, phonetic: ""))
            } else if isPureASCII(word) {
                result.append(AnnotatedChar(character: word, phonetic: ""))
            } else {
                let latin = transliterateAnyLatin(word)
                result.append(AnnotatedChar(character: word, phonetic: latin))
            }
        }

        if lastEnd < length {
            let gap = substring(cfText, from: lastEnd, length: length - lastEnd)
            appendGapTokens(gap, to: &result)
        }

        return result
    }

    // MARK: - Word-Level Alphabetic / Abjad / Abugida Scripts

    private static func annotateWordLevelAnyLatin(_ text: String) -> [AnnotatedChar] {
        let tokens = tokenizeWordsPreservingSpaces(text)
        return tokens.map { token in
            if token.allSatisfy({ $0.isWhitespace }) {
                return AnnotatedChar(character: " ", phonetic: "")
            }
            if token.allSatisfy({ $0.isPunctuation || $0.isSymbol }) || isPureASCII(token) {
                return AnnotatedChar(character: token, phonetic: "")
            }
            let romanized = transliterateAnyLatin(token)
            return AnnotatedChar(character: token, phonetic: romanized)
        }
    }

    // MARK: - Transliteration Helpers

    private static func transliterateAnyLatin(_ text: String) -> String {
        let mutable = NSMutableString(string: text)
        CFStringTransform(mutable, nil, "Any-Latin" as CFString, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripCombiningMarks, false)
        let out = (mutable as String).trimmingCharacters(in: .whitespacesAndNewlines)
        return out == text ? "" : out
    }

    private static func tokenizeWordsPreservingSpaces(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inWhitespace = false

        for ch in text {
            if ch.isWhitespace {
                if !inWhitespace && !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                inWhitespace = true
                current = " "
            } else {
                if inWhitespace && !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                inWhitespace = false
                current.append(ch)
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    private static func substring(_ cfStr: CFString, from start: CFIndex, length: CFIndex) -> String {
        let sub = CFStringCreateWithSubstring(nil, cfStr, CFRangeMake(start, length))!
        return sub as String
    }

    private static func appendGapTokens(_ gap: String, to result: inout [AnnotatedChar]) {
        for ch in gap {
            if ch.isWhitespace {
                result.append(AnnotatedChar(character: " ", phonetic: ""))
            } else {
                result.append(AnnotatedChar(character: String(ch), phonetic: ""))
            }
        }
    }

    private static func isCJKIdeograph(_ ch: Character) -> Bool {
        for s in ch.unicodeScalars {
            let v = s.value
            if (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) || (0xF900...0xFAFF).contains(v) {
                return true
            }
        }
        return false
    }

    private static func isHangul(_ ch: Character) -> Bool {
        for s in ch.unicodeScalars {
            let v = s.value
            if (0xAC00...0xD7AF).contains(v) || (0x1100...0x11FF).contains(v) || (0x3130...0x318F).contains(v) {
                return true
            }
        }
        return false
    }

    private static func isPureASCII(_ s: String) -> Bool {
        return s.unicodeScalars.allSatisfy { $0.value < 0x80 }
    }
}
