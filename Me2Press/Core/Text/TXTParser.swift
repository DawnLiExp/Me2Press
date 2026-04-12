//
//  TXTParser.swift
//  Me2Press
//
//  Parses plain text files into chapters and paragraphs.
//  Chapter detection is driven by an external list of ChapterPattern from AppSettings.
//  Each pattern carries a `level` (1–3) that maps to the heading hierarchy in the EPUB.
//

import Foundation

struct ParsedBook {
    let title: String
    let chapters: [Chapter]
}

struct Chapter {
    let title: String
    let paragraphs: [String]
    /// Heading level: 1 = volume/part (outermost), 2 = chapter, 3 = section. Defaults to 1.
    let level: Int
}

actor TXTParser {
    init() {}

    private func getEncodingName(_ enc: String.Encoding) -> String {
        switch enc {
        case .utf8: return "UTF-8"
        case .utf16BigEndian: return "UTF-16 BE"
        case .utf16LittleEndian: return "UTF-16 LE"
        case .isoLatin1: return "ISO-Latin-1"
        default: return "GB18030"
        }
    }

    // MARK: - Parse

    /// - Parameter chapterPatterns: Rules from AppSettings including level metadata.
    ///   Invalid regexes are silently skipped; if all are invalid the built-in Chinese
    ///   chapter pattern is used as a fallback (level = 1).
    func parse(
        url: URL,
        indentParagraph: Bool,
        keepLineBreaks: Bool,
        chapterPatterns: [ChapterPattern]
    ) async throws(Me2PressError) -> ParsedBook {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw Me2PressError.emptyFile(name: url.lastPathComponent)
        }

        let encoding = detect(data: data)
        guard let text = String(data: data, encoding: encoding) else {
            throw Me2PressError.decodeFailed(encoding: getEncodingName(encoding))
        }

        let title = url.deletingPathExtension().lastPathComponent
        let lines = text.components(separatedBy: .newlines)

        var chapters = [Chapter]()
        var currentChapterTitle = title
        var currentLevel = 1
        var currentParagraphs = [String]()

        // ── Build regex rules from chapter patterns ────────────────────────────────
        let rules: [(regex: NSRegularExpression, level: Int)] = {
            let valid: [(regex: NSRegularExpression, level: Int)] = chapterPatterns
                .map { ($0.value.trimmingCharacters(in: .whitespaces), $0.level) }
                .filter { !$0.0.isEmpty }
                .compactMap { pattern, level in
                    (try? NSRegularExpression(pattern: pattern, options: []))
                        .map { ($0, level) }
                }

            if !valid.isEmpty { return valid }

            // IMPORTANT: If all patterns are invalid, fall back to the built-in Chinese chapter
            // regex so that TXT conversion never produces a single-chapter book unexpectedly.
            if let fallback = try? NSRegularExpression(
                pattern: "^\\s*(第[0-9０-９一二三四五六七八九十零〇百千两]+[章回部节集卷]).*",
                options: []
            ) {
                return [(fallback, 1)]
            }
            return []
        }()

        // Strip ASCII whitespace only; fullwidth space U+3000 is intentionally preserved
        // so Chinese paragraph indentation survives the non-indent mode path.
        let asciiWhitespace = CharacterSet(charactersIn: " \t\r\n")

        for rawLine in lines {
            let fullyTrimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if fullyTrimmed.isEmpty {
                if keepLineBreaks {
                    if !currentParagraphs.isEmpty, currentParagraphs.last != "__BLANK__" {
                        currentParagraphs.append("__BLANK__")
                    }
                }
                continue
            }

            let range = NSRange(location: 0, length: fullyTrimmed.utf16.count)
            let matchedRule = rules.first { rule in
                rule.regex.firstMatch(in: fullyTrimmed, options: [], range: range) != nil
            }

            if let rule = matchedRule {
                // ── Matched chapter heading ───────────────────────────────────────────
                var trimmed = currentParagraphs
                while trimmed.last == "__BLANK__" {
                    trimmed.removeLast()
                }

                // Save the current chapter before starting a new one.
                // Conditions that require saving even an empty chapter:
                // • Has body content — always save.
                // • Prior chapters exist — container headings (e.g. "Volume 1" before "Chapter 1") must be preserved.
                // • Title was overwritten by an earlier heading match — no longer the initial placeholder.
                // Skip only the very first placeholder: empty body, no prior chapters, title unchanged.
                let shouldSave = !trimmed.isEmpty
                    || !chapters.isEmpty
                    || currentChapterTitle != title

                if shouldSave {
                    chapters.append(Chapter(
                        title: currentChapterTitle,
                        paragraphs: trimmed,
                        level: currentLevel
                    ))
                }

                currentChapterTitle = fullyTrimmed
                currentLevel = rule.level
                currentParagraphs = []

            } else {
                // ── Body line ─────────────────────────────────────────────────────────
                let contentLine = indentParagraph
                    ? fullyTrimmed
                    : rawLine.trimmingCharacters(in: asciiWhitespace)

                let escaped = contentLine
                    .replacingOccurrences(of: "&", with: "&amp;")
                    .replacingOccurrences(of: "<", with: "&lt;")
                    .replacingOccurrences(of: ">", with: "&gt;")

                currentParagraphs.append(escaped)
            }
        }

        // ── Save the final chapter ────────────────────────────────────────────────
        var trimmedFinal = currentParagraphs
        while trimmedFinal.last == "__BLANK__" {
            trimmedFinal.removeLast()
        }

        let shouldSaveLast = !trimmedFinal.isEmpty
            || !chapters.isEmpty
            || currentChapterTitle != title

        if shouldSaveLast {
            chapters.append(Chapter(
                title: currentChapterTitle,
                paragraphs: trimmedFinal,
                level: currentLevel
            ))
        }

        // ── Empty-file fallback ───────────────────────────────────────────────────
        if chapters.isEmpty {
            chapters.append(Chapter(
                title: title,
                paragraphs: [String(localized: "error.empty_file")],
                level: 1
            ))
        }

        return ParsedBook(title: title, chapters: chapters)
    }

    // MARK: - Encoding Detection

    /// Detects file encoding using BOM sniffing first, then UTF-8 validation, then GB18030.
    /// Falls back to ISO-Latin-1 if all candidates fail, as it accepts any byte sequence.
    private func detect(data: Data) -> String.Encoding {
        if data.count >= 3, data[0] == 0xef, data[1] == 0xbb, data[2] == 0xbf {
            return .utf8
        }
        if data.count >= 2 {
            if data[0] == 0xfe, data[1] == 0xff { return .utf16BigEndian }
            if data[0] == 0xff, data[1] == 0xfe { return .utf16LittleEndian }
        }
        if String(data: data, encoding: .utf8) != nil { return .utf8 }
        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        ))
        if String(data: data, encoding: gb18030) != nil { return gb18030 }
        return .isoLatin1
    }
}
