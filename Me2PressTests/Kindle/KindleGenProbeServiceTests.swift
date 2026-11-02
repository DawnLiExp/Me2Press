import Foundation
import Testing
@testable import Me2Press

@Suite("KindleGen readiness")
@MainActor
struct KindleGenProbeServiceTests {
    @Test("Missing and non-executable files have different explanations")
    func fileFailures() async throws {
        try await TestFileSystem.withTemporaryDirectory { directory in
            let service = KindleGenProbeService()
            let missing = await service.probe(executableURL: directory.appendingPathComponent("missing"))
            #expect(missing.failure == .missing)
            let file = try TestFileSystem.writeText("not executable", named: "tool", in: directory)
            let denied = await service.probe(executableURL: file)
            #expect(denied.failure == .notExecutable)
        }
    }

    @Test("Launch errors, wrong programs and valid kindlegen are distinguishable")
    func programFailures() async throws {
        try await TestFileSystem.withTemporaryDirectory { directory in
            let service = KindleGenProbeService()
            let broken = try TestFileSystem.writeExecutableScript("exit 0", in: directory)
            try "#!/missing/interpreter\n".write(to: broken, atomically: true, encoding: .utf8)
            let failed = await service.probe(executableURL: broken)
            guard case .launchFailed(let reason) = failed.failure else {
                Issue.record("Expected launch error, got \(String(describing: failed.failure))")
                return
            }
            #expect(!reason.isEmpty)
            let wrong = try TestFileSystem.writeExecutableScript("printf 'unrelated program\\n'", in: directory)
            #expect(await service.probe(executableURL: wrong).failure == .unrecognizedVersion)
            let valid = try TestFileSystem.writeExecutableScript("printf 'Amazon kindlegen V2.9\\n'", in: directory)
            let result = await service.probe(executableURL: valid)
            #expect(result.isReady && result.version == "Amazon kindlegen V2.9")
        }
    }

    @Test("A hanging executable times out and is terminated")
    func timeout() async throws {
        try await TestFileSystem.withTemporaryDirectory { directory in
            let script = try TestFileSystem.writeExecutableScript("while :; do :; done", in: directory)
            let result = await KindleGenProbeService().probe(executableURL: script, timeout: .milliseconds(100))
            #expect(result.failure == .timedOut)
        }
    }

    @Test("A late old probe cannot replace a newly selected executable")
    func staleProbe() async throws {
        try await TestFileSystem.withTemporaryDirectory { directory in
            let suite = "Me2PressTests-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let settings = AppSettings(defaults: defaults)
            defer { settings.updateKindleGenURL(nil) }
            let old = try TestFileSystem.writeExecutableScript(": > \"$0.started\"\nwhile :; do :; done", in: directory)
            let current = try TestFileSystem.writeExecutableScript("printf 'Amazon kindlegen CURRENT\\n'", in: directory)
            settings.updateKindleGenURL(old)
            let startedDeadline = ContinuousClock.now + .seconds(5)
            while !FileManager.default.fileExists(atPath: old.path + ".started"), ContinuousClock.now < startedDeadline {
                await Task.yield()
            }
            try #require(FileManager.default.fileExists(atPath: old.path + ".started"))
            settings.updateKindleGenURL(current)
            let deadline = ContinuousClock.now + .seconds(5)
            while settings.kindleGenStatus == .checking, ContinuousClock.now < deadline { await Task.yield() }
            #expect(settings.isKindleGenReady)
            #expect(settings.kindlegenVersion == "Amazon kindlegen CURRENT")
            #expect(settings.kindleGenFailure == nil)
        }
    }
}
