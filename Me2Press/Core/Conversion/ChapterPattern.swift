import Foundation

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
