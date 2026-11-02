//
//  TestFileSystem.swift
//  Me2PressTests
//
//  Temporary filesystem helpers for unit tests.
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum TestFileSystem {
    static func readZIPEntry(_ entry: String, from archive: URL) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", archive.path, entry]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileReadCorruptFile) }
        return data
    }

    static func writeImage(named name: String, width: Int = 32, height: Int = 48, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CocoaError(.fileWriteUnknown)
        }
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let type = name.lowercased().hasSuffix(".png") ? UTType.png : UTType.jpeg
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return url
    }

    static func writeExecutableScript(_ body: String, in directory: URL) throws -> URL {
        let url = try writeText("#!/bin/sh\nset -eu\n" + body + "\n", named: "tool-\(UUID().uuidString)", in: directory)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

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
