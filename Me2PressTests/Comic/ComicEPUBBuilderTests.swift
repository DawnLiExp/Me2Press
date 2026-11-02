import Foundation
import Testing
@testable import Me2Press

@Suite("Comic EPUB layout")
struct ComicEPUBBuilderTests {
    @Test("Direction controls metadata and page sides, not natural file order", arguments: ComicReadingDirection.allCases)
    func readingDirection(direction: ComicReadingDirection) async throws {
        try await TestFileSystem.withTemporaryDirectory { directory in
            let input = try TestFileSystem.createDirectory(named: "输入", in: directory)
            let first = try TestFileSystem.writeImage(named: "001.png", in: input)
            let second = try TestFileSystem.writeImage(named: "002.jpg", width: 64, in: input)
            let third = try TestFileSystem.writeImage(named: "010.png", height: 64, in: input)
            let output = directory.appendingPathComponent("epub")
            try await ComicEPUBBuilder.build(folderURL: input, uuid: "test", author: "作者", tempDir: output, readingDirection: direction)
            let opf = try XMLDocument(contentsOf: output.appendingPathComponent("OEBPS/content.opf"))
            let spine = try #require(opf.nodes(forXPath: "//*[local-name()='spine']").first as? XMLElement)
            #expect(spine.attribute(forName: "page-progression-direction")?.stringValue == direction.rawValue)
            let writingMode = try #require(opf.nodes(forXPath: "//*[@name='primary-writing-mode']").first as? XMLElement)
            #expect(writingMode.attribute(forName: "content")?.stringValue == (direction == .rightToLeft ? "horizontal-rl" : "horizontal-lr"))
            let pages = (spine.children ?? []).compactMap { $0 as? XMLElement }
            let expected = direction == .rightToLeft ? ["right", "left", "right"] : ["left", "right", "left"]
            #expect(pages.map { $0.attribute(forName: "properties")?.stringValue } == expected.map { "page-spread-\($0)" })
            #expect(pages.map { $0.attribute(forName: "idref")?.stringValue } == ["page-0001", "page-0002", "page-0003"])
            for (name, source) in [("img-0001.png", first), ("img-0002.jpg", second), ("img-0003.png", third)] {
                #expect(try Data(contentsOf: output.appendingPathComponent("OEBPS/Images/\(name)")) == Data(contentsOf: source))
            }
            let secondPage = try XMLDocument(contentsOf: output.appendingPathComponent("OEBPS/Text/page-0002.xhtml"))
            let viewport = try #require(secondPage.nodes(forXPath: "//*[@name='viewport']").first as? XMLElement)
            #expect(viewport.attribute(forName: "content")?.stringValue == "width=64, height=48")
        }
    }

    @Test("New settings default to RTL and persist a changed direction")
    @MainActor
    func persistedDirection() throws {
        let suite = "Me2PressTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        #expect(settings.comicReadingDirection == .rightToLeft)
        settings.comicReadingDirection = .leftToRight
        #expect(AppSettings(defaults: defaults).comicReadingDirection == .leftToRight)
    }
}
