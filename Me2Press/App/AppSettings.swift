//
//  AppSettings.swift
//  Me2Press
//
//  Persists UI settings via UserDefaults and coordinates kindlegen probe results.
//

import SwiftUI

// MARK: - ChapterPattern

/// A chapter-detection regex rule with a stable UUID identity and a heading level.
/// `level`: 1 = part/volume (outermost), 2 = chapter, 3 = section. Defaults to 1.
struct ChapterPattern: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var value: String
    /// Heading level written to the EPUB TOC and HTML heading tag (h1–h3).
    var level: Int

    init(id: UUID = UUID(), value: String, level: Int = 1) {
        self.id = id
        self.value = value
        self.level = level
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, value, level
    }

    // IMPORTANT: `level` uses decodeIfPresent so existing data without the field
    // migrates silently to level 1 rather than throwing a decode error.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        value = try container.decode(String.self, forKey: .value)
        level = try container.decodeIfPresent(Int.self, forKey: .level) ?? 1
    }
}

// MARK: - AppSettings

@MainActor
@Observable
class AppSettings {
    static let concurrencyRange: ClosedRange<Int> = 1 ... 6

    // MARK: - Chapter Pattern Defaults

    static let defaultChapterPatterns: [ChapterPattern] = [
        ChapterPattern(value: "^\\s*(第[0-9０-９一二三四五六七八九十零〇百千两]+[章回部节集卷]).*", level: 1),
        ChapterPattern(value: "^\\s*(简介|序言|序[一二三四五六七八九]?|序曲|前言|自序|后记|尾声|附录|楔子|番外).*", level: 1)
    ]

    // MARK: - KindleGen

    var kindlegenURL: URL? {
        didSet {
            UserDefaults.standard.set(kindlegenURL?.path, forKey: "kindlegenPath")
        }
    }

    var isKindleGenReady = false
    var kindlegenVersion = ""

    private let kindleGenProbeService = KindleGenProbeService()
    private var kindleGenProbeTask: Task<Void, Never>?
    private var kindleGenProbeGeneration = 0

    // MARK: - Concurrency

    /// Max parallel conversion tasks (1–6). Clamped in didSet; written to UserDefaults.
    var maxConcurrency: Int = 1 {
        didSet {
            let clamped = Self.concurrencyRange.clamp(maxConcurrency)
            if clamped != maxConcurrency {
                // Reassign the clamped value, but return immediately to avoid infinite recursion
                // (the second didSet will see clamped == maxConcurrency and fall through).
                maxConcurrency = clamped
                return
            }
            UserDefaults.standard.set(maxConcurrency, forKey: "maxConcurrency")
        }
    }

    // MARK: - Author

    /// Written to dc:creator in every newly generated EPUB and MOBI file.
    var authorName: String = "Me2Press" {
        didSet {
            UserDefaults.standard.set(authorName, forKey: "authorName")
        }
    }

    // MARK: - Chapter Patterns

    /// Regex rules used by TXTParser to detect chapter headings. Each rule is tested
    /// independently; the first match wins. Contains level info for TOC hierarchy.
    var chapterPatterns: [ChapterPattern] = AppSettings.defaultChapterPatterns {
        didSet {
            if let data = try? JSONEncoder().encode(chapterPatterns) {
                UserDefaults.standard.set(data, forKey: "chapterPatterns")
            }
        }
    }

    // MARK: - Init

    init() {
        if let path = UserDefaults.standard.string(forKey: "kindlegenPath") {
            kindlegenURL = URL(fileURLWithPath: path)
        }
        let saved = UserDefaults.standard.integer(forKey: "maxConcurrency")
        maxConcurrency = Self.concurrencyRange.contains(saved) ? saved : 1

        if let savedAuthor = UserDefaults.standard.string(forKey: "authorName") {
            authorName = savedAuthor
        }

        // Three-format migration path for chapter patterns stored across app versions:
        //   1. [ChapterPattern] with level — current format, decoded as-is.
        //   2. [ChapterPattern] without level — decoded via decodeIfPresent, level defaults to 1.
        //   3. [String] — oldest format; each string is wrapped into a ChapterPattern(level: 1).
        if let data = UserDefaults.standard.data(forKey: "chapterPatterns") {
            if let patterns = try? JSONDecoder().decode([ChapterPattern].self, from: data),
               !patterns.isEmpty
            {
                chapterPatterns = patterns
            } else if let strings = try? JSONDecoder().decode([String].self, from: data),
                      !strings.isEmpty
            {
                chapterPatterns = strings.map { ChapterPattern(value: $0, level: 1) }
            }
        }

        refreshKindleGenStatus()
    }
    // MARK: - KindleGen Actions

    func updateKindleGenURL(_ url: URL?) {
        kindlegenURL = url
        startKindleGenProbe(for: url)
    }

    func refreshKindleGenStatus() {
        startKindleGenProbe(for: kindlegenURL)
    }

    // MARK: - Private

    private func startKindleGenProbe(for url: URL?) {
        kindleGenProbeTask?.cancel()
        kindleGenProbeTask = nil
        kindleGenProbeGeneration += 1

        let generation = kindleGenProbeGeneration
        let expectedURL = url
        resetKindleGenStatus()

        guard let expectedURL else { return }

        let probeService = kindleGenProbeService
        kindleGenProbeTask = Task { @MainActor [weak self, probeService, generation, expectedURL] in
            let result = await probeService.probe(executableURL: expectedURL)
            guard !Task.isCancelled else { return }
            self?.applyKindleGenProbeResult(
                result,
                generation: generation,
                expectedURL: expectedURL
            )
        }
    }

    private func applyKindleGenProbeResult(
        _ result: KindleGenProbeResult,
        generation: Int,
        expectedURL: URL?
    ) {
        guard generation == kindleGenProbeGeneration, expectedURL == kindlegenURL else {
            return
        }

        isKindleGenReady = result.isReady
        kindlegenVersion = result.version
        kindleGenProbeTask = nil
    }

    private func resetKindleGenStatus() {
        isKindleGenReady = false
        kindlegenVersion = ""
    }
}

// MARK: - Helpers

private extension ClosedRange where Bound == Int {
    func clamp(_ value: Int) -> Int {
        Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}
