import Foundation
import Testing
@testable import Me2Press

@Suite("Conversion results")
@MainActor
struct ConversionResultTests {
    @Test("A failed batch never reports success", arguments: [1, 2])
    func failedBatch(concurrency: Int) async throws {
        let progress = ConversionProgress()
        let presenter = ConversionEventPresenter(progress: progress, logger: LogManager(), simulator: ConversionProgressSimulator())
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        let job = TextConversionJob(sourceURL: missing, outputFormat: .epub, indentParagraph: true,
                                    keepLineBreaks: false, coverImageURL: nil, chapterPatterns: [],
                                    authorName: "Test", kindlegenURL: nil)
        await ConversionCoordinator().runBatch(jobs: [.text(job)], maxConcurrency: concurrency) { event in
            await presenter.handle(event)
        }
        #expect(progress.outcome == .failure)
        #expect(!progress.isCompleted)
        #expect(progress.failures.map(\.sourceURL) == [missing])
        #expect(progress.succeededCount == 0)
    }

    @Test("Real EPUB output is retained alongside a failed item", arguments: [1, 2])
    func realMixedBatch(concurrency: Int) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("valid.txt")
        try "第一章 测试\n这是正文。".write(to: source, atomically: true, encoding: .utf8)
        let missing = directory.appendingPathComponent("missing.txt")
        let jobs = [source, missing].map {
            ConversionJob.text(TextConversionJob(sourceURL: $0, outputFormat: .epub,
                indentParagraph: true, keepLineBreaks: false, coverImageURL: nil,
                chapterPatterns: [], authorName: "Test", kindlegenURL: nil))
        }
        let progress = ConversionProgress()
        let presenter = ConversionEventPresenter(progress: progress, logger: LogManager(), simulator: ConversionProgressSimulator())
        await ConversionCoordinator().runBatch(jobs: jobs, maxConcurrency: concurrency) { event in
            await presenter.handle(event)
        }
        #expect(progress.outcome == .failure)
        #expect(progress.succeededCount == 1)
        #expect(progress.failures.map(\.sourceURL) == [missing])
        let output = try #require(progress.outputURLs.first)
        #expect(output.lastPathComponent == "valid.epub")
        #expect(try Data(contentsOf: output).starts(with: [0x50, 0x4B]))
    }

    @Test("Mixed results retain exact failed sources and successful outputs")
    func mixedResults() {
        let progress = ConversionProgress()
        let presenter = ConversionEventPresenter(progress: progress, logger: LogManager(), simulator: ConversionProgressSimulator())
        let failed = URL(fileURLWithPath: "/fixtures/failed.txt")
        let output = URL(fileURLWithPath: "/fixtures/success.epub")
        presenter.handle(.batchStarted(totalFiles: 2, isConcurrent: true))
        presenter.handle(.outputCreated(output))
        presenter.handle(.itemSucceeded)
        presenter.handle(.itemCompleted(name: "success"))
        presenter.handle(.itemFailed(sourceURL: failed, name: "failed", errorDescription: "Unreadable", recoverySuggestion: "Choose another file"))
        presenter.handle(.itemCompleted(name: "failed"))
        presenter.handle(.batchCompleted(totalFiles: 2, elapsed: "1s"))
        #expect(progress.outcome == .failure)
        #expect(progress.succeededCount == 1)
        #expect(progress.completedCount == 2)
        #expect(progress.outputURLs == [output])
        #expect(progress.failures.first?.message.contains("Choose another file") == true)
        progress.reset()
        #expect(!progress.isFinished)
        #expect(progress.outputURLs.isEmpty && progress.failures.isEmpty)
    }

    @Test("Cancellation retains completed work without claiming full success")
    func cancelledResults() {
        let progress = ConversionProgress()
        let presenter = ConversionEventPresenter(progress: progress, logger: LogManager(), simulator: ConversionProgressSimulator())
        presenter.handle(.batchStarted(totalFiles: 3, isConcurrent: true))
        presenter.handle(.itemSucceeded)
        presenter.handle(.batchCancelled)
        #expect(progress.outcome == .cancelled)
        #expect(progress.succeededCount == 1)
        #expect(progress.unprocessedCount == 2)
    }

    @Test("Successful batch reports success only after all items succeed")
    func successfulResults() {
        let progress = ConversionProgress()
        let presenter = ConversionEventPresenter(progress: progress, logger: LogManager(), simulator: ConversionProgressSimulator())
        presenter.handle(.batchStarted(totalFiles: 1, isConcurrent: false))
        presenter.handle(.itemSucceeded)
        presenter.handle(.batchCompleted(totalFiles: 1, elapsed: "1s"))
        #expect(progress.isCompleted)
        #expect(progress.value == 1)
    }
}
