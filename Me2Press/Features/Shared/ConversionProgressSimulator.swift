//
//  ConversionProgressSimulator.swift
//  Me2Press
//
//  Drives asymptotic progress simulation for opaque sequential conversion steps.
//

import Foundation

@MainActor
final class ConversionProgressSimulator {
    private let clock = ContinuousClock()
    private var task: Task<Void, Never>?

    func start(
        on progress: ConversionProgress,
        from localFrom: Double,
        to localTo: Double,
        step: String,
        rate: Double
    ) {
        cancel()

        if progress.isConcurrent {
            progress.step = step
            return
        }

        let capturedBatch = progress.batchSequence
        let capturedFile = progress.fileSequence
        let startTime = clock.now

        task = Task { @MainActor [weak progress, clock] in
            while !Task.isCancelled {
                guard let progress else { return }
                guard progress.batchSequence == capturedBatch, progress.fileSequence == capturedFile else {
                    return
                }

                let elapsed = Self.seconds(from: startTime.duration(to: clock.now))
                let localProgress = localTo - (localTo - localFrom) * exp(-rate * elapsed)
                progress.set(local: localProgress, step: step)

                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch {
                    return
                }
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    private nonisolated static func seconds(from duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
