//
//  KindleGenProbeService.swift
//  Me2Press
//
//  Probes kindlegen readiness without blocking cooperative executor threads.
//

import Foundation

struct KindleGenProbeResult: Sendable, Equatable {
    let version: String
    let failure: KindleGenProbeFailure?

    var isReady: Bool { failure == nil }
}

enum KindleGenProbeFailure: Sendable, Equatable {
    case missing
    case notExecutable
    case launchFailed(String)
    case timedOut
    case unrecognizedVersion
    case cancelled

    var description: String {
        switch self {
        case .missing: String(localized: "kindlegen.failure.missing")
        case .notExecutable: String(localized: "kindlegen.failure.not_executable")
        case .launchFailed(let reason): String(localized: "kindlegen.failure.launch \(reason)")
        case .timedOut: String(localized: "kindlegen.failure.timeout")
        case .unrecognizedVersion: String(localized: "kindlegen.failure.version")
        case .cancelled: String(localized: "log.cancelled")
        }
    }

    var recoverySuggestion: String {
        switch self {
        case .missing, .notExecutable, .unrecognizedVersion:
            String(localized: "kindlegen.recovery.select")
        case .launchFailed:
            String(localized: "kindlegen.recovery.launch")
        case .timedOut:
            String(localized: "kindlegen.recovery.timeout")
        case .cancelled:
            ""
        }
    }
}

actor KindleGenProbeService {
    func probe(executableURL: URL, timeout: Duration = .seconds(5)) async -> KindleGenProbeResult {
        if Task.isCancelled {
            return KindleGenProbeResult(version: "", failure: .cancelled)
        }
        guard FileManager.default.fileExists(atPath: executableURL.path) else {
            return KindleGenProbeResult(version: "", failure: .missing)
        }
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            return KindleGenProbeResult(version: "", failure: .notExecutable)
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["-locale", "en"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let outputTask = Task { [fileHandle = pipe.fileHandleForReading] in
            await Self.collectOutput(from: fileHandle)
        }

        let output: String
        do {
            _ = try await runProcess(process, timeout: timeout)
            try? pipe.fileHandleForWriting.close()
            output = await outputTask.value
        } catch ProbeError.timedOut {
            try? pipe.fileHandleForWriting.close()
            _ = await outputTask.value
            return KindleGenProbeResult(version: "", failure: .timedOut)
        } catch is CancellationError {
            try? pipe.fileHandleForWriting.close()
            _ = await outputTask.value
            return KindleGenProbeResult(version: "", failure: .cancelled)
        } catch {
            try? pipe.fileHandleForWriting.close()
            _ = await outputTask.value
            return KindleGenProbeResult(version: "", failure: .launchFailed(error.localizedDescription))
        }

        let version = output
            .components(separatedBy: .newlines)
            .first(where: { $0.contains("Amazon kindlegen") }) ?? ""

        if version.isEmpty {
            return KindleGenProbeResult(version: "", failure: .unrecognizedVersion)
        }

        return KindleGenProbeResult(version: version, failure: nil)
    }

    // MARK: - Private

    /// Runs a probe process with a hard timeout and cooperative cancellation.
    private func runProcess(_ process: Process, timeout: Duration) async throws -> Int32 {
        let timeoutState = ProbeTimeoutState()
        let timeoutTask = Task {
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, process.isRunning else { return }
            await timeoutState.markTimedOut()
            process.terminate()
        }

        defer {
            timeoutTask.cancel()
            process.terminationHandler = nil
        }

        let exitCode = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
                process.terminationHandler = { terminatedProcess in
                    continuation.resume(returning: terminatedProcess.terminationStatus)
                }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            timeoutTask.cancel()
            if process.isRunning {
                process.terminate()
            }
        }

        if await timeoutState.didTimeOut {
            throw ProbeError.timedOut
        }

        try Task.checkCancellation()
        return exitCode
    }

    /// Reads probe output to completion. Read errors are expected during forced termination.
    private nonisolated static func collectOutput(from fileHandle: FileHandle) async -> String {
        var output = ""

        do {
            for try await line in fileHandle.bytes.lines {
                if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    output += line + "\n"
                }
            }
        } catch {
            // pipe closed (process ended or was terminated) — ignore read errors
        }

        return output
    }
}

private enum ProbeError: Error {
    case timedOut
}

private actor ProbeTimeoutState {
    private(set) var didTimeOut = false

    func markTimedOut() {
        didTimeOut = true
    }
}
