//
//  KindleGenRunner.swift
//  Me2Press
//
//  Asynchronously runs kindlegen CLI tool.
//  Supports cooperative Task cancellation: cancelling the task sends SIGTERM to kindlegen.
//

import Foundation

struct KindleGenConversionResult: Sendable {
    let outputURL: URL
    let warnings: [String]
}

actor KindleGenRunner {
    let kindlegenPath: URL

    init(kindlegenPath: URL) {
        self.kindlegenPath = kindlegenPath
    }

    func convert(epubPath: URL) async throws -> KindleGenConversionResult {
        try Task.checkCancellation()
        // 629_145_600 = 600 MB — mirrors the threshold KCC uses for the same kindlegen restriction.
        let epubSize = (try? FileManager.default.attributesOfItem(atPath: epubPath.path)[.size] as? Int) ?? 0
        if epubSize >= 629_145_600 {
            throw Me2PressError.epubTooLarge(output: "")
        }

        let targetMobiPath = epubPath.deletingPathExtension().appendingPathExtension("mobi")
        // Remove existing to avoid kindlegen prompt
        try? FileManager.default.removeItem(at: targetMobiPath)

        let process = Process()
        process.executableURL = kindlegenPath
        process.arguments = ["-dont_append_source", "-locale", "zh", epubPath.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let outputTask = Task { [fileHandle = pipe.fileHandleForReading] in
            await Self.collectOutput(from: fileHandle)
        }

        let exitCode: Int32
        do {
            exitCode = try await runProcess(process)
        } catch {
            try? pipe.fileHandleForWriting.close()
            _ = await outputTask.value
            throw error
        }

        try? pipe.fileHandleForWriting.close()
        let outputStr = await outputTask.value

        // Propagate cancellation immediately; do not act on kindlegen output after termination.
        try Task.checkCancellation()

        // IMPORTANT: kindlegen exit code semantics differ from Unix conventions.
        // 0 = success, 1 = converted with warnings (output file is still valid), 2 = fatal error.
        // Treat exit code 1 as success to avoid discarding valid output.
        if exitCode == 0 || exitCode == 1 {
            guard FileManager.default.fileExists(atPath: targetMobiPath.path) else {
                throw Me2PressError.kindlegenFailed(
                    exitCode: exitCode,
                    output: outputStr + "\n" + String(localized: "error.kindlegen_no_output")
                )
            }
            var warnings = outputStr.components(separatedBy: .newlines).filter {
                $0.range(of: #"\bW\d{5}\b"#, options: .regularExpression) != nil
            }
            if exitCode == 1, warnings.isEmpty {
                warnings = [outputStr.isEmpty ? String(localized: "warning.kindlegen") : outputStr]
            }
            return KindleGenConversionResult(outputURL: targetMobiPath, warnings: warnings)
        }
        // E23026 is kindlegen's own "source file too large" error; surface it as the typed case
        // rather than a generic kindlegenFailed so the UI can show a targeted recovery message.
        if outputStr.contains("E23026") {
            throw Me2PressError.epubTooLarge(output: outputStr)
        }

        throw Me2PressError.kindlegenFailed(exitCode: exitCode, output: outputStr)
    }

    // MARK: - Private

    /// Runs kindlegen without blocking a cooperative executor thread.
    /// Cancellation sends SIGTERM and still waits for termination before returning.
    private func runProcess(_ process: Process) async throws -> Int32 {
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
            if process.isRunning {
                process.terminate()
            }
        }

        process.terminationHandler = nil
        return exitCode
    }

    /// Reads kindlegen output to completion. Read errors are expected during forced termination.
    private nonisolated static func collectOutput(from fileHandle: FileHandle) async -> String {
        var output = ""

        do {
            for try await line in fileHandle.bytes.lines {
                output += line + "\n"
            }
        } catch {
            // pipe closed (process ended or was terminated) — ignore read errors
        }

        return output
    }
}
