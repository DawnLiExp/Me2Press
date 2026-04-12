//
//  KindleGenProbeService.swift
//  Me2Press
//
//  Probes kindlegen readiness without blocking cooperative executor threads.
//

import Foundation

struct KindleGenProbeResult: Sendable, Equatable {
    let isReady: Bool
    let version: String

    nonisolated static let unavailable = KindleGenProbeResult(isReady: false, version: "")
}

actor KindleGenProbeService {
    func probe(executableURL: URL) async -> KindleGenProbeResult {
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            return .unavailable
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
            _ = try await runProcess(process, timeout: .seconds(5))
            output = await outputTask.value
        } catch {
            try? pipe.fileHandleForWriting.close()
            _ = await outputTask.value
            return .unavailable
        }

        let version = output
            .components(separatedBy: .newlines)
            .first(where: { $0.contains("Amazon kindlegen") }) ?? ""

        if version.isEmpty {
            return .unavailable
        }

        return KindleGenProbeResult(isReady: true, version: version)
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
