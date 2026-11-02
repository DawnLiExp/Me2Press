//
//  ComicVolumeSplitterTests.swift
//  Me2PressTests
//
//  Coverage for comic volume boundary decisions.
//

import Foundation
import Testing
@testable import Me2Press

@Suite("ComicVolumeSplitter")
struct ComicVolumeSplitterTests {
    @Test("Repeated covers consume each volume's budget without duplicating a source page", arguments: [true, false])
    func repeatedCover(coverIsInSource: Bool) throws {
        try TestFileSystem.withTemporaryDirectory { directory in
            let cover = try TestFileSystem.writeDataFile(named: "cover.jpg", size: 20, in: directory)
            let a = try TestFileSystem.writeDataFile(named: "001.jpg", size: 40, in: directory)
            let b = try TestFileSystem.writeDataFile(named: "002.jpg", size: 40, in: directory)
            let c = try TestFileSystem.writeDataFile(named: "003.jpg", size: 1, in: directory)
            let images = (coverIsInSource ? [cover] : []) + [a, b, c]
            let volumes = ComicVolumeSplitter.split(imageURLs: images, threshold: 100, coverImageURL: cover)
            #expect(volumes == [[cover, a, b], [cover, c]])
            #expect(volumes.allSatisfy { ComicVolumeSplitter.estimateTotalSize(imageURLs: $0) <= 100 })
        }
    }

    @Test("A cover selected through a symbolic link is not duplicated")
    func linkedCover() throws {
        try TestFileSystem.withTemporaryDirectory { directory in
            let cover = try TestFileSystem.writeDataFile(named: "cover.jpg", size: 20, in: directory)
            let page = try TestFileSystem.writeDataFile(named: "page.jpg", size: 30, in: directory)
            let link = directory.appendingPathComponent("linked.jpg")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: cover)
            #expect(ComicVolumeSplitter.split(imageURLs: [cover, page], threshold: 100, coverImageURL: link) == [[link, page]])
        }
    }

    @Test("空输入返回空数组")
    func returnsEmptyVolumesForEmptyInput() {
        #expect(ComicVolumeSplitter.split(imageURLs: []).isEmpty)
    }

    @Test("总大小低于阈值时不分卷")
    func keepsSingleVolumeBelowThreshold() throws {
        try TestFileSystem.withTemporaryDirectory { directoryURL in
            let urls = try [
                TestFileSystem.writeDataFile(named: "001.jpg", size: 20, in: directoryURL),
                TestFileSystem.writeDataFile(named: "002.jpg", size: 30, in: directoryURL),
                TestFileSystem.writeDataFile(named: "003.jpg", size: 40, in: directoryURL),
            ]

            let volumes = ComicVolumeSplitter.split(imageURLs: urls, threshold: 100)

            #expect(volumes.count == 1)
            #expect(volumes[0] == urls)
        }
    }

    @Test("加入下一张后超阈值时切卷")
    func splitsBeforeImageThatWouldOverflowThreshold() throws {
        try TestFileSystem.withTemporaryDirectory { directoryURL in
            let urls = try [
                TestFileSystem.writeDataFile(named: "001.jpg", size: 50, in: directoryURL),
                TestFileSystem.writeDataFile(named: "002.jpg", size: 40, in: directoryURL),
                TestFileSystem.writeDataFile(named: "003.jpg", size: 30, in: directoryURL),
            ]

            let volumes = ComicVolumeSplitter.split(imageURLs: urls, threshold: 100)

            #expect(volumes.count == 2)
            #expect(volumes[0] == Array(urls.prefix(2)))
            #expect(volumes[1] == [urls[2]])
        }
    }

    @Test("单张超阈值图片独占一卷")
    func keepsOversizedImageInOwnVolume() throws {
        try TestFileSystem.withTemporaryDirectory { directoryURL in
            let urls = try [
                TestFileSystem.writeDataFile(named: "001.jpg", size: 40, in: directoryURL),
                TestFileSystem.writeDataFile(named: "002.jpg", size: 120, in: directoryURL),
                TestFileSystem.writeDataFile(named: "003.jpg", size: 30, in: directoryURL),
            ]

            let volumes = ComicVolumeSplitter.split(imageURLs: urls, threshold: 100)

            #expect(volumes.count == 3)
            #expect(volumes[0] == [urls[0]])
            #expect(volumes[1] == [urls[1]])
            #expect(volumes[2] == [urls[2]])
        }
    }

    @Test("总大小估算等于文件尺寸总和")
    func estimatesTotalSizeFromFileMetadata() throws {
        try TestFileSystem.withTemporaryDirectory { directoryURL in
            let urls = try [
                TestFileSystem.writeDataFile(named: "001.jpg", size: 11, in: directoryURL),
                TestFileSystem.writeDataFile(named: "002.jpg", size: 22, in: directoryURL),
                TestFileSystem.writeDataFile(named: "003.jpg", size: 33, in: directoryURL),
            ]

            let total = ComicVolumeSplitter.estimateTotalSize(imageURLs: urls)

            #expect(total == 66)
        }
    }
}
