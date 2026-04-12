//
//  TXTParserTests.swift
//  Me2PressTests
//
//  Regression coverage for chapter parsing and paragraph handling.
//

import Foundation
import Testing
@testable import Me2Press

@MainActor
@Suite("TXTParser")
struct TXTParserTests {
    @Test("基本章节解析")
    func parsesStandardChapters() async throws {
        try await TestFileSystem.withTemporaryDirectory { directoryURL in
            let fileURL = try TestFileSystem.writeText(
                """
                第1章 起点
                这里是正文A

                第2章 继续
                这里是正文B
                """,
                named: "sample.txt",
                in: directoryURL
            )

            let parsed = try await TXTParser().parse(
                url: fileURL,
                indentParagraph: true,
                keepLineBreaks: false,
                chapterPatterns: AppSettings.defaultChapterPatterns
            )

            #expect(parsed.title == "sample")
            #expect(parsed.chapters.count == 2)
            #expect(parsed.chapters[0].title == "第1章 起点")
            #expect(parsed.chapters[0].paragraphs == ["这里是正文A"])
            #expect(parsed.chapters[1].title == "第2章 继续")
            #expect(parsed.chapters[1].paragraphs == ["这里是正文B"])
        }
    }

    @Test("保留空行时写入单个空行标记")
    func keepsCollapsedBlankMarkersWhenRequested() async throws {
        try await TestFileSystem.withTemporaryDirectory { directoryURL in
            let fileURL = try TestFileSystem.writeText(
                """
                第1章 标题
                第一段


                第二段
                """,
                named: "blank-lines.txt",
                in: directoryURL
            )

            let parsed = try await TXTParser().parse(
                url: fileURL,
                indentParagraph: true,
                keepLineBreaks: true,
                chapterPatterns: AppSettings.defaultChapterPatterns
            )

            #expect(parsed.chapters.count == 1)
            #expect(parsed.chapters[0].paragraphs == ["第一段", "__BLANK__", "第二段"])
        }
    }

    @Test("忽略空行时不写入空行标记")
    func omitsBlankMarkersWhenKeepLineBreaksIsFalse() async throws {
        try await TestFileSystem.withTemporaryDirectory { directoryURL in
            let fileURL = try TestFileSystem.writeText(
                """
                第1章 标题
                第一段


                第二段
                """,
                named: "no-blank-markers.txt",
                in: directoryURL
            )

            let parsed = try await TXTParser().parse(
                url: fileURL,
                indentParagraph: true,
                keepLineBreaks: false,
                chapterPatterns: AppSettings.defaultChapterPatterns
            )

            #expect(parsed.chapters.count == 1)
            #expect(parsed.chapters[0].paragraphs == ["第一段", "第二段"])
            #expect(parsed.chapters[0].paragraphs.contains("__BLANK__") == false)
        }
    }

    @Test("关闭缩进整理时保留全角空格但移除 ASCII 空白")
    func preservesFullWidthIndentWhenIndentParagraphIsFalse() async throws {
        try await TestFileSystem.withTemporaryDirectory { directoryURL in
            let fileURL = try TestFileSystem.writeText(
                "  \u{3000}正文段落  \n",
                named: "indent.txt",
                in: directoryURL
            )

            let parsed = try await TXTParser().parse(
                url: fileURL,
                indentParagraph: false,
                keepLineBreaks: false,
                chapterPatterns: AppSettings.defaultChapterPatterns
            )

            #expect(parsed.chapters.count == 1)
            #expect(parsed.chapters[0].paragraphs == ["\u{3000}正文段落"])
        }
    }

    @Test("自定义章节规则携带 level")
    func appliesCustomPatternsAndLevels() async throws {
        try await TestFileSystem.withTemporaryDirectory { directoryURL in
            let fileURL = try TestFileSystem.writeText(
                """
                第一卷 启程
                第一章 起点
                章节正文
                第二章 继续
                后续正文
                """,
                named: "custom-patterns.txt",
                in: directoryURL
            )

            let patterns = [
                ChapterPattern(value: "^\\s*第[一二三四五六七八九十]+卷.*", level: 1),
                ChapterPattern(value: "^\\s*第[一二三四五六七八九十]+章.*", level: 2),
            ]

            let parsed = try await TXTParser().parse(
                url: fileURL,
                indentParagraph: true,
                keepLineBreaks: false,
                chapterPatterns: patterns
            )

            #expect(parsed.chapters.count == 3)
            #expect(parsed.chapters[0].title == "第一卷 启程")
            #expect(parsed.chapters[0].level == 1)
            #expect(parsed.chapters[0].paragraphs.isEmpty)
            #expect(parsed.chapters[1].title == "第一章 起点")
            #expect(parsed.chapters[1].level == 2)
            #expect(parsed.chapters[1].paragraphs == ["章节正文"])
            #expect(parsed.chapters[2].title == "第二章 继续")
            #expect(parsed.chapters[2].level == 2)
            #expect(parsed.chapters[2].paragraphs == ["后续正文"])
        }
    }

    @Test("自定义规则全失效时回退到内建中文章节规则")
    func fallsBackToBuiltInChapterRuleWhenCustomPatternsAreInvalid() async throws {
        try await TestFileSystem.withTemporaryDirectory { directoryURL in
            let fileURL = try TestFileSystem.writeText(
                """
                第1章 标题
                正文内容
                """,
                named: "fallback.txt",
                in: directoryURL
            )

            let parsed = try await TXTParser().parse(
                url: fileURL,
                indentParagraph: true,
                keepLineBreaks: false,
                chapterPatterns: [ChapterPattern(value: "[", level: 3)]
            )

            #expect(parsed.chapters.count == 1)
            #expect(parsed.chapters[0].title == "第1章 标题")
            #expect(parsed.chapters[0].level == 1)
            #expect(parsed.chapters[0].paragraphs == ["正文内容"])
        }
    }

    @Test("空文件回退为单章节占位")
    func returnsSinglePlaceholderChapterForEmptyFile() async throws {
        try await TestFileSystem.withTemporaryDirectory { directoryURL in
            let fileURL = try TestFileSystem.writeText(
                "",
                named: "empty.txt",
                in: directoryURL
            )

            let parsed = try await TXTParser().parse(
                url: fileURL,
                indentParagraph: true,
                keepLineBreaks: false,
                chapterPatterns: AppSettings.defaultChapterPatterns
            )

            #expect(parsed.title == "empty")
            #expect(parsed.chapters.count == 1)
            #expect(parsed.chapters[0].title == "empty")
            #expect(parsed.chapters[0].level == 1)
            #expect(parsed.chapters[0].paragraphs == [String(localized: "error.empty_file")])
        }
    }

    @Test("读取失败时抛出 emptyFile")
    func throwsEmptyFileForMissingURL() async {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).txt")

        let parser = TXTParser()
        var capturedError: Me2PressError?

        do {
            _ = try await parser.parse(
                url: missingURL,
                indentParagraph: true,
                keepLineBreaks: false,
                chapterPatterns: AppSettings.defaultChapterPatterns
            )
        } catch let error {
            capturedError = error
        }

        guard case let .emptyFile(name)? = capturedError else {
            #expect(Bool(false))
            return
        }

        #expect(name == missingURL.lastPathComponent)
    }
}
