//
//  ConversionJob.swift
//  Me2Press
//
//  Immutable, Sendable snapshots used by background conversion workers.
//

import Foundation

struct TextConversionJob: Sendable {
    let sourceURL: URL
    let outputFormat: OutputFormat
    let indentParagraph: Bool
    let keepLineBreaks: Bool
    let coverImageURL: URL?
    let chapterPatterns: [ChapterPattern]
    let authorName: String
    let kindlegenURL: URL?
}

struct EPUBConversionJob: Sendable {
    let sourceURL: URL
    let kindlegenURL: URL
}

struct ComicConversionJob: Sendable {
    let sourceFolderURL: URL
    let authorName: String
    let kindlegenURL: URL
}

enum ConversionJob: Sendable {
    case text(TextConversionJob)
    case epub(EPUBConversionJob)
    case comic(ComicConversionJob)

    nonisolated var displayName: String {
        switch self {
        case .text(let job):
            job.sourceURL.deletingPathExtension().lastPathComponent
        case .epub(let job):
            job.sourceURL.deletingPathExtension().lastPathComponent
        case .comic(let job):
            job.sourceFolderURL.lastPathComponent
        }
    }
}
