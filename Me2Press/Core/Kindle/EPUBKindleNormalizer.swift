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
    private nonisolated static let bodyIDPattern = try! NSRegularExpression(
        pattern: #"(?is)<!--.*?-->|<!\[CDATA\[.*?\]\]>|<body(?=\s)(?:[^<>"']|"[^"]*"|'[^']*')*?\s+id\s*=\s*("[^"]+"|'[^']+')(?:[^<>"']|"[^"]*"|'[^']*')*(?<!/)>"#
    )

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

    private nonisolated static func dataByAddingBodyAnchorIfNeeded(_ data: Data) -> Data? {
        guard var html = String(validating: data, as: UTF8.self) else { return nil }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var bodyMatch: NSTextCheckingResult?
        bodyIDPattern.enumerateMatches(in: html, range: range) { match, _, stop in
            // Comments and CDATA are consumed without capturing an ID.
            guard let match, match.range(at: 1).location != NSNotFound else { return }
            bodyMatch = match
            stop.pointee = true
        }
        guard let bodyMatch,
              let tag = Range(bodyMatch.range, in: html),
              let quotedID = Range(bodyMatch.range(at: 1), in: html) else { return nil }

        // KindleGen ignores body IDs as link targets but accepts named anchors.
        // Retain the body ID so styles can still refer to it.
        let anchor = "<a name=\(html[quotedID])></a>"
        guard !html[tag.upperBound...].hasPrefix(anchor) else { return nil }
        html.insert(contentsOf: anchor, at: tag.upperBound)
        return Data(html.utf8)
    }

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
            let declared = dataByAddingUTF8DeclarationIfNeeded(data)
            guard let normalized = dataByAddingBodyAnchorIfNeeded(declared ?? data) ?? declared else {
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
