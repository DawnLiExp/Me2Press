import Foundation
import Testing
@testable import Me2Press

@Suite("Comic queue cover assignments")
@MainActor
struct ComicBookViewModelTests {
    @Test("Reordering, removing and clearing keep covers attached to their source books")
    func coverAssignments() async throws {
        try await TestFileSystem.withTemporaryDirectory { directory in
            let a = try TestFileSystem.createDirectory(named: "A", in: directory)
            let b = try TestFileSystem.createDirectory(named: "B", in: directory)
            _ = try TestFileSystem.writeImage(named: "001.jpg", in: a)
            _ = try TestFileSystem.writeImage(named: "001.jpg", in: b)
            let coverA = try TestFileSystem.writeImage(named: "coverA.jpg", in: directory)
            let coverB = try TestFileSystem.writeImage(named: "coverB.png", in: directory)
            let model = ComicBookViewModel()
            _ = await model.add([a, b])
            let sources = model.items
            model.setCover(coverA, for: sources[0])
            model.setCover(coverB, for: sources[1])
            model.move(from: IndexSet(integer: 0), to: 2)
            #expect(model.items == Array(sources.reversed()))
            #expect(model.coverURL(for: sources[0]) == coverA)
            #expect(model.coverURL(for: sources[1]) == coverB)
            model.remove(sources[1])
            #expect(model.coverURL(for: sources[1]) == nil)
            model.clearAll()
            #expect(model.items.isEmpty)
            #expect(model.coverURL(for: sources[0]) == nil)
        }
    }

    @Test("Failed retries retain the original direction and cover, including an absent cover", arguments: [true, false])
    func retrySnapshot(hasCover: Bool) async throws {
        try await TestFileSystem.withTemporaryDirectory { directory in
            let source = try TestFileSystem.createDirectory(named: "Book", in: directory)
            _ = try TestFileSystem.writeImage(named: "001.jpg", in: source)
            let oldCover = try TestFileSystem.writeImage(named: "old.jpg", in: directory)
            let newCover = try TestFileSystem.writeImage(named: "new.png", in: directory)
            let tool = try TestFileSystem.writeExecutableScript("""
            if [ "$#" -eq 2 ]; then printf 'Amazon kindlegen TEST\\n'; exit 0; fi
            cp "$4" "$0.captured.epub"
            printf 'Error(prcgen):E99999: test failure\\n'
            exit 2
            """, in: directory)
            let suite = "Me2PressTests-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let settings = AppSettings(defaults: defaults)
            settings.updateKindleGenURL(tool)
            try await waitWhile { settings.kindleGenStatus == .checking }
            try #require(settings.isKindleGenReady)
            settings.comicReadingDirection = .leftToRight
            let model = ComicBookViewModel()
            _ = await model.add([source])
            let canonicalSource = try #require(model.items.first)
            if hasCover { model.setCover(oldCover, for: canonicalSource) }
            let logger = LogManager()
            model.startConversion(appSettings: settings, logger: logger)
            try await waitWhile { model.isConverting }
            try #require(model.progress.failures.count == 1)
            settings.comicReadingDirection = .rightToLeft
            model.setCover(newCover, for: canonicalSource)
            model.retryFailed(appSettings: settings, logger: logger)
            try await waitWhile { model.isConverting }
            let archive = URL(fileURLWithPath: tool.path + ".captured.epub")
            let opf = try XMLDocument(data: TestFileSystem.readZIPEntry("OEBPS/content.opf", from: archive))
            let spine = try #require(opf.nodes(forXPath: "//*[local-name()='spine']").first as? XMLElement)
            #expect(spine.attribute(forName: "page-progression-direction")?.stringValue == "ltr")
            #expect((spine.children ?? []).compactMap { $0 as? XMLElement }.count == (hasCover ? 2 : 1))
            let packedCover = try TestFileSystem.readZIPEntry("OEBPS/Images/img-0001.jpg", from: archive)
            #expect(packedCover == (try Data(contentsOf: hasCover ? oldCover : source.appendingPathComponent("001.jpg"))))
        }
    }

    private func waitWhile(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while condition(), ContinuousClock.now < deadline { await Task.yield() }
        try #require(!condition(), "Background operation did not finish")
    }
}
