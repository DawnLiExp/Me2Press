//
//  EPUBKindleNormalizer.swift
//  Me2Press
//
//  Normalizes third-party EPUB XHTML before kindlegen parses it.
//

import Foundation

enum EPUBKindleNormalizer {
    private nonisolated static let utf8XMLDeclaration = Data("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n".utf8)
    private nonisolated static let utf8BOM = Data([0xEF, 0xBB, 0xBF])

    nonisolated static func normalizeIfNeeded(
        epubURL: URL,
        workspace: TemporaryWorkspace
    ) async throws -> URL {
        let unpackedURL = workspace.rootURL.appendingPathComponent("epub-normalized", isDirectory: true)
        try FileManager.default.createDirectory(at: unpackedURL, withIntermediateDirectories: true)

        try await unzip(epubURL: epubURL, to: unpackedURL)
        try Task.checkCancellation()

        let changedCount = try normalizeHTMLFiles(in: unpackedURL)
        guard changedCount > 0 else {
            return epubURL
        }

        let normalizedURL = workspace.epubURL(named: epubURL.deletingPathExtension().lastPathComponent)
        try await ZIPWriter.pack(directoryURL: unpackedURL, to: normalizedURL)
        return normalizedURL
    }

    nonisolated static func dataByAddingUTF8DeclarationIfNeeded(_ data: Data) -> Data? {
        let inspectLength = min(data.count, 1024)
        let inspected = String(decoding: data.prefix(inspectLength), as: UTF8.self).lowercased()
        if inspected.contains("charset=") || inspected.contains("encoding=") {
            return nil
        }
        guard String(data: data, encoding: .utf8) != nil else {
            return nil
        }

        if data.starts(with: utf8BOM) {
            var normalized = utf8BOM
            normalized.append(utf8XMLDeclaration)
            normalized.append(data.dropFirst(utf8BOM.count))
            return normalized
        }

        var normalized = utf8XMLDeclaration
        normalized.append(data)
        return normalized
    }

    // MARK: - Private

    private nonisolated static func normalizeHTMLFiles(in rootURL: URL) throws -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var changedCount = 0
        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true, isHTMLFile(fileURL) else {
                continue
            }

            let data = try Data(contentsOf: fileURL)
            guard let normalized = dataByAddingUTF8DeclarationIfNeeded(data) else {
                continue
            }

            try normalized.write(to: fileURL, options: .atomic)
            changedCount += 1
        }

        return changedCount
    }

    private nonisolated static func isHTMLFile(_ url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "html", "xhtml":
            true
        default:
            false
        }
    }

    private nonisolated static func unzip(epubURL: URL, to outputURL: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", epubURL.path, "-d", outputURL.path]
        try await runProcess(process)

        guard process.terminationStatus == 0 else {
            throw Me2PressError.zipFailed(exitCode: process.terminationStatus)
        }
    }

    private nonisolated static func runProcess(_ process: Process) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { _ in
                    continuation.resume()
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
        try Task.checkCancellation()
    }
}
