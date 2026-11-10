import Foundation

/// A read-only snapshot. Loading it never initializes the UI settings or its probe task.
nonisolated struct ComicCLISettings: Codable, Sendable {
    let kindlegenPath: String
    let maxConcurrency: Int
    let authorName: String
    let readingDirection: String

    static func load(defaults: UserDefaults) -> Self {
        let savedConcurrency = defaults.integer(forKey: "maxConcurrency")
        return Self(
            kindlegenPath: defaults.string(forKey: "kindlegenPath") ?? "",
            maxConcurrency: (1...6).contains(savedConcurrency) ? savedConcurrency : 1,
            authorName: defaults.string(forKey: "authorName") ?? "Me2Press",
            readingDirection: defaults.string(forKey: "comicReadingDirection") ?? "rtl"
        )
    }

    func validate() throws {
        guard (1...6).contains(maxConcurrency),
              ComicReadingDirection(rawValue: readingDirection) != nil else {
            throw CLIRequestError("Invalid concurrency or readingDirection.")
        }
        guard FileManager.default.isExecutableFile(atPath: kindlegenPath) else {
            throw CLIRequestError("KindleGen is not executable: \(kindlegenPath)")
        }
    }
}
