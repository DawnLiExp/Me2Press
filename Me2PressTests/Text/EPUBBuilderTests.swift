import Foundation
import Testing
@testable import Me2Press

@Suite("Text EPUB covers")
struct EPUBBuilderTests {
    @Test("Cover bytes, metadata and XHTML follow the actual image type",
          arguments: ["jpg", "jpeg", "png", "png-as-jpg"])
    func coverFormat(format: String) async throws {
        try await TestFileSystem.withTemporaryDirectory { directory in
            let isPNG = format.hasPrefix("png")
            var cover = try TestFileSystem.writeImage(named: "selected.\(isPNG ? "png" : format)", in: directory)
            if format == "png-as-jpg" {
                let renamed = directory.appendingPathComponent("renamed.jpg")
                try FileManager.default.moveItem(at: cover, to: renamed)
                cover = renamed
            }
            let output = directory.appendingPathComponent("epub")
            try await EPUBBuilder.buildAsync(
                book: ParsedBook(title: "Book", chapters: [Chapter(title: "Chapter", paragraphs: ["Body"], level: 1)]),
                uuid: "test", coverImage: cover, indentParagraph: true, author: "Author", tempDir: output
            )
            let filename = isPNG ? "cover.png" : "cover.jpg"
            let opf = try XMLDocument(contentsOf: output.appendingPathComponent("OEBPS/content.opf"))
            let item = try #require(opf.nodes(forXPath: "//*[@properties='cover-image']").first as? XMLElement)
            #expect(item.attribute(forName: "href")?.stringValue == "Images/\(filename)")
            #expect(item.attribute(forName: "media-type")?.stringValue == (isPNG ? "image/png" : "image/jpeg"))
            let meta = try #require(opf.nodes(forXPath: "//*[@name='cover']").first as? XMLElement)
            #expect(meta.attribute(forName: "content")?.stringValue == item.attribute(forName: "id")?.stringValue)
            let page = try XMLDocument(contentsOf: output.appendingPathComponent("OEBPS/Text/cover.xhtml"))
            let image = try #require(page.nodes(forXPath: "//*[local-name()='img']").first as? XMLElement)
            #expect(image.attribute(forName: "src")?.stringValue == "../Images/\(filename)")
            #expect(try Data(contentsOf: output.appendingPathComponent("OEBPS/Images/\(filename)")) == Data(contentsOf: cover))
        }
    }

    @Test("An unreadable selected cover fails instead of silently disappearing")
    func unreadableCover() async throws {
        try await TestFileSystem.withTemporaryDirectory { directory in
            let cover = directory.appendingPathComponent("missing.png")
            await #expect(throws: Me2PressError.self) {
                try await EPUBBuilder.buildAsync(
                    book: ParsedBook(title: "Book", chapters: []), uuid: "test", coverImage: cover,
                    indentParagraph: true, author: "", tempDir: directory.appendingPathComponent("epub")
                )
            }
        }
    }
}
