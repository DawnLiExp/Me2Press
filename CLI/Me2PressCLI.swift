import Foundation

nonisolated private struct ComicRequest: Decodable, Sendable {
    let settings: ComicCLISettings
    let jobs: [ComicRequestJob]
}

nonisolated private struct ComicRequestJob: Decodable, Sendable {
    let id: String
    let input: String
    let output: String
    let readingDirection: String?
}

nonisolated private struct JobResult: Encodable, Sendable {
    let id: String
    var status = "pending"
    var outputs: [String] = []
    var warnings: [String] = []
    var error: String?
}

nonisolated private struct Message: Encodable {
    let event: String
    var id: String?
    var stage: String?
    var result: JobResult?
    var results: [JobResult]?
}

private actor Reporter {
    private var results: [String: JobResult]
    private var stages: [String: String] = [:]
    private let order: [String]
    private let ids: [String: String]

    init(jobs: [ComicRequestJob]) {
        order = jobs.map(\.id)
        results = Dictionary(uniqueKeysWithValues: jobs.map { ($0.id, JobResult(id: $0.id)) })
        ids = Dictionary(uniqueKeysWithValues: jobs.map { (URL(fileURLWithPath: $0.input).path, $0.id) })
    }

    func receive(source: URL, event: ConversionEvent) {
        guard let id = ids[source.path] else { return }
        switch event {
        case .itemStarted:
            results[id]?.status = "running"
            CLIOutput.emit(Message(event: "job_started", id: id))
        case .progress(_, let step), .simulation(_, _, let step, _):
            // The GUI may animate simulated percentages; the CLI only reports the real stage.
            if stages[id] != step {
                stages[id] = step
                CLIOutput.emit(Message(event: "progress", id: id, stage: step))
            }
        case .outputCreated(let url):
            results[id]?.outputs.append(url.path)
        case .itemSucceeded:
            results[id]?.status = "succeeded"
            CLIOutput.emit(Message(event: "job_result", id: id, result: results[id]))
        case .itemFailed(_, _, let error, _):
            results[id]?.status = "failed"
            results[id]?.error = error
            CLIOutput.emit(Message(event: "job_result", id: id, result: results[id]))
        case .log(let level, let message):
            if case .warn = level { results[id]?.warnings.append(message) }
            CLIOutput.diagnostic("[\(id)] \(message)")
        default: break
        }
    }

    func finish(cancelled: Bool) -> Int32 {
        for id in order where results[id]?.status == "pending" || results[id]?.status == "running" {
            results[id]?.status = cancelled ? "cancelled" : "failed"
            results[id]?.error = cancelled ? "Cancelled" : "Job did not finish"
        }
        let ordered = order.compactMap { results[$0] }
        CLIOutput.emit(Message(event: "summary", results: ordered))
        return cancelled ? 130 : ordered.allSatisfy { $0.status == "succeeded" } ? 0 : 1
    }
}

@main
struct Me2PressCLI {
    static func main() async {
        await CLIOutput.run { await execute() }
    }

    private static func execute() async -> Int32 {
        do {
            switch CommandLine.arguments.dropFirst().first {
            case "--help", "-h", nil:
                print("me2press-cli settings | comic --request request.json | --version\nSee docs/CLI.md for the JSON contract.")
                return 0
            case "--version":
                CLIOutput.version(tool: "me2press-cli")
                return 0
            case "settings":
                CLIOutput.emit(ComicCLISettings.load(defaults: try CLIOutput.appDefaults("me2.Me2Press")))
                return 0
            default: break
            }
            let path = try CLIOutput.requestPath(command: "comic")
            let request = try JSONDecoder().decode(ComicRequest.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
            try request.settings.validate()
            guard !request.jobs.isEmpty, Set(request.jobs.map(\.id)).count == request.jobs.count,
                  Set(request.jobs.map { URL(fileURLWithPath: $0.input).path }).count == request.jobs.count else {
                throw CLIRequestError("Provide nonempty jobs with unique ids and input directories.")
            }
            let jobs: [ConversionJob] = try request.jobs.map { job in
                guard let direction = ComicReadingDirection(rawValue: job.readingDirection ?? request.settings.readingDirection) else {
                    throw CLIRequestError("Invalid readingDirection for \(job.id).")
                }
                return .comic(ComicConversionJob(
                    sourceFolderURL: URL(fileURLWithPath: job.input),
                    authorName: request.settings.authorName,
                    kindlegenURL: URL(fileURLWithPath: request.settings.kindlegenPath),
                    parallelConversions: min(request.jobs.count, request.settings.maxConcurrency),
                    readingDirection: direction, outputDirectoryURL: URL(fileURLWithPath: job.output)
                ))
            }
            let reporter = Reporter(jobs: request.jobs)
            await ConversionCoordinator().runBatch(
                jobs: jobs, maxConcurrency: request.settings.maxConcurrency,
                jobEventSink: { source, event in await reporter.receive(source: source, event: event) },
                eventSink: { _ in }
            )
            return await reporter.finish(cancelled: Task.isCancelled)
        } catch {
            CLIOutput.emit(["event": "error", "error": error.localizedDescription])
            return 2
        }
    }
}
