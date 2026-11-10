import Foundation
import Testing
@testable import Me2Press

struct ComicCLISettingsTests {
    @Test("Reading CLI settings preserves stored preferences")
    func readOnlySnapshot() throws {
        let domain = "Me2PressCLI.test.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set("/custom/kindlegen", forKey: "kindlegenPath")
        defaults.set(3, forKey: "maxConcurrency")
        defaults.set("Author", forKey: "authorName")
        defaults.set("ltr", forKey: "comicReadingDirection")
        let before = NSDictionary(dictionary: defaults.persistentDomain(forName: domain) ?? [:])
        let settings = ComicCLISettings.load(defaults: defaults)
        #expect(settings.kindlegenPath == "/custom/kindlegen")
        #expect(settings.maxConcurrency == 3)
        #expect(settings.authorName == "Author")
        #expect(settings.readingDirection == "ltr")
        #expect(before.isEqual(to: defaults.persistentDomain(forName: domain) ?? [:]))
    }
}
