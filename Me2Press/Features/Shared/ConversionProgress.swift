//
//  ConversionProgress.swift
//  Me2Press
//
//  Observable progress state shared by all three conversion pipelines.
//  Sequential mode (isConcurrent = false): value is driven by set(local:step:) with
//  fine-grained per-step mapping. Concurrent mode (isConcurrent = true): value advances
//  in whole-file increments via markFileCompleted(); set(local:step:) only updates the
//  step label to avoid out-of-order writes from parallel tasks.
//

import Foundation

/// Tracks batch conversion progress. Each ViewModel owns one instance; ConversionProgressView observes it directly.
@MainActor
@Observable
final class ConversionProgress {
    // MARK: - Public state

    /// Overall batch progress, 0.0 – 1.0.
    var value: Double = 0
    /// Human-readable label for the current pipeline step.
    var step: String = ""
    /// 1-based index of the file currently being processed.
    var fileIndex: Int = 0
    /// Total number of files in this batch.
    var totalFiles: Int = 0
    /// Display name of the file currently being processed (no extension).
    var currentFileName: String = ""
    /// Briefly true when all files complete, driving the ✅ animation.
    var isCompleted: Bool = false
    /// Non-empty only during multi-volume comic conversion, e.g. "Vol.1 / 3".
    var volumeLabel: String = ""

    // MARK: - Concurrent mode

    /// When true, `value` is driven by `markFileCompleted()` in whole-file steps.
    /// Set explicitly by the ViewModel after `beginBatch(totalFiles:)`.
    var isConcurrent: Bool = false

    /// Number of files completed so far (concurrent mode only).
    private(set) var completedCount: Int = 0

    // MARK: - Private

    private var simulationTask: Task<Void, Never>?

    // MARK: - Batch lifecycle

    func beginBatch(totalFiles count: Int) {
        cancelSimulation()
        totalFiles = count
        fileIndex = 0
        completedCount = 0
        value = 0
        step = ""
        currentFileName = ""
        volumeLabel = ""
        isCompleted = false
        isConcurrent = false // ViewModel overrides this after calling beginBatch
    }

    func beginFile(index: Int, name: String) {
        fileIndex = index
        currentFileName = name
        volumeLabel = ""
        // IMPORTANT: skip value update in concurrent mode — multiple tasks call beginFile
        // concurrently and would overwrite each other's progress out of order.
        if !isConcurrent {
            let span = totalFiles > 0 ? 1.0 / Double(totalFiles) : 1.0
            let base = Double(index - 1) * span
            value = base
        }
    }

    func reset() {
        beginBatch(totalFiles: 0)
    }

    // MARK: - Step progress (sequential mode only)

    /// Updates progress using a local fraction (0–1) within the current file's slice.
    /// In concurrent mode, only the step label is updated; value is left unchanged
    /// to prevent parallel tasks from overwriting each other's progress.
    func set(local: Double, step: String) {
        self.step = step
        guard !isConcurrent, totalFiles > 0 else { return }
        let span = 1.0 / Double(totalFiles)
        let base = Double(fileIndex - 1) * span
        value = min(1.0, max(0.0, base + span * local))
    }

    // MARK: - Completed count (concurrent mode only)

    /// Marks one file as finished (success or failure) and advances the progress ring
    /// by one whole-file step. Only called from the TaskGroup convergence point.
    func markFileCompleted(name: String) {
        guard isConcurrent else { return }
        completedCount = min(totalFiles, completedCount + 1)
        currentFileName = name
        value = totalFiles > 0 ? Double(completedCount) / Double(totalFiles) : 1
    }

    // MARK: - Black-box simulation (sequential mode only)

    /// Starts an asymptotic progress simulation for opaque steps such as ZIP packing
    /// or kindlegen conversion where real progress cannot be observed.
    ///
    /// The simulation uses `localP = localTo - (localTo - localFrom) * exp(-rate * t)`,
    /// which approaches `localTo` without ever reaching it, guaranteeing the step
    /// never overshoots before the real completion event cancels the task.
    ///
    /// In concurrent mode, this is a no-op: returns an empty Task without starting
    /// a timer, because progress is driven by completion counts instead.
    @discardableResult
    func startSimulation(
        from localFrom: Double,
        to localTo: Double,
        step: String,
        rate: Double
    ) -> Task<Void, Never> {
        if isConcurrent {
            self.step = step
            return Task {}
        }

        simulationTask?.cancel()

        let capturedIndex = fileIndex
        let capturedTotal = totalFiles
        let startTime = Date()

        let task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let elapsed = Date().timeIntervalSince(startTime)
                let localP = localTo - (localTo - localFrom) * exp(-rate * elapsed)
                if self.fileIndex == capturedIndex, self.totalFiles == capturedTotal {
                    self.set(local: localP, step: step)
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        simulationTask = task
        return task
    }

    func cancelSimulation() {
        simulationTask?.cancel()
        simulationTask = nil
    }
}
