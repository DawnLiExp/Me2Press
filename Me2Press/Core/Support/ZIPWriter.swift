//
//  ZIPWriter.swift
//  Me2Press
//
//  Uses 7z (if installed) or system zip to package EPUB, preserving KCC's 7zip hack.
//  Supports cooperative Task cancellation via withTaskCancellationHandler.
//

import Foundation

enum ZIPWriter {
    static func pack(directoryURL: URL, to outputURL: URL) async throws {
        try Task.checkCancellation()

        // Find 7zz
        var sevenZipURL: URL?
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/7zz") {
            sevenZipURL = URL(fileURLWithPath: "/opt/homebrew/bin/7zz")
        } else if FileManager.default.fileExists(atPath: "/usr/local/bin/7zz") {
            sevenZipURL = URL(fileURLWithPath: "/usr/local/bin/7zz")
        }

        let resolvedDirectoryURL = directoryURL.resolvingSymlinksInPath()
        try? FileManager.default.removeItem(at: outputURL)

        if let executableURL = sevenZipURL {
            // KCC's "crazy hack to ensure mimetype is first when using 7zip"
            let mimetypeURL = resolvedDirectoryURL.appendingPathComponent("mimetype")
            let hackMimetypeURL = resolvedDirectoryURL.appendingPathComponent("!mimetype")
            if FileManager.default.fileExists(atPath: mimetypeURL.path) {
                try? FileManager.default.moveItem(at: mimetypeURL, to: hackMimetypeURL)
            }

            // 7zz a -tzip -mx=0 output.zip *
            let aProcess = Process()
            aProcess.executableURL = executableURL
            aProcess.currentDirectoryURL = resolvedDirectoryURL
            aProcess.arguments = ["a", "-tzip", "-mx=0", outputURL.path, "*"]
            try await runProcess(aProcess)

            guard aProcess.terminationStatus == 0 else {
                throw Me2PressError.zipFailed(exitCode: aProcess.terminationStatus)
            }

            try Task.checkCancellation()

            // 7zz rn output.zip !mimetype mimetype
            let rnProcess = Process()
            rnProcess.executableURL = executableURL
            rnProcess.currentDirectoryURL = resolvedDirectoryURL
            rnProcess.arguments = ["rn", outputURL.path, "!mimetype", "mimetype"]
            try await runProcess(rnProcess)

            guard rnProcess.terminationStatus == 0 else {
                throw Me2PressError.zipRenameFailed(exitCode: rnProcess.terminationStatus)
            }

            // Restore mimetype locally
            if FileManager.default.fileExists(atPath: hackMimetypeURL.path) {
                try? FileManager.default.moveItem(at: hackMimetypeURL, to: mimetypeURL)
            }

        } else {
            // Fallback to macOS built-in zip
            // 1. zip -X -q -0 output.zip mimetype
            let mimeProcess = Process()
            mimeProcess.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            mimeProcess.currentDirectoryURL = resolvedDirectoryURL
            mimeProcess.arguments = ["-X", "-q", "-0", outputURL.path, "mimetype"]
            try await runProcess(mimeProcess)

            try Task.checkCancellation()

            // 2. zip -X -q -r -0 output.zip META-INF OEBPS
            let restProcess = Process()
            restProcess.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            restProcess.currentDirectoryURL = resolvedDirectoryURL
            restProcess.arguments = ["-X", "-q", "-r", "-0", outputURL.path, "META-INF", "OEBPS"]
            try await runProcess(restProcess)

            guard restProcess.terminationStatus == 0 else {
                throw Me2PressError.zipFailed(exitCode: restProcess.terminationStatus)
            }
        }
    }

    // MARK: - Private

    /// Runs a process to completion, sending SIGTERM on Task cancellation.
    private static func runProcess(_ process: Process) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                process.terminationHandler = { _ in cont.resume(returning: ()) }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    cont.resume(throwing: error)
                }
            }
        } onCancel: {
            process.terminate()
        }
        // IMPORTANT: terminate() triggers terminationHandler before CancellationError propagates;
        // checking here ensures the caller sees cancellation rather than a successful exit code.
        try Task.checkCancellation()
    }
}
