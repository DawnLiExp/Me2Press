//
//  ComicBookViewModel.swift
//  Me2Press
//
//  Folder resolution (add override):
//    A) Folder has direct images → pack as single MOBI (subdirs ignored)
//    B) Folder has no direct images, subdirs have images → expand to those subdirs
//    C) Otherwise → skip silently
//
//  Volume splitting: images > 380 MB total → auto-split into multiple .mobi volumes.
//  Naming: single → "Name.mobi", multi → "Name [Vol.1].mobi", etc.
//

import AppKit
import SwiftUI

// MARK: - ComicBookError

enum ComicBookError: LocalizedError {
    case noImagesFound(folderName: String)

    var errorDescription: String? {
        switch self {
        case .noImagesFound(let name):
            return String(localized: "error.no_images \(name)")
        }
    }
}

// MARK: - ComicBookViewModel

@MainActor
@Observable
class ComicBookViewModel: ConversionViewModel {
    private static let imageExts = Set(["jpg", "jpeg", "png"])

    // MARK: - Folder resolution

    private func hasDirectImages(in folderURL: URL) -> Bool {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return false }
        return children.contains { child in
            var isDir: ObjCBool = false
            fm.fileExists(atPath: child.path, isDirectory: &isDir)
            return !isDir.boolValue
                && Self.imageExts.contains(child.pathExtension.lowercased())
        }
    }

    /// Resolves a dropped URL into the actual folder(s) to process (max two levels deep).
    /// Returns [] for empty folders or images buried 3+ levels deep.
    private func resolveComicFolders(_ url: URL) -> [URL] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir),
              isDir.boolValue else { return [] }

        // Case A: folder has direct images → leaf node
        if hasDirectImages(in: url) {
            return [url]
        }

        guard let children = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let subdirs = children.filter { child in
            var childIsDir: ObjCBool = false
            fm.fileExists(atPath: child.path, isDirectory: &childIsDir)
            return childIsDir.boolValue
        }

        // Case B: expand subdirs that contain images
        let subdirsWithImages = subdirs.filter { hasDirectImages(in: $0) }
        if !subdirsWithImages.isEmpty {
            return subdirsWithImages.sorted {
                $0.lastPathComponent
                    .localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
        }

        return []
    }

    // MARK: - ConversionViewModel overrides

    @discardableResult
    override func add(_ urls: [URL]) -> Int {
        var added = 0
        for url in urls {
            for folder in resolveComicFolders(url) where !items.contains(folder) {
                items.append(folder)
                added += 1
            }
        }
        return added
    }

    override func accepts(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            && isDir.boolValue
    }

    override func validateBeforeStart(appSettings: AppSettings, logger: LogManager) -> Bool {
        guard appSettings.isKindleGenReady, appSettings.kindlegenURL != nil else {
            logger.log(level: .error, "kindlegen is not configured.")
            return false
        }
        return true
    }

    override func convertItem(
        _ url: URL,
        index: Int,
        appSettings: AppSettings,
        logger: LogManager
    ) async throws {
        let log = AppLogger(category: "ComicBook", uiLogger: logger)
        guard let kindlegenURL = appSettings.kindlegenURL else { return }
        let runner = KindleGenRunner(kindlegenPath: kindlegenURL)
        let folderURL = url
        let baseName = url.lastPathComponent
        let outputFolder = folderURL.deletingLastPathComponent()

        // ── Scan & split ──────────────────────────────────────────────────
        progress.set(local: 0.0, step: String(localized: "progress.scanning"))

        let allImages = ComicEPUBBuilder.collectImageURLs(
            in: folderURL,
            fileManager: FileManager.default
        )
        guard !allImages.isEmpty else {
            throw ComicBookError.noImagesFound(folderName: baseName)
        }

        let volumes = ComicVolumeSplitter.split(imageURLs: allImages)
        let totalVolumes = volumes.count

        if totalVolumes > 1 {
            log.info(String(localized: "log.split_volumes \(totalVolumes)"))
        }

        for (volIdx, volumeImages) in volumes.enumerated() {
            try Task.checkCancellation()

            let volNumber = volIdx + 1
            let volName = outputName(base: baseName, volumeIndex: volNumber, totalVolumes: totalVolumes)

            let volSpan = 1.0 / Double(totalVolumes)
            let volBase = Double(volIdx) * volSpan

            func setVolumeProgress(_ local: Double, step: String) {
                progress.set(local: volBase + volSpan * local, step: step)
            }

            progress.volumeLabel = totalVolumes > 1
                ? String(localized: "progress.volume \(volNumber) \(totalVolumes)")
                : ""

            let tempDir = outputFolder.appendingPathComponent(".me2press_tmp_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let epubContentDir = tempDir.appendingPathComponent("content")
            try FileManager.default.createDirectory(at: epubContentDir, withIntermediateDirectories: true)
            let uuid = UUID().uuidString

            // Multi-volume: per-volume errors are logged but don't abort remaining volumes.
            do {
                // ── Step 1: Build EPUB ────────────────────────────────────
                setVolumeProgress(0.0, step: String(localized: "progress.building_epub"))
                let t1 = CFAbsoluteTimeGetCurrent()
                try await ComicEPUBBuilder.buildAsync(
                    images: volumeImages,
                    title: volName,
                    uuid: uuid,
                    author: appSettings.authorName,
                    tempDir: epubContentDir
                )
                setVolumeProgress(0.20, step: String(localized: "progress.building_epub"))
                logStep(volName, step: String(localized: "log.step.build_epub"), since: t1, log: log)

                // ── Step 2: Pack ZIP ──────────────────────────────────────
                let tempEpubURL = tempDir.appendingPathComponent("\(volName).epub")
                let zipSim = progress.startSimulation(
                    from: volBase + volSpan * 0.20,
                    to: volBase + volSpan * 0.45,
                    step: String(localized: "progress.packing"), rate: 0.10
                )
                let t2 = CFAbsoluteTimeGetCurrent()
                try await ZIPWriter.pack(directoryURL: epubContentDir, to: tempEpubURL)
                zipSim.cancel()
                setVolumeProgress(0.45, step: String(localized: "progress.packing"))
                logStep(volName, step: String(localized: "log.step.pack_zip"), since: t2, log: log)

                // ── Step 3: kindlegen ─────────────────────────────────────
                let kgSim = progress.startSimulation(
                    from: volBase + volSpan * 0.45,
                    to: volBase + volSpan * 0.95,
                    step: String(localized: "progress.kindlegen"), rate: 0.06
                )
                let t3 = CFAbsoluteTimeGetCurrent()
                let mobiPath = try await runner.convert(epubPath: tempEpubURL)
                kgSim.cancel()
                setVolumeProgress(0.95, step: String(localized: "progress.kindlegen"))
                logStep(volName, step: String(localized: "log.step.kindlegen"), since: t3, log: log)

                // ── Step 4: DualMetaFix ───────────────────────────────────
                setVolumeProgress(0.95, step: String(localized: "progress.fixing_meta"))
                let t4 = CFAbsoluteTimeGetCurrent()
                try await DualMetaFix.fixAsync(mobiPath: mobiPath, uuid: uuid)
                setVolumeProgress(1.0, step: String(localized: "progress.fixing_meta"))
                logStep(volName, step: String(localized: "log.step.dualmetafix"), since: t4, log: log)

                let outputURL = outputFolder.appendingPathComponent("\(volName).mobi")
                try? FileManager.default.removeItem(at: outputURL)
                try FileManager.default.moveItem(at: mobiPath, to: outputURL)
                log.info("[\(volName)] → \(outputURL.lastPathComponent)")

            } catch is CancellationError {
                // IMPORTANT: propagate immediately; do not continue remaining volumes.
                throw CancellationError()
            } catch {
                if totalVolumes > 1 {
                    log.error("[\(volName)] ❌ \(error.localizedDescription)")
                } else {
                    throw error
                }
            }
        }

        progress.volumeLabel = ""
    }

    // MARK: - Helpers

    /// Single volume → base name. Multi-volume → appends "[Vol.N]" suffix.
    private func outputName(base: String, volumeIndex: Int, totalVolumes: Int) -> String {
        guard totalVolumes > 1 else { return base }
        let pad = totalVolumes >= 10 ? 2 : 1
        return "\(base) [Vol.\(String(format: "%0\(pad)d", volumeIndex))]"
    }
}
