import Foundation
import Testing
@testable import Me2Press

@Suite("KindleGen diagnostics")
@MainActor
struct KindleGenRunnerTests {
    @Test("Success and warning success retain output", arguments: [0, 1])
    func successfulOutput(exitCode: Int) async throws {
        try await TestFileSystem.withTemporaryDirectory { directory in
            let epub = try TestFileSystem.writeText("EPUB", named: "漫画 book.epub", in: directory)
            let script = try TestFileSystem.writeExecutableScript("""
            printf 'MOBI' > "${4%.epub}.mobi"
            printf '警告(prcgen):W14019: 封面尺寸较小\\n'
            exit \(exitCode)
            """, in: directory)
            let result = try await KindleGenRunner(kindlegenPath: script).convert(epubPath: epub)
            #expect(try Data(contentsOf: result.outputURL) == Data("MOBI".utf8))
            #expect(result.warnings == ["警告(prcgen):W14019: 封面尺寸较小"])
        }
    }

    @Test("Warning success without a known warning code still exposes output")
    func unrecognizedWarning() async throws {
        try await TestFileSystem.withTemporaryDirectory { directory in
            let epub = try TestFileSystem.writeText("EPUB", named: "book.epub", in: directory)
            let script = try TestFileSystem.writeExecutableScript("""
            printf 'MOBI' > "${4%.epub}.mobi"
            printf 'A warning in an unfamiliar format\\n'
            exit 1
            """, in: directory)
            let result = try await KindleGenRunner(kindlegenPath: script).convert(epubPath: epub)
            #expect(result.warnings.first?.contains("unfamiliar format") == true)
        }
    }

    @Test("Concurrent failures retain complete, named diagnostic blocks", arguments: ["E23026", "E99999"])
    func failedDiagnostics(code: String) async throws {
        try await TestFileSystem.withTemporaryDirectory { directory in
            let epub = try TestFileSystem.writeText("EPUB", named: "book.epub", in: directory)
            let script = try TestFileSystem.writeExecutableScript("""
            printf 'first line\\nError(prcgen):\(code): failed\\nlast line\\n'
            exit 2
            """, in: directory)
            let logger = LogManager()
            do {
                _ = try await ConversionWorkerSupport.convertWithDiagnostics(
                    runner: KindleGenRunner(kindlegenPath: script), epubURL: epub, name: "\(code) [Vol.2]"
                ) { event in
                    if case .log(_, let message) = event {
                        await logger.log(level: .error, message)
                    }
                }
                Issue.record("Expected conversion failure")
            } catch let error as Me2PressError {
                #expect(error.kindlegenOutput == "first line\nError(prcgen):\(code): failed\nlast line\n")
            }
            #expect(logger.fullHistory.count == 1)
            #expect(logger.fullHistory.first?.message == "[\(code) [Vol.2]] kindlegen:\nfirst line\nError(prcgen):\(code): failed\nlast line\n")
        }
    }

    @Test("A successful exit without output does not report success")
    func missingOutput() async throws {
        try await TestFileSystem.withTemporaryDirectory { directory in
            let epub = try TestFileSystem.writeText("EPUB", named: "book.epub", in: directory)
            let script = try TestFileSystem.writeExecutableScript("exit 0", in: directory)
            await #expect(throws: Me2PressError.self) {
                _ = try await KindleGenRunner(kindlegenPath: script).convert(epubPath: epub)
            }
        }
    }

    @Test("Cancellation terminates the running tool and remains cancellation")
    func cancellation() async throws {
        try await TestFileSystem.withTemporaryDirectory { directory in
            let epub = try TestFileSystem.writeText("EPUB", named: "book.epub", in: directory)
            let script = try TestFileSystem.writeExecutableScript("""
            : > "$4.started"
            while :; do :; done
            """, in: directory)
            let task = Task { try await KindleGenRunner(kindlegenPath: script).convert(epubPath: epub) }
            let deadline = ContinuousClock.now + .seconds(5)
            while !FileManager.default.fileExists(atPath: epub.path + ".started"), ContinuousClock.now < deadline {
                await Task.yield()
            }
            task.cancel()
            await #expect(throws: CancellationError.self) { _ = try await task.value }
        }
    }
}
