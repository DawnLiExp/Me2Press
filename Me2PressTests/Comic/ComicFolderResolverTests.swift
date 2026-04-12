//
//  ComicFolderResolverTests.swift
//  Me2PressTests
//
//  Coverage for comic drag-and-drop folder resolution.
//

import Foundation
import Testing
@testable import Me2Press

@Suite("ComicFolderResolver")
struct ComicFolderResolverTests {
    @Test("直接含图目录返回自身")
    func returnsFolderWhenItContainsDirectImages() async throws {
        try await TestFileSystem.withTemporaryDirectory { directoryURL in
            let folderURL = try TestFileSystem.createDirectory(named: "FolderA", in: directoryURL)
            try TestFileSystem.writeDataFile(named: "1.jpg", size: 1, in: folderURL)

            let resolved = await ComicFolderResolver.resolveDroppedFolders([folderURL])

            #expect(resolved == [folderURL])
        }
    }

    @Test("一级子目录含图时展开并稳定排序")
    func expandsFirstLevelChildrenWithImages() async throws {
        try await TestFileSystem.withTemporaryDirectory { directoryURL in
            let rootURL = try TestFileSystem.createDirectory(named: "Root", in: directoryURL)
            let vol2URL = try TestFileSystem.createDirectory(named: "Vol2", in: rootURL)
            let vol1URL = try TestFileSystem.createDirectory(named: "Vol1", in: rootURL)
            try TestFileSystem.writeDataFile(named: "1.jpg", size: 1, in: vol2URL)
            try TestFileSystem.writeDataFile(named: "1.jpg", size: 1, in: vol1URL)

            let resolved = await ComicFolderResolver.resolveDroppedFolders([rootURL])

            #expect(resolved == [vol1URL, vol2URL])
        }
    }

    @Test("仅更深层含图时忽略")
    func ignoresImagesDeeperThanOneLevel() async throws {
        try await TestFileSystem.withTemporaryDirectory { directoryURL in
            let rootURL = try TestFileSystem.createDirectory(named: "Root", in: directoryURL)
            let levelOneURL = try TestFileSystem.createDirectory(named: "A", in: rootURL)
            let levelTwoURL = try TestFileSystem.createDirectory(named: "B", in: levelOneURL)
            try TestFileSystem.writeDataFile(named: "1.jpg", size: 1, in: levelTwoURL)

            let resolved = await ComicFolderResolver.resolveDroppedFolders([rootURL])

            #expect(resolved.isEmpty)
        }
    }

    @Test("非目录输入被忽略")
    func ignoresNonDirectoryURLs() async throws {
        try await TestFileSystem.withTemporaryDirectory { directoryURL in
            let fileURL = try TestFileSystem.writeDataFile(named: "not-a-folder.jpg", size: 1, in: directoryURL)

            let resolved = await ComicFolderResolver.resolveDroppedFolders([fileURL])

            #expect(resolved.isEmpty)
        }
    }

    @Test("重复目录只保留一次")
    func deduplicatesRepeatedFolders() async throws {
        try await TestFileSystem.withTemporaryDirectory { directoryURL in
            let rootURL = try TestFileSystem.createDirectory(named: "Root", in: directoryURL)
            let volumeURL = try TestFileSystem.createDirectory(named: "Vol1", in: rootURL)
            try TestFileSystem.writeDataFile(named: "1.png", size: 1, in: volumeURL)

            let resolved = await ComicFolderResolver.resolveDroppedFolders([volumeURL, rootURL, volumeURL])

            #expect(resolved == [volumeURL])
        }
    }

    @Test("混合输入时仅保留合法漫画目录")
    func keepsOnlyValidComicFoldersFromMixedInput() async throws {
        try await TestFileSystem.withTemporaryDirectory { directoryURL in
            let directFolderURL = try TestFileSystem.createDirectory(named: "Direct", in: directoryURL)
            let emptyFolderURL = try TestFileSystem.createDirectory(named: "Empty", in: directoryURL)
            let rootURL = try TestFileSystem.createDirectory(named: "Root", in: directoryURL)
            let vol1URL = try TestFileSystem.createDirectory(named: "Vol1", in: rootURL)
            let vol2URL = try TestFileSystem.createDirectory(named: "Vol2", in: rootURL)
            let fileURL = try TestFileSystem.writeDataFile(named: "notes.txt", size: 1, in: directoryURL)

            try TestFileSystem.writeDataFile(named: "cover.jpg", size: 1, in: directFolderURL)
            try TestFileSystem.writeDataFile(named: "1.jpg", size: 1, in: vol1URL)
            try TestFileSystem.writeDataFile(named: "1.png", size: 1, in: vol2URL)

            let resolved = await ComicFolderResolver.resolveDroppedFolders([
                emptyFolderURL,
                fileURL,
                directFolderURL,
                rootURL,
                vol1URL,
            ])

            #expect(resolved == [directFolderURL, vol1URL, vol2URL])
        }
    }
}
