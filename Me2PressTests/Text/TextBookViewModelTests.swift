import Foundation
import ImageIO
import Testing
@testable import Me2Press

@Suite("Text queue cover assignments")
@MainActor
struct TextBookViewModelTests {
    @Test("Covers stay attached across aliases, reordering, replacement, removal and clearing")
    func coverAssignments() async throws {
        try await TestFileSystem.withTemporaryDirectory { directory in
            let a = try TestFileSystem.createDirectory(named: "A", in: directory)
            let b = try TestFileSystem.createDirectory(named: "B", in: directory)
            let first = try TestFileSystem.writeText("Body", named: "Book.txt", in: a)
            let second = try TestFileSystem.writeText("Body", named: "Book.txt", in: b)
            let alias = directory.appendingPathComponent("Alias.txt")
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: first)
            let coverA = try TestFileSystem.writeImage(named: "a.jpg", in: directory)
            let coverB = try TestFileSystem.writeImage(named: "b.png", in: directory)
            let model = TextBookViewModel()
            let summary = await model.add([first, second, alias])
            #expect(summary.addedCount == 2)
            #expect(summary.duplicateCount == 1)
            model.setCover(coverA, for: alias)
            model.setCover(coverB, for: second)
            #expect(model.coverURL(for: first) == coverA)
            model.setCover(coverB, for: first)
            #expect(model.coverURL(for: alias) == coverB)
            model.setCover(nil, for: first)
            #expect(model.coverURL(for: alias) == nil)
            model.setCover(coverA, for: first)
            model.move(from: IndexSet(integer: 0), to: 2)
            #expect(model.items == [second, first])
            #expect(model.coverURL(for: first) == coverA)
            #expect(model.coverURL(for: second) == coverB)
            model.remove(first)
            _ = await model.add([first])
            #expect(model.coverURL(for: first) == nil)
            model.clearAll()
            #expect(model.items.isEmpty)
            #expect(model.coverURL(for: second) == nil)
        }
    }

    @Test("A concurrent batch independently packages JPG, PNG and generated covers")
    func mixedCovers() async throws {
        try await TestFileSystem.withTemporaryDirectory { directory in
            let suite = "Me2PressTests-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let settings = AppSettings(defaults: defaults)
            settings.maxConcurrency = 2
            let sources = try ["JPG", "PNG", "Automatic"].map {
                try TestFileSystem.writeText("第一章 测试\n正文。", named: "\($0).txt", in: directory)
            }
            let jpg = try TestFileSystem.writeImage(named: "cover.jpg", in: directory)
            let png = try TestFileSystem.writeImage(named: "cover.png", in: directory)
            let model = TextBookViewModel()
            model.outputFormat = .epub
            _ = await model.add(sources)
            model.setCover(jpg, for: sources[0])
            model.setCover(png, for: sources[1])
            model.startConversion(appSettings: settings, logger: LogManager())
            try await waitWhile { model.isConverting }
            #expect(model.progress.isCompleted)
            #expect(model.progress.succeededCount == 3)
            for (source, cover) in zip(sources, [jpg, png]) {
                let output = source.deletingPathExtension().appendingPathExtension("epub")
                let entry = "OEBPS/Images/cover.\(cover.pathExtension)"
                #expect(try TestFileSystem.readZIPEntry(entry, from: output) == Data(contentsOf: cover))
            }
            let automatic = sources[2].deletingPathExtension().appendingPathExtension("epub")
            try verifyGeneratedCover(in: automatic)
        }
    }

    @Test("Failed retries preserve the original cover selection, including no custom cover",
          arguments: [true, false])
    func retryCover(hasCover: Bool) async throws {
        try await TestFileSystem.withTemporaryDirectory { directory in
            let suite = "Me2PressTests-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let settings = AppSettings(defaults: defaults)
            let failed = directory.appendingPathComponent("Failed.txt")
            let success = try TestFileSystem.writeText("正文。", named: "Success.txt", in: directory)
            let original = try TestFileSystem.writeImage(named: "original.jpg", in: directory)
            let replacement = try TestFileSystem.writeImage(named: "replacement.png", in: directory)
            let model = TextBookViewModel()
            model.outputFormat = .epub
            _ = await model.add([failed, success])
            if hasCover { model.setCover(original, for: failed) }
            let logger = LogManager()
            model.startConversion(appSettings: settings, logger: logger)
            try await waitWhile { model.isConverting }
            #expect(model.progress.succeededCount == 1)
            try #require(model.progress.failures.map(\.sourceURL) == [failed])
            try "正文。".write(to: failed, atomically: true, encoding: .utf8)
            model.setCover(replacement, for: failed)
            model.retryFailed(appSettings: settings, logger: logger)
            try await waitWhile { model.isConverting }
            let output = failed.deletingPathExtension().appendingPathExtension("epub")
            #expect(model.items == [failed])
            #expect(model.progress.isCompleted)
            #expect(model.progress.outputURLs == [output])
            if hasCover {
                #expect(try TestFileSystem.readZIPEntry("OEBPS/Images/cover.jpg", from: output) == Data(contentsOf: original))
            } else {
                try verifyGeneratedCover(in: output)
            }
        }
    }

    @Test("An unavailable selected cover fails without generating a substitute")
    func unavailableCover() async throws {
        try await TestFileSystem.withTemporaryDirectory { directory in
            let suite = "Me2PressTests-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let settings = AppSettings(defaults: defaults)
            let source = try TestFileSystem.writeText("正文。", named: "Book.txt", in: directory)
            let cover = directory.appendingPathComponent("missing.png")
            let model = TextBookViewModel()
            model.outputFormat = .epub
            _ = await model.add([source])
            model.setCover(cover, for: source)
            model.startConversion(appSettings: settings, logger: LogManager())
            try await waitWhile { model.isConverting }
            #expect(model.progress.failures.map(\.sourceURL) == [source])
            #expect(model.progress.outputURLs.isEmpty)
            #expect(model.coverURL(for: source) == cover)
            #expect(!FileManager.default.fileExists(atPath: source.deletingPathExtension().appendingPathExtension("epub").path))
        }
    }

    private func verifyGeneratedCover(in archive: URL) throws {
        let data = try TestFileSystem.readZIPEntry("OEBPS/Images/cover.jpg", from: archive)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 600)
        #expect(image.height == 800)
    }

    private func waitWhile(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(20)
        while condition(), ContinuousClock.now < deadline { await Task.yield() }
        try #require(!condition(), "Background operation did not finish")
    }
}
