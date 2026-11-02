import Foundation
import Testing
@testable import Me2Press

@Suite("Comic workspace space")
struct ComicWorkspaceSpaceTests {
    @Test("Checks the actual output volume and warns below its estimated requirement")
    func actualVolume() throws {
        try TestFileSystem.withTemporaryDirectory { output in
            let needed = ComicWorkspaceSpace.estimatedBytes(volumeBytes: 100_000_000, parallelConversions: 2)
            var checkedURL: URL?
            let warning = ComicWorkspaceSpace.warning(in: output, volumeBytes: 100_000_000, parallelConversions: 2) {
                checkedURL = $0
                return needed - 1
            }
            #expect(checkedURL == output)
            #expect(warning != nil)
            #expect(ComicWorkspaceSpace.warning(in: output, volumeBytes: 100_000_000, parallelConversions: 2) { _ in needed } == nil)
        }
    }

    @Test("Unknown capacity does not stop conversion")
    func unknownCapacity() {
        let warning = ComicWorkspaceSpace.warning(in: URL(fileURLWithPath: "/missing"), volumeBytes: 1_000, parallelConversions: 1) { _ in nil }
        #expect(warning == nil)
    }

    @Test("Concurrent jobs and repeated covers contribute to the estimate")
    func concurrencyAndCover() {
        let bodyOnly = ComicWorkspaceSpace.estimatedBytes(volumeBytes: 100_000, parallelConversions: 1)
        let withCover = ComicWorkspaceSpace.estimatedBytes(volumeBytes: 120_000, parallelConversions: 1)
        #expect(withCover > bodyOnly)
        #expect(ComicWorkspaceSpace.estimatedBytes(volumeBytes: 120_000, parallelConversions: 3) == withCover * 3)
    }
}
