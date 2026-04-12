//
//  KindleGenRunner.swift
//  Me2Press
//
//  Asynchronously runs kindlegen CLI tool.
//  Supports cooperative Task cancellation: cancelling the task sends SIGTERM to kindlegen.
//

import Foundation
import OSLog

actor KindleGenRunner {
    let kindlegenPath: URL

    init(kindlegenPath: URL) {
        self.kindlegenPath = kindlegenPath
    }

    func convert(epubPath: URL) async throws -> URL {
        // 629_145_600 = 600 MB — mirrors the threshold KCC uses for the same kindlegen restriction.
        let epubSize = (try? FileManager.default.attributesOfItem(atPath: epubPath.path)[.size] as? Int) ?? 0
        if epubSize >= 629_145_600 {
            throw Me2PressError.epubTooLarge
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

        try process.run()

        // Read output and wait for exit; terminate the process on Task cancellation.
        // Pipe read errors are suppressed — they occur when the process is terminated externally.
        var outputStr = ""
        await withTaskCancellationHandler {
            do {
                for try await line in pipe.fileHandleForReading.bytes.lines {
                    outputStr += line + "\n"
                }
            } catch {
                // pipe closed (process ended or was terminated) — ignore read errors
            }
            process.waitUntilExit()
        } onCancel: {
            process.terminate()
        }

        // Propagate cancellation immediately; do not act on kindlegen output after termination.
        try Task.checkCancellation()

        let exitCode = process.terminationStatus

        // IMPORTANT: kindlegen exit code semantics differ from Unix conventions.
        // 0 = success, 1 = converted with warnings (output file is still valid), 2 = fatal error.
        // Treat exit code 1 as success to avoid discarding valid output.
        if exitCode == 0 {
            return targetMobiPath
        }
        if exitCode == 1 {
            let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Me2Press", category: "KindleGenRunner")
            logger.warning("Built with warnings (exit code 1)")
            return targetMobiPath
        }
        // E23026 is kindlegen's own "source file too large" error; surface it as the typed case
        // rather than a generic kindlegenFailed so the UI can show a targeted recovery message.
        if outputStr.contains("E23026") {
            throw Me2PressError.epubTooLarge
        }

        throw Me2PressError.kindlegenFailed(exitCode: exitCode, output: outputStr)
    }
}
