//
//  ComicFolderResolver.swift
//  Me2Press
//
//  Background folder resolution for comic drag-and-drop intake.
//

import Foundation

enum ComicFolderResolver {
    private nonisolated static let imageExts = Set(["jpg", "jpeg", "png"])

    nonisolated static func resolveDroppedFolders(_ urls: [URL]) async -> [URL] {
        await Task.detached(priority: .userInitiated) {
            resolveDroppedFoldersSync(urls)
        }.value
    }

    private nonisolated static func resolveDroppedFoldersSync(_ urls: [URL]) -> [URL] {
        var results = [URL]()
        var seen = Set<String>()

        for url in urls {
            for folder in resolveComicFolders(url) {
                let canonicalFolder = canonicalFolderURL(folder)
                if seen.insert(canonicalFolder.path).inserted {
                    results.append(canonicalFolder)
                }
            }
        }

        return results
    }

    private nonisolated static func hasDirectImages(in folderURL: URL) -> Bool {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return false }

        return children.contains { child in
            var isDir: ObjCBool = false
            fm.fileExists(atPath: child.path, isDirectory: &isDir)
            return !isDir.boolValue && imageExts.contains(child.pathExtension.lowercased())
        }
    }

    /// Returns [] for empty folders or images buried 3+ levels deep.
    private nonisolated static func resolveComicFolders(_ url: URL) -> [URL] {
        let folderURL = canonicalFolderURL(url)
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: folderURL.path, isDirectory: &isDir), isDir.boolValue else {
            return []
        }

        if hasDirectImages(in: folderURL) {
            return [folderURL]
        }

        guard let children = try? fm.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let subdirs = children.filter { child in
            var childIsDir: ObjCBool = false
            fm.fileExists(atPath: child.path, isDirectory: &childIsDir)
            return childIsDir.boolValue
        }

        let subdirsWithImages = subdirs.filter { hasDirectImages(in: $0) }
        if !subdirsWithImages.isEmpty {
            return subdirsWithImages.sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
        }

        return []
    }

    private nonisolated static func canonicalFolderURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}
