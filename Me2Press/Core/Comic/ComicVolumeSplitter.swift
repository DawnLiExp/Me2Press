//
//  ComicVolumeSplitter.swift
//  Me2Press
//
//  Splits an ordered image URL array into multiple volumes when the total
//  uncompressed size would exceed kindlegen's effective processing limit.
//

import Foundation

enum ComicVolumeSplitter {
    /// Default split threshold: 380 MB.
    ///
    /// kindlegen reports E23026 when uncompressed assets exceed ~629 MB (629,145,600 bytes).
    /// 380 MB provides ~20 MB headroom above the per-volume image budget to account for
    /// EPUB overhead (XML, CSS, nav files) that is not counted in image sizes alone.
    nonisolated static let defaultThreshold: Int = 380 * 1024 * 1024 // 398,458,880 bytes

    /// Splits an ordered image URL array into volumes sized by disk usage.
    ///
    /// - Parameters:
    ///   - imageURLs: Sorted image URLs produced by `ComicEPUBBuilder.collectImageURLs`.
    ///   - threshold: Max uncompressed bytes per volume. Defaults to `defaultThreshold`.
    ///   - coverImageURL: Optional cover repeated and counted in every volume.
    ///     The same source file is excluded from body pages by its resolved path.
    /// - Returns: A 2-D array of per-volume URL groups.
    ///   Returns a single-element array when total size ≤ threshold.
    ///   Returns an empty array when `imageURLs` is empty.
    ///
    /// Edge case: a single image that alone exceeds the threshold forms its own volume
    /// rather than being appended indefinitely to the previous one.
    nonisolated static func split(
        imageURLs: [URL],
        threshold: Int = defaultThreshold,
        coverImageURL: URL? = nil
    ) -> [[URL]] {
        guard !imageURLs.isEmpty else { return [] }

        let cover = coverImageURL.map { [$0] } ?? []
        let coverSize = coverImageURL.map(fileSize(of:)) ?? 0
        let coverIdentity = coverImageURL?.resolvingSymlinksInPath().standardizedFileURL
        let bodyImages = imageURLs.filter {
            coverIdentity == nil || $0.resolvingSymlinksInPath().standardizedFileURL != coverIdentity
        }
        var volumes: [[URL]] = []
        var currentVolume = cover
        var currentSize = coverSize

        for url in bodyImages {
            let fileSize = fileSize(of: url)
            // Flush the current volume before starting a new one when adding this image
            // would breach the threshold. A lone oversized image always forms its own volume.
            if currentVolume.count > cover.count, currentSize + fileSize > threshold {
                volumes.append(currentVolume)
                currentVolume = cover
                currentSize = coverSize
            }
            currentVolume.append(url)
            currentSize += fileSize
        }

        if !currentVolume.isEmpty {
            volumes.append(currentVolume)
        }

        return volumes
    }

    /// Returns the total on-disk size of an image URL array using stat (no content read).
    nonisolated static func estimateTotalSize(imageURLs: [URL]) -> Int {
        imageURLs.reduce(0) { acc, url in acc + fileSize(of: url) }
    }

    // MARK: - Private

    private nonisolated static func fileSize(of url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
    }
}
