import Foundation

enum OutputFormat: String, CaseIterable, Identifiable, Sendable {
    case epub = "EPUB"
    case azw3 = "AZW3"

    var id: String {
        rawValue
    }
}
