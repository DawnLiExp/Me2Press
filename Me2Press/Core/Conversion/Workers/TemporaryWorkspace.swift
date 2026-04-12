//
//  TemporaryWorkspace.swift
//  Me2Press
//
//  Temporary conversion directories created next to the output folder.
//

import Foundation

struct TemporaryWorkspace {
    let rootURL: URL
    let contentURL: URL
    let uuid: String

    nonisolated static func create(nextTo outputFolder: URL) throws -> TemporaryWorkspace {
        let uuid = UUID().uuidString
        let rootURL = outputFolder.appendingPathComponent(".me2press_tmp_\(uuid)")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let contentURL = rootURL.appendingPathComponent("content")
        try FileManager.default.createDirectory(at: contentURL, withIntermediateDirectories: true)

        return TemporaryWorkspace(rootURL: rootURL, contentURL: contentURL, uuid: uuid)
    }

    nonisolated func epubURL(named name: String) -> URL {
        rootURL.appendingPathComponent("\(name).epub")
    }

    nonisolated func generatedCoverURL() -> URL {
        rootURL.appendingPathComponent("generated_cover.jpg")
    }

    nonisolated func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
