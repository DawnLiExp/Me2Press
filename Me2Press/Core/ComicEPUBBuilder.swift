//
//  ComicEPUBBuilder.swift
//  Me2Press
//
//  Entry points: buildAsync(folderURL:) collects images from disk;
//  buildAsync(images:title:) accepts a pre-split list for multi-volume packing.
//

import CoreGraphics
import Foundation
import ImageIO

enum ComicEPUBBuilder {
    // MARK: - Types

    private struct ImageMeta {
        let index: Int
        let newName: String
        let width: Int
        let height: Int
        let ext: String
    }

    // MARK: - Image collection

    nonisolated static func collectImageURLs(
        in folderURL: URL,
        fileManager: FileManager
    ) -> [URL] {
        let imageExts = Set(["jpg", "jpeg", "png"])
        guard let contents = try? fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return contents
            .filter { url in
                var isDir: ObjCBool = false
                fileManager.fileExists(atPath: url.path, isDirectory: &isDir)
                return !isDir.boolValue
                    && imageExts.contains(url.pathExtension.lowercased())
            }
            .sorted {
                $0.lastPathComponent
                    .localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
    }

    // MARK: - Async entry points

    static func buildAsync(folderURL: URL, uuid: String, author: String, tempDir: URL) async throws {
        try await build(folderURL: folderURL, uuid: uuid, author: author, tempDir: tempDir)
    }

    static func buildAsync(
        images: [URL],
        title: String,
        uuid: String,
        author: String,
        tempDir: URL
    ) async throws {
        try await build(images: images, title: title, uuid: uuid, author: author, tempDir: tempDir)
    }

    // MARK: - Synchronous wrappers

    nonisolated static func build(folderURL: URL, uuid: String, author: String, tempDir: URL) async throws {
        let fm = FileManager.default
        let images = collectImageURLs(in: folderURL, fileManager: fm)
        guard !images.isEmpty else {
            throw Me2PressError.noImagesFound(folderName: folderURL.lastPathComponent)
        }
        try await buildFromImages(images,
                                  title: folderURL.lastPathComponent,
                                  uuid: uuid,
                                  author: author,
                                  tempDir: tempDir)
    }

    nonisolated static func build(
        images: [URL],
        title: String,
        uuid: String,
        author: String,
        tempDir: URL
    ) async throws {
        guard !images.isEmpty else {
            throw Me2PressError.noImagesFound(folderName: title)
        }
        try await buildFromImages(images, title: title, uuid: uuid, author: author, tempDir: tempDir)
    }

    // MARK: - Private core

    /// Builds the full EPUB directory structure from an ordered image list.
    ///
    /// Image copy + dimension read runs in a bounded TaskGroup (2× active processors, max 16)
    /// to parallelise I/O without saturating the disk. Results are re-sorted by original index
    /// before XHTML generation so spine order matches the source file sort.
    private nonisolated static func buildFromImages(
        _ images: [URL],
        title: String,
        uuid: String,
        author: String,
        tempDir: URL
    ) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        try "application/epub+zip".write(
            to: tempDir.appendingPathComponent("mimetype"),
            atomically: true, encoding: .ascii
        )

        let metaInfDir = tempDir.appendingPathComponent("META-INF")
        try fm.createDirectory(at: metaInfDir, withIntermediateDirectories: true)
        let containerXML = """
        <?xml version="1.0"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
           <rootfiles>
              <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
           </rootfiles>
        </container>
        """
        try containerXML.write(
            to: metaInfDir.appendingPathComponent("container.xml"),
            atomically: true, encoding: .utf8
        )

        let oebpsDir = tempDir.appendingPathComponent("OEBPS")
        try fm.createDirectory(at: oebpsDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: oebpsDir.appendingPathComponent("Images"), withIntermediateDirectories: true)
        try fm.createDirectory(at: oebpsDir.appendingPathComponent("Text"), withIntermediateDirectories: true)

        let css = """
        @page { margin: 0; }
        body { display: block; margin: 0; padding: 0; background-color: #000000; }
        div { text-align: center; margin: 0; padding: 0; }
        """

        // ── Concurrent image copy + dimension read ────────────────────────
        // Concurrency is capped at 2× active processors (max 16) to parallelise
        // file copy and CGImageSource dimension reads without overwhelming the disk.
        // Falls back to 1236×1648 if the image source cannot be read.
        let imagesDir = oebpsDir.appendingPathComponent("Images")
        let concurrency = min(max(2, ProcessInfo.processInfo.activeProcessorCount * 2), 16)
        let metas: [ImageMeta] = try await withThrowingTaskGroup(of: ImageMeta.self) { group in
            var inFlight = 0
            var results = [ImageMeta]()

            for (i, imgURL) in images.enumerated() {
                if inFlight >= concurrency, let meta = try await group.next() {
                    results.append(meta)
                    inFlight -= 1
                }

                group.addTask {
                    try Task.checkCancellation()

                    let ext = imgURL.pathExtension.lowercased()
                    let newImgName = String(format: "img-%04d.%@", i + 1, ext)
                    let destImgURL = imagesDir.appendingPathComponent(newImgName)
                    try FileManager.default.copyItem(at: imgURL, to: destImgURL)

                    var w = 1236
                    var h = 1648
                    let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
                    if let imgSource = CGImageSourceCreateWithURL(imgURL as CFURL, sourceOptions),
                       let properties = CGImageSourceCopyPropertiesAtIndex(imgSource, 0, nil) as? [CFString: Any]
                    {
                        w = properties[kCGImagePropertyPixelWidth] as? Int ?? w
                        h = properties[kCGImagePropertyPixelHeight] as? Int ?? h
                    }

                    return ImageMeta(index: i, newName: newImgName, width: w, height: h, ext: ext)
                }
                inFlight += 1
            }

            while let meta = try await group.next() {
                results.append(meta)
            }

            return results.sorted { $0.index < $1.index }
        }

        // ── Generate XHTML pages ──────────────────────────────────────────
        var spineItems = [String]()
        var manifestItems = [String]()
        var maxW = 1236
        var maxH = 1648
        // IMPORTANT: page-spread alternates right→left starting with the cover page.
        // Kindle uses this to determine double-page spread layout; do not reset mid-volume.
        var pageSide = "right"

        for meta in metas {
            try Task.checkCancellation()

            maxW = max(maxW, meta.width)
            maxH = max(maxH, meta.height)

            let id = String(format: "page-%04d", meta.index + 1)
            let xhtml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE html>
            <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
            <head>
              <title>\(id)</title>
              <style type="text/css">
              \(css)
              </style>
              <meta name="viewport" content="width=\(meta.width), height=\(meta.height)"/>
            </head>
            <body>
              <div style="text-align:center;top:0.0%;">
                <div style="display:none;">.</div>
                <img width="\(meta.width)" height="\(meta.height)" src="../Images/\(meta.newName)" alt=""/>
              </div>
            </body>
            </html>
            """

            try xhtml.write(
                to: oebpsDir.appendingPathComponent("Text/\(id).xhtml"),
                atomically: true, encoding: .utf8
            )

            let mediaType = meta.ext == "png" ? "image/png" : "image/jpeg"
            let propertiesAttr = meta.index == 0 ? " properties=\"cover-image\"" : ""

            manifestItems.append(
                "    <item id=\"img-\(id)\" href=\"Images/\(meta.newName)\" media-type=\"\(mediaType)\"\(propertiesAttr)/>"
            )
            manifestItems.append(
                "    <item id=\"\(id)\" href=\"Text/\(id).xhtml\" media-type=\"application/xhtml+xml\"/>"
            )
            spineItems.append(
                "    <itemref idref=\"\(id)\" linear=\"yes\" properties=\"page-spread-\(pageSide)\"/>"
            )
            pageSide = (pageSide == "right") ? "left" : "right"
        }

        // ── toc.ncx ──────────────────────────────────────────────────────
        let escapedTitle = title
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let escapedAuthor = author
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")

        let tocNCX = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
          <head>
            <meta name="dtb:uid" content="urn:uuid:\(uuid)"/>
            <meta name="dtb:depth" content="1"/>
            <meta name="dtb:totalPageCount" content="0"/>
            <meta name="dtb:maxPageNumber" content="0"/>
          </head>
          <docTitle><text>\(escapedTitle)</text></docTitle>
          <navMap/>
        </ncx>
        """
        try tocNCX.write(
            to: oebpsDir.appendingPathComponent("toc.ncx"),
            atomically: true, encoding: .utf8
        )

        // ── nav.xhtml ─────────────────────────────────────────────────────
        let navXHTML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
        <head><title>\(escapedTitle)</title></head>
        <body>
          <nav epub:type="toc" id="toc"><ol/></nav>
        </body>
        </html>
        """
        try navXHTML.write(
            to: oebpsDir.appendingPathComponent("nav.xhtml"),
            atomically: true, encoding: .utf8
        )

        // ── content.opf ──────────────────────────────────────────────────
        let iso8601 = ISO8601DateFormatter().string(from: Date())
        let opf = """
        <?xml version="1.0" encoding="utf-8"?>
        <package version="3.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="BookID">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>\(escapedTitle)</dc:title>
            <dc:language>zh-Hans</dc:language>
            <dc:creator>\(escapedAuthor)</dc:creator>
            <dc:identifier id="BookID">urn:uuid:\(uuid)</dc:identifier>
            <meta property="dcterms:modified">\(iso8601)</meta>
            <meta name="cover" content="img-page-0001"/>
            <meta name="fixed-layout" content="true"/>
            <meta name="original-resolution" content="\(maxW)x\(maxH)"/>
            <meta name="book-type" content="comic"/>
            <meta name="primary-writing-mode" content="horizontal-rl"/>
            <meta name="zero-gutter" content="true"/>
            <meta name="zero-margin" content="true"/>
            <meta name="region-mag" content="true"/>
            <meta property="rendition:spread">landscape</meta>
            <meta property="rendition:layout">pre-paginated</meta>
            <meta name="ke-border-color" content="#FFFFFF"/>
            <meta name="ke-border-width" content="0"/>
            <meta name="orientation-lock" content="none"/>
          </metadata>
          <manifest>
            <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
            <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
        \(manifestItems.joined(separator: "\n"))
          </manifest>
          <spine page-progression-direction="rtl" toc="ncx">
        \(spineItems.joined(separator: "\n"))
          </spine>
        </package>
        """

        try opf.write(
            to: oebpsDir.appendingPathComponent("content.opf"),
            atomically: true, encoding: .utf8
        )
    }
}
