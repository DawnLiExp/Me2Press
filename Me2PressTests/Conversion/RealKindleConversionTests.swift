import Foundation
import Testing
@testable import Me2Press

private let realKindlegenURL = URL(fileURLWithPath:
    ProcessInfo.processInfo.environment["ME2PRESS_TEST_KINDLEGEN"]
    ?? "/Applications/Kindle Previewer 3.app/Contents/lib/fc/bin/kindlegen")

@Suite("Real KindleGen pipelines", .serialized,
       .enabled(if: FileManager.default.isExecutableFile(atPath: realKindlegenURL.path)))
struct RealKindleConversionTests {
    @Test("Comic CLI jobs use their output directory and keep failures scoped to the source")
    func explicitComicOutput() async throws {
        try await TestFileSystem.withTemporaryDirectory { directory in
            let source = try TestFileSystem.createDirectory(named: "Comic", in: directory)
            let output = directory.appendingPathComponent("output")
            _ = try TestFileSystem.writeImage(named: "001.jpg", width: 1236, height: 1648, in: source)
            let good = ComicConversionJob(sourceFolderURL: source, authorName: "Author",
                                          kindlegenURL: realKindlegenURL, outputDirectoryURL: output)
            let missing = directory.appendingPathComponent("missing")
            let bad = ComicConversionJob(sourceFolderURL: missing, authorName: "Author",
                                         kindlegenURL: realKindlegenURL, outputDirectoryURL: output)
            let events = ScopedConversionEvents()
            await ConversionCoordinator().runBatch(
                jobs: [.comic(good), .comic(bad)], maxConcurrency: 2,
                jobEventSink: { source, event in await events.record(source, event) },
                eventSink: { _ in }
            )
            try verifyMOBI(output.appendingPathComponent("Comic.mobi"))
            #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("Comic.mobi").path))
            let results = await events.snapshot()
            #expect(results.succeeded == [source])
            #expect(results.failed == [missing])
        }
    }

    @Test("TXT to AZW3 and existing EPUB to AZW3 use the real tool")
    func textAndEPUB() async throws {
        try await TestFileSystem.withTemporaryDirectory { directory in
            let source = try TestFileSystem.writeText("第一章 测试\n这是正文。\n第二章 验证\n这是第二章。", named: "小说.txt", in: directory)
            let job = TextConversionJob(sourceURL: source, outputFormat: .azw3, indentParagraph: true,
                                        keepLineBreaks: false, coverImageURL: nil, chapterPatterns: [],
                                        authorName: "测试作者", kindlegenURL: realKindlegenURL)
            try await TextConversionWorker.run(job: job) { _ in }
            try verifyMOBI(source.deletingPathExtension().appendingPathExtension("azw3"))
            let epubJob = TextConversionJob(sourceURL: source, outputFormat: .epub, indentParagraph: true,
                                            keepLineBreaks: false, coverImageURL: nil, chapterPatterns: [],
                                            authorName: "测试作者", kindlegenURL: nil)
            try await TextConversionWorker.run(job: epubJob) { _ in }
            let epub = source.deletingPathExtension().appendingPathExtension("epub")
            try await EPUBConversionWorker.run(job: EPUBConversionJob(sourceURL: epub, kindlegenURL: realKindlegenURL)) { _ in }
            try verifyMOBI(source.deletingPathExtension().appendingPathExtension("azw3"))
            #expect(FileManager.default.fileExists(atPath: epub.path))
        }
    }

    @Test("Real TXT to AZW3 conversion accepts JPG and PNG covers", arguments: ["jpg", "png"])
    func textCustomCover(ext: String) async throws {
        try await TestFileSystem.withTemporaryDirectory { directory in
            let source = try TestFileSystem.writeText("第一章 测试\n这是正文。", named: "小说.txt", in: directory)
            let cover = try TestFileSystem.writeImage(named: "cover.\(ext)", width: 1236, height: 1648, in: directory)
            let job = TextConversionJob(sourceURL: source, outputFormat: .azw3, indentParagraph: true,
                                        keepLineBreaks: false, coverImageURL: cover, chapterPatterns: [],
                                        authorName: "测试作者", kindlegenURL: realKindlegenURL)
            try await TextConversionWorker.run(job: job) { _ in }
            try verifyMOBI(source.deletingPathExtension().appendingPathExtension("azw3"))
        }
    }

    @Test("Real comic worker packages its selected cover")
    func singleComic() async throws {
        try await TestFileSystem.withTemporaryDirectory { directory in
            let source = try TestFileSystem.createDirectory(named: "漫画", in: directory)
            _ = try TestFileSystem.writeImage(named: "001.jpg", width: 1236, height: 1648, in: source)
            let cover = try TestFileSystem.writeImage(named: "cover.png", width: 1236, height: 1648, in: directory)
            let job = ComicConversionJob(sourceFolderURL: source, authorName: "Author", kindlegenURL: realKindlegenURL,
                                         readingDirection: .leftToRight, coverImageURL: cover)
            try await ComicConversionWorker.run(job: job) { _ in }
            try verifyMOBI(directory.appendingPathComponent("漫画.mobi"))
        }
    }

    @Test("Every split comic volume survives real EPUB packing, KindleGen and metadata fixing",
          arguments: ComicReadingDirection.allCases)
    func splitComic(direction: ComicReadingDirection) async throws {
        try await TestFileSystem.withTemporaryDirectory { directory in
            let cover = try TestFileSystem.writeImage(named: "cover.jpg", width: 1236, height: 1648, in: directory)
            let pages = try (1...2).map { try TestFileSystem.writeImage(named: "00\($0).png", width: 1236, height: 1648, in: directory) }
            let threshold = ComicVolumeSplitter.estimateTotalSize(imageURLs: [cover, pages[0]])
            let volumes = ComicVolumeSplitter.split(imageURLs: pages, threshold: threshold, coverImageURL: cover)
            #expect(volumes.count == 2)
            for (index, images) in volumes.enumerated() {
                let root = directory.appendingPathComponent("volume\(index)")
                try await ComicEPUBBuilder.build(images: images, title: "Comic [Vol.\(index + 1)]", uuid: "test-volume-\(index)",
                                                  author: "Author", tempDir: root, readingDirection: direction)
                let epub = directory.appendingPathComponent("volume\(index).epub")
                try await ZIPWriter.pack(directoryURL: root, to: epub)
                let result = try await KindleGenRunner(kindlegenPath: realKindlegenURL).convert(epubPath: epub)
                try await DualMetaFix.fixAsync(mobiPath: result.outputURL, uuid: UUID().uuidString)
                try verifyMOBI(result.outputURL)
            }
        }
    }

    private func verifyMOBI(_ url: URL) throws {
        let data = try Data(contentsOf: url)
        #expect(data.count > 1_000)
        #expect(data.range(of: Data("BOOKMOBI".utf8)) != nil)
        #expect(data.range(of: Data("EBOK".utf8)) != nil)
    }
}

private actor ScopedConversionEvents {
    var succeeded: [URL] = []
    var failed: [URL] = []
    func record(_ source: URL, _ event: ConversionEvent) {
        switch event {
        case .itemSucceeded: succeeded.append(source)
        case .itemFailed: failed.append(source)
        default: break
        }
    }
    func snapshot() -> (succeeded: [URL], failed: [URL]) { (succeeded, failed) }
}
