//
//  TestFileSystem.swift
//  Me2PressTests
//
//  Temporary filesystem helpers for unit tests.
//

import Foundation

enum TestFileSystem {
    static func withTemporaryDirectory<T>(
        _ body: (URL) throws -> T
    ) throws -> T {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Me2PressTests-\(UUID().uuidString)", isDirectory: true)

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        return try body(directoryURL)
    }

    static func withTemporaryDirectory<T>(
        _ body: (URL) async throws -> T
    ) async throws -> T {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Me2PressTests-\(UUID().uuidString)", isDirectory: true)

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        return try await body(directoryURL)
    }

    @discardableResult
    static func writeText(
        _ text: String,
        named name: String,
        in directory: URL,
        encoding: String.Encoding = .utf8
    ) throws -> URL {
        let fileURL = directory.appendingPathComponent(name)
        try text.write(to: fileURL, atomically: true, encoding: encoding)
        return fileURL
    }

    @discardableResult
    static func createDirectory(
        named name: String,
        in directory: URL
    ) throws -> URL {
        let folderURL = directory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        return folderURL
    }

    @discardableResult
    static func writeDataFile(
        named name: String,
        size: Int,
        in directory: URL
    ) throws -> URL {
        let fileURL = directory.appendingPathComponent(name)
        let data = Data(repeating: 0xA5, count: size)
        try data.write(to: fileURL)
        return fileURL
    }
}
