import Foundation

enum ComicReadingDirection: String, CaseIterable, Identifiable, Sendable {
    case rightToLeft = "rtl"
    case leftToRight = "ltr"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .rightToLeft: String(localized: "comic.direction.rtl")
        case .leftToRight: String(localized: "comic.direction.ltr")
        }
    }

    nonisolated var writingMode: String { self == .rightToLeft ? "horizontal-rl" : "horizontal-lr" }
    nonisolated var firstPageSide: String { self == .rightToLeft ? "right" : "left" }
}
