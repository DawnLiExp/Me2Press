//
//  EPUBBuilder.swift
//  Me2Press
//
//  Generates EPUB 3.0 directory structure from ParsedBook.
//  Entry points: buildAsync() (MainActor-safe), build() (nonisolated/sync).
//  Chapter.level 1/2/3 maps to <h1>/<h2>/<h3>; NCX and nav.xhtml mirror the same hierarchy.
//

import Foundation

enum EPUBBuilder {
    // MARK: - Async entry point

    static func buildAsync(
        book: ParsedBook,
        uuid: String,
        coverImage: URL?,
        indentParagraph: Bool,
        author: String,
        tempDir: URL
    ) async throws(Me2PressError) {
        do {
            try await Task.detached(priority: .userInitiated) {
                try build(book: book, uuid: uuid,
                          coverImage: coverImage, indentParagraph: indentParagraph,
                          author: author, tempDir: tempDir)
            }.value
        } catch let e as Me2PressError {
            throw e
        } catch {
            throw Me2PressError.epubBuildFailed(reason: error.localizedDescription)
        }
    }

    // MARK: - Synchronous core

    nonisolated static func build(
        book: ParsedBook,
        uuid: String,
        coverImage: URL?,
        indentParagraph: Bool,
        author: String,
        tempDir: URL
    ) throws(Me2PressError) {
        do {
            let fm = FileManager.default
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

            try "application/epub+zip".write(to: tempDir.appendingPathComponent("mimetype"), atomically: true, encoding: .ascii)

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
            try containerXML.write(to: metaInfDir.appendingPathComponent("container.xml"), atomically: true, encoding: .utf8)

            let oebpsDir = tempDir.appendingPathComponent("OEBPS")
            try fm.createDirectory(at: oebpsDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: oebpsDir.appendingPathComponent("Styles"), withIntermediateDirectories: true)
            try fm.createDirectory(at: oebpsDir.appendingPathComponent("Images"), withIntermediateDirectories: true)
            try fm.createDirectory(at: oebpsDir.appendingPathComponent("Text"), withIntermediateDirectories: true)

            var hasCover = false
            if let cover = coverImage {
                try fm.copyItem(at: cover, to: oebpsDir.appendingPathComponent("Images/cover.jpg"))
                hasCover = true
            }

            // IMPORTANT: h1 intentionally matches the old h2 style so single-level books are unaffected.
            // h2/h3 are only visible in multi-level TOC books.
            let css = """
            @charset "UTF-8";
            body { font-family: serif; line-height: 1.8; margin: 1em; }
            p { margin: 0; padding: 0; text-indent: \(indentParagraph ? "2em" : "0"); }
            p.blank { margin: 0.5em 0; text-indent: 0; }
            h1 {
              text-align: center;
              margin: 4em 15% 3em;
              padding: 1.2em 0;
              border-top: 1px solid #333;
              border-bottom: 4px double #333;
              letter-spacing: 0.2em;
              font-size: 1.4em;
              font-weight: bold;
              line-height: 1.5;
              color: #111;
              text-indent: 0;
            }
            h2 {
              text-align: center;
              margin: 3em 5% 2em;
              padding: 0.8em 0;
              border-bottom: 2px solid #555;
              letter-spacing: 0.15em;
              font-size: 1.25em;
              font-weight: bold;
              line-height: 1.5;
              color: #222;
              text-indent: 0;
            }
            h3 {
              text-align: center;
              margin: 2em 0 1.2em;
              letter-spacing: 0.1em;
              font-size: 1.1em;
              font-weight: bold;
              text-indent: 0;
            }
            .cover-img { width: 100%; height: auto; }
            """
            try css.write(to: oebpsDir.appendingPathComponent("Styles/style.css"), atomically: true, encoding: .utf8)

            var spineItems = [String]()
            var manifestItems = [String]()
            var chapterIDs = [String]()

            if hasCover {
                let coverXHTML = """
                <?xml version="1.0" encoding="UTF-8"?>
                <!DOCTYPE html>
                <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
                <head>
                  <title>Cover</title>
                  <link href="../Styles/style.css" type="text/css" rel="stylesheet"/>
                </head>
                <body style="margin: 0; padding: 0; text-align: center;">
                  <img src="../Images/cover.jpg" alt="Cover" class="cover-img"/>
                </body>
                </html>
                """
                try coverXHTML.write(to: oebpsDir.appendingPathComponent("Text/cover.xhtml"), atomically: true, encoding: .utf8)
                manifestItems.append("<item id=\"cover-page\" href=\"Text/cover.xhtml\" media-type=\"application/xhtml+xml\"/>")
                spineItems.append("<itemref idref=\"cover-page\" linear=\"yes\"/>")
            }

            for (i, chapter) in book.chapters.enumerated() {
                let id = "ch\(String(format: "%03d", i + 1))"
                chapterIDs.append(id)

                let escapedTitle = xmlEscape(chapter.title)
                let headingLevel = max(1, min(3, chapter.level))

                var paragraphsHtml = ""
                for p in chapter.paragraphs {
                    if p == "__BLANK__" {
                        paragraphsHtml += "  <p class=\"blank\"></p>\n"
                    } else {
                        paragraphsHtml += "  <p>\(p)</p>\n"
                    }
                }

                let html = """
                <?xml version="1.0" encoding="UTF-8"?>
                <!DOCTYPE html>
                <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
                <head>
                  <title>\(escapedTitle)</title>
                  <link href="../Styles/style.css" type="text/css" rel="stylesheet"/>
                </head>
                <body>
                  <h\(headingLevel)>\(escapedTitle)</h\(headingLevel)>
                \(paragraphsHtml)
                </body>
                </html>
                """
                try html.write(to: oebpsDir.appendingPathComponent("Text/\(id).xhtml"), atomically: true, encoding: .utf8)

                manifestItems.append("<item id=\"\(id)\" href=\"Text/\(id).xhtml\" media-type=\"application/xhtml+xml\"/>")
                spineItems.append("<itemref idref=\"\(id)\"/>")
            }

            let (ncxNavPoints, ncxDepth) = buildNCXNavPoints(chapters: book.chapters, ids: chapterIDs)

            let tocNCX = """
            <?xml version="1.0" encoding="UTF-8"?>
            <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
              <head>
                <meta name="dtb:uid" content="urn:uuid:\(uuid)"/>
                <meta name="dtb:depth" content="\(ncxDepth)"/>
                <meta name="dtb:totalPageCount" content="0"/>
                <meta name="dtb:maxPageNumber" content="0"/>
              </head>
              <docTitle><text>\(xmlEscape(book.title))</text></docTitle>
              <navMap>
            \(ncxNavPoints)
              </navMap>
            </ncx>
            """
            try tocNCX.write(to: oebpsDir.appendingPathComponent("toc.ncx"), atomically: true, encoding: .utf8)

            let nestedNavOL = buildNavOLList(chapters: book.chapters, ids: chapterIDs)
            let navXHTML = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE html>
            <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
            <head>
              <title>Navigation</title>
              <link href="../Styles/style.css" type="text/css" rel="stylesheet"/>
            </head>
            <body>
              <nav epub:type="toc" id="toc">
                <h1>Contents</h1>
                \(nestedNavOL)
              </nav>
            </body>
            </html>
            """
            try navXHTML.write(to: oebpsDir.appendingPathComponent("nav.xhtml"), atomically: true, encoding: .utf8)

            let escapedTitle = xmlEscape(book.title)
            let escapedAuthor = xmlEscape(author)
            let iso8601 = ISO8601DateFormatter().string(from: Date())

            var opf = """
            <?xml version="1.0" encoding="utf-8"?>
            <package version="3.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="BookID">
              <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                <dc:title>\(escapedTitle)</dc:title>
                <dc:language>zh-Hans</dc:language>
                <dc:creator>\(escapedAuthor)</dc:creator>
                <dc:identifier id="BookID">urn:uuid:\(uuid)</dc:identifier>
                <meta property="dcterms:modified">\(iso8601)</meta>
            """
            if hasCover {
                opf += "    <meta name=\"cover\" content=\"cover-image\"/>\n"
            }
            opf += "  </metadata>\n"
            opf += "  <manifest>\n"
            opf += "    <item id=\"ncx\" href=\"toc.ncx\" media-type=\"application/x-dtbncx+xml\"/>\n"
            opf += "    <item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/>\n"
            opf += "    <item id=\"style\" href=\"Styles/style.css\" media-type=\"text/css\"/>\n"
            if hasCover {
                opf += "    <item id=\"cover-image\" href=\"Images/cover.jpg\" media-type=\"image/jpeg\" properties=\"cover-image\"/>\n"
            }
            opf += "    \(manifestItems.joined(separator: "\n    "))\n"
            opf += "  </manifest>\n"
            opf += "  <spine toc=\"ncx\">\n"
            opf += "    \(spineItems.joined(separator: "\n    "))\n"
            opf += "  </spine>\n"
            opf += "</package>"

            try opf.write(to: oebpsDir.appendingPathComponent("content.opf"), atomically: true, encoding: .utf8)

        } catch let e as Me2PressError {
            throw e
        } catch {
            throw Me2PressError.epubBuildFailed(reason: error.localizedDescription)
        }
    }

    // MARK: - Nav <ol> builder (EPUB3 Navigation Document)

    /// Builds a nested `<ol>` structure for nav.xhtml from Chapter.level values.
    ///
    /// Stack-driven: push on deeper entry, pop+close on shallower.
    /// Example for levels [1, 2, 3, 3, 1]:
    ///   <ol>
    ///     <li><a>L1</a>
    ///       <ol><li><a>L2</a>
    ///         <ol>
    ///           <li><a>L3</a></li>
    ///           <li><a>L3</a></li>
    ///         </ol></li>
    ///       </ol>
    ///     </li>
    ///     <li><a>L1</a>...</li>
    ///   </ol>
    private nonisolated static func buildNavOLList(
        chapters: [Chapter],
        ids: [String]
    ) -> String {
        var result = "<ol>\n"
        var levelStack: [Int] = []

        for (i, chapter) in chapters.enumerated() {
            guard i < ids.count else { break }
            let level = max(1, min(6, chapter.level))
            let esc = xmlEscape(chapter.title)
            let href = "Text/\(ids[i]).xhtml"

            if levelStack.isEmpty {
                result += "<li><a href=\"\(href)\">\(esc)</a>"
                levelStack.append(level)
            } else {
                let topLevel = levelStack.last!

                if level > topLevel {
                    result += "\n<ol>\n<li><a href=\"\(href)\">\(esc)</a>"
                    levelStack.append(level)
                } else if level == topLevel {
                    result += "</li>\n<li><a href=\"\(href)\">\(esc)</a>"
                } else {
                    result += "</li>\n"
                    while !levelStack.isEmpty, levelStack.last! > level {
                        result += "</ol>\n</li>\n"
                        levelStack.removeLast()
                    }
                    result += "<li><a href=\"\(href)\">\(esc)</a>"
                    if levelStack.last != level {
                        levelStack.append(level)
                    }
                }
            }
        }

        if !levelStack.isEmpty {
            result += "</li>\n"
            levelStack.removeLast()
            while !levelStack.isEmpty {
                result += "</ol>\n</li>\n"
                levelStack.removeLast()
            }
        }
        result += "</ol>"
        return result
    }

    // MARK: - NCX navPoint builder (EPUB2/Kindle fallback)

    /// Builds nested NCX navPoint strings from Chapter.level values.
    ///
    /// Stack-driven: pop all open levels >= current before opening a new navPoint.
    /// Remaining open levels are closed after the loop.
    private nonisolated static func buildNCXNavPoints(
        chapters: [Chapter],
        ids: [String]
    ) -> (navPoints: String, depth: Int) {
        var result = ""
        var openLevels: [Int] = []
        var playOrder = 0
        var maxDepth = 0

        for (i, chapter) in chapters.enumerated() {
            guard i < ids.count else { break }
            playOrder += 1
            let level = max(1, min(6, chapter.level))
            maxDepth = max(maxDepth, level)
            let id = ids[i]
            let esc = xmlEscape(chapter.title)

            while let last = openLevels.last, last >= level {
                result += "</navPoint>\n"
                openLevels.removeLast()
            }

            result += "<navPoint id=\"navPoint-\(playOrder)\" playOrder=\"\(playOrder)\">\n"
            result += "  <navLabel><text>\(esc)</text></navLabel>\n"
            result += "  <content src=\"Text/\(id).xhtml\"/>\n"
            openLevels.append(level)
        }

        while !openLevels.isEmpty {
            result += "</navPoint>\n"
            openLevels.removeLast()
        }

        return (result, max(maxDepth, 1))
    }

    // MARK: - Helpers

    private nonisolated static func xmlEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
