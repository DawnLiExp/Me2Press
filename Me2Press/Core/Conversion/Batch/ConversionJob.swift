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
    let parallelConversions: Int
    let readingDirection: ComicReadingDirection
    let coverImageURL: URL?
    let outputDirectoryURL: URL?

    nonisolated init(sourceFolderURL: URL, authorName: String, kindlegenURL: URL,
                     parallelConversions: Int = 1, readingDirection: ComicReadingDirection = .rightToLeft,
                     coverImageURL: URL? = nil, outputDirectoryURL: URL? = nil) {
        self.sourceFolderURL = sourceFolderURL
        self.authorName = authorName
        self.kindlegenURL = kindlegenURL
        self.parallelConversions = parallelConversions
        self.readingDirection = readingDirection
        self.coverImageURL = coverImageURL
        self.outputDirectoryURL = outputDirectoryURL
    }

}

enum ConversionJob: Sendable {
    case text(TextConversionJob)
    case epub(EPUBConversionJob)
    case comic(ComicConversionJob)

    nonisolated var sourceURL: URL {
        switch self {
        case .text(let job): job.sourceURL
        case .epub(let job): job.sourceURL
        case .comic(let job): job.sourceFolderURL
        }
    }

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
