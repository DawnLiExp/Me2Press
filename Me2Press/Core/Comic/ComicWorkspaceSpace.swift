import Foundation

enum ComicWorkspaceSpace {
    /// Image copies, stored EPUB and combined MOBI coexist until a volume completes.
    /// This is an advisory estimate, not a reservation or a conversion limit.
    nonisolated static func estimatedBytes(volumeBytes: Int, parallelConversions: Int) -> Int64 {
        (Int64(volumeBytes) * 4 + 16 * 1024 * 1024) * Int64(max(1, parallelConversions))
    }

    nonisolated static func availableBytes(at directory: URL) -> Int64? {
        try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
    }

    nonisolated static func warning(
        in directory: URL,
        volumeBytes: Int,
        parallelConversions: Int,
        capacity: (URL) -> Int64? = availableBytes
    ) -> String? {
        let required = estimatedBytes(volumeBytes: volumeBytes, parallelConversions: parallelConversions)
        guard let available = capacity(directory), available < required else { return nil }
        let freeText = ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
        let requiredText = ByteCountFormatter.string(fromByteCount: required, countStyle: .file)
        return String(localized: "warning.comic_space \(freeText) \(requiredText)")
    }
}
