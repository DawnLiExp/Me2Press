//
//  CoverGenerator.swift
//  Me2Press
//
//  Generates a text-based cover image using pure CoreGraphics + CoreText (no AppKit),
//  so all methods are nonisolated and safe to call from any executor.
//
//  Layout (top → bottom, visual):
//    • Decorative border frame + corner L-accents
//    • Book title (~38% from top), Georgia-Bold 46pt, kern +3
//    • Ornament separator (split line + center diamond)
//    • Author name, Georgia 20pt, 60% opacity
//
//  Entry points: generate() — synchronous, nonisolated, blocking file I/O.
//                generateAsync() — offloads to a detached task; safe to call from MainActor.
//

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum CoverGenerator {
    // MARK: - Async entry point

    static func generateAsync(
        title: String,
        author: String = "",
        to outputURL: URL
    ) async throws(Me2PressError) {
        do {
            try await Task.detached(priority: .userInitiated) {
                try generate(title: title, author: author, to: outputURL)
            }.value
        } catch let e as Me2PressError {
            throw e
        } catch {
            throw Me2PressError.coverEncodeFailed
        }
    }

    // MARK: - Synchronous core

    nonisolated static func generate(
        title: String,
        author: String = "",
        to outputURL: URL
    ) throws(Me2PressError) {
        let width = 600
        let height = 800
        let W = CGFloat(width)
        let H = CGFloat(height)

        // ── Background color (4 deep dark options) ────────────────────────
        let bgColors: [CGColor] = [
            CGColor(red: 0.11, green: 0.17, blue: 0.26, alpha: 1), // deep navy
            CGColor(red: 0.20, green: 0.11, blue: 0.19, alpha: 1), // deep plum
            CGColor(red: 0.12, green: 0.20, blue: 0.15, alpha: 1), // deep forest
            CGColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1) // charcoal
        ]
        let bgColor = bgColors.randomElement() ?? bgColors[0]

        // ── Bitmap context ────────────────────────────────────────────────
        guard let ctx = CGContext(
            data: nil,
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw Me2PressError.coverContextFailed
        }

        let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        let centerStyle = makeCenterAlignStyle()

        // ── Fill background ───────────────────────────────────────────────
        ctx.setFillColor(bgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // ── Decorative border frame ───────────────────────────────────────
        let bi: CGFloat = 28 // border inset
        let borderRect = CGRect(x: bi, y: bi, width: W - bi * 2, height: H - bi * 2)
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.50))
        ctx.setLineWidth(0.75)
        ctx.stroke(borderRect)

        // ── Corner L-accents ──────────────────────────────────────────────
        let al: CGFloat = 22 // accent arm length
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.85))
        ctx.setLineWidth(1.5)

        let lCorners: [(CGPoint, CGPoint, CGPoint)] = [
            // bottom-left
            (CGPoint(x: bi, y: bi + al), CGPoint(x: bi, y: bi), CGPoint(x: bi + al, y: bi)),
            // bottom-right
            (CGPoint(x: W - bi - al, y: bi), CGPoint(x: W - bi, y: bi), CGPoint(x: W - bi, y: bi + al)),
            // top-left
            (CGPoint(x: bi, y: H - bi - al), CGPoint(x: bi, y: H - bi), CGPoint(x: bi + al, y: H - bi)),
            // top-right
            (CGPoint(x: W - bi - al, y: H - bi), CGPoint(x: W - bi, y: H - bi), CGPoint(x: W - bi, y: H - bi - al))
        ]
        for (p1, p2, p3) in lCorners {
            ctx.move(to: p1)
            ctx.addLine(to: p2)
            ctx.addLine(to: p3)
            ctx.strokePath()
        }

        // ── Title text ────────────────────────────────────────────────────
        // CGContext origin is bottom-left with Y increasing upward.
        // titleCenterY = H * 0.62 places the visual center ~38% from the top.
        let titleFont = CTFontCreateWithName("Georgia-Bold" as CFString, 46, nil)
        let titleAttrs: [CFString: Any] = [
            kCTFontAttributeName: titleFont,
            kCTForegroundColorAttributeName: white,
            kCTParagraphStyleAttributeName: centerStyle,
            kCTKernAttributeName: CGFloat(3)
        ]
        guard let titleAttrStr = CFAttributedStringCreate(
            nil, title as CFString, titleAttrs as CFDictionary
        ) else { throw Me2PressError.coverImageFailed }

        let titleSetter = CTFramesetterCreateWithAttributedString(titleAttrStr)
        let titleConstraint = CGSize(width: W - 90, height: 270)
        let titleSize = CTFramesetterSuggestFrameSizeWithConstraints(
            titleSetter, CFRangeMake(0, 0), nil, titleConstraint, nil
        )

        let titleCenterY = H * 0.62
        let titleX = (W - titleSize.width) / 2
        let titleY = titleCenterY - titleSize.height / 2
        let titlePath = CGPath(
            rect: CGRect(x: titleX, y: titleY, width: titleSize.width, height: titleSize.height),
            transform: nil
        )
        CTFrameDraw(
            CTFramesetterCreateFrame(titleSetter, CFRangeMake(0, 0), titlePath, nil),
            ctx
        )

        // ── Ornament separator ────────────────────────────────────────────
        // Placed 32pt below the bottom edge of the title rect.
        let ornY: CGFloat = titleY - 32
        let ornHW: CGFloat = 54 // half-width of each line segment
        let midX = W / 2

        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.38))
        ctx.setLineWidth(0.7)
        // Left line
        ctx.move(to: CGPoint(x: midX - ornHW, y: ornY))
        ctx.addLine(to: CGPoint(x: midX - 7, y: ornY))
        ctx.strokePath()
        // Right line
        ctx.move(to: CGPoint(x: midX + 7, y: ornY))
        ctx.addLine(to: CGPoint(x: midX + ornHW, y: ornY))
        ctx.strokePath()

        // Center diamond (rotated square)
        ctx.saveGState()
        ctx.translateBy(x: midX, y: ornY)
        ctx.rotate(by: .pi / 4)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.50))
        let ds: CGFloat = 5.5
        ctx.fill(CGRect(x: -ds / 2, y: -ds / 2, width: ds, height: ds))
        ctx.restoreGState()

        // ── Author text ───────────────────────────────────────────────────
        if !author.isEmpty {
            let authorFont = CTFontCreateWithName("Georgia" as CFString, 20, nil)
            let authorColor = CGColor(red: 1, green: 1, blue: 1, alpha: 0.60)
            let authorAttrs: [CFString: Any] = [
                kCTFontAttributeName: authorFont,
                kCTForegroundColorAttributeName: authorColor,
                kCTParagraphStyleAttributeName: centerStyle,
                kCTKernAttributeName: CGFloat(1.5)
            ]
            guard let authorAttrStr = CFAttributedStringCreate(
                nil, author as CFString, authorAttrs as CFDictionary
            ) else { throw Me2PressError.coverImageFailed }

            let authorSetter = CTFramesetterCreateWithAttributedString(authorAttrStr)
            let authorConstraint = CGSize(width: W - 130, height: 70)
            let authorSize = CTFramesetterSuggestFrameSizeWithConstraints(
                authorSetter, CFRangeMake(0, 0), nil, authorConstraint, nil
            )

            // Place 18pt below the ornament line.
            let authorTopY = ornY - 18
            let authorX = (W - authorSize.width) / 2
            let authorY = authorTopY - authorSize.height
            let authorPath = CGPath(
                rect: CGRect(x: authorX, y: authorY, width: authorSize.width, height: authorSize.height),
                transform: nil
            )
            CTFrameDraw(
                CTFramesetterCreateFrame(authorSetter, CFRangeMake(0, 0), authorPath, nil),
                ctx
            )
        }

        // ── Export as JPEG ────────────────────────────────────────────────
        guard let cgImage = ctx.makeImage() else {
            throw Me2PressError.coverImageFailed
        }
        guard let dest = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.jpeg.identifier as CFString,
            1, nil
        ) else {
            throw Me2PressError.coverEncodeFailed
        }
        CGImageDestinationAddImage(
            dest, cgImage,
            [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary
        )
        guard CGImageDestinationFinalize(dest) else {
            throw Me2PressError.coverEncodeFailed
        }
    }

    // MARK: - Private helpers

    /// Creates a center-aligned `CTParagraphStyle` for use in attributed string drawing.
    private nonisolated static func makeCenterAlignStyle() -> CTParagraphStyle {
        var alignment = CTTextAlignment.center
        return withUnsafeMutablePointer(to: &alignment) { ptr in
            let setting = CTParagraphStyleSetting(
                spec: .alignment,
                valueSize: MemoryLayout<CTTextAlignment>.size,
                value: ptr
            )
            return withUnsafePointer(to: setting) { settingPtr in
                CTParagraphStyleCreate(settingPtr, 1)
            }
        }
    }
}
