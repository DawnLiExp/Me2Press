//
//  EPUBKindleNormalizerTests.swift
//  Me2PressTests
//
//  Regression coverage for kindlegen XHTML charset normalization.
//

import Foundation
import Testing
@testable import Me2Press

@Suite("EPUBKindleNormalizer")
struct EPUBKindleNormalizerTests {
    @Test("UTF-8 HTML without encoding gets XML declaration")
    func addsUTF8DeclarationToUndeclaredHTML() throws {
        let source = Data("""
        <!DOCTYPE html><html xmlns="http://www.w3.org/1999/xhtml"><head><title></title></head><body>第一章</body></html>
        """.utf8)

        let normalized = try #require(EPUBKindleNormalizer.dataByAddingUTF8DeclarationIfNeeded(source))
        let text = try #require(String(data: normalized, encoding: .utf8))

        #expect(text.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
        #expect(text.contains("第一章"))
    }

    @Test("HTML with existing charset is unchanged")
    func leavesDeclaredCharsetUnchanged() {
        let source = Data("""
        <!DOCTYPE html><html><head><meta charset="UTF-8" /></head><body>第一章</body></html>
        """.utf8)

        #expect(EPUBKindleNormalizer.dataByAddingUTF8DeclarationIfNeeded(source) == nil)
    }

    @Test("Non UTF-8 HTML is unchanged")
    func leavesNonUTF8DataUnchanged() {
        let source = Data([0xFF, 0xFE, 0x3C, 0x00])

        #expect(EPUBKindleNormalizer.dataByAddingUTF8DeclarationIfNeeded(source) == nil)
    }
}
