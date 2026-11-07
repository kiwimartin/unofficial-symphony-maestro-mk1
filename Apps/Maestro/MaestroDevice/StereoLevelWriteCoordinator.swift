import Foundation
import MaestroCore

public struct StereoLevelWrite: Sendable, Equatable {
    public let index: Int
    public let selector: AudioPropertySelector
    public let value: UInt32

    public init(index: Int, selector: AudioPropertySelector, value: UInt32) {
        self.index = index
        self.selector = selector
        self.value = value
    }
}

/// Serializes one pair's writes across asynchronous transport suspension.
/// A newer move replaces pending moves and supersedes the remaining writes of
/// an older move. Callers must send the complete desired L/R values for a move;
/// an initial alignment may deliberately contain only the louder channel.
@MainActor
public final class StereoLevelWriteCoordinator {
    public typealias Write = @MainActor (StereoLevelWrite) async throws -> Void
    public typealias Completion = @MainActor (Result<Void, any Error>) -> Void

    @MainActor
    private final class Request {
        let revision = UUID()
        let epoch: UUID
        let writes: [StereoLevelWrite]
        let write: Write
        let completion: Completion
        var completed = false

        init(epoch: UUID, writes: [StereoLevelWrite], write: @escaping Write,
             completion: @escaping Completion) {
            self.epoch = epoch
            self.writes = writes
            self.write = write
            self.completion = completion
        }
    }

    @MainActor
    private final class Lane {
        var epoch = UUID()
        var latestRevision: UUID?
        var pending: Request?
        var worker: Task<Void, Never>?
    }

    private var lanes: [String: Lane] = [:]

    public init() {}

    public func submit(key: String, writes: [StereoLevelWrite],
                       write: @escaping Write, completion: @escaping Completion) {
        let lane = lanes[key] ?? Lane()
        lanes[key] = lane
        let request = Request(epoch: lane.epoch, writes: writes, write: write,
                              completion: completion)
        let supersededPending = lane.pending
        // Commit the new state before invoking a completion: that callback may
        // submit another move or invalidate the entire coordinator reentrantly.
        lane.latestRevision = request.revision
        lane.pending = request
        if let supersededPending {
            finish(supersededPending, on: lane, result: .failure(CancellationError()))
        }
        guard lanes[key] === lane, lane.worker == nil, lane.pending != nil else { return }
        lane.worker = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.drain(key: key, lane: lane)
        }
    }

    /// Does not cancel or replace an in-flight worker. The underlying transport
    /// may finish its already-started write; no additional invalidated writes
    /// or completions follow. New work for the same key waits for that worker.
    public func invalidateAll() {
        for lane in lanes.values {
            lane.epoch = UUID()
            lane.latestRevision = nil
            lane.pending = nil
        }
        lanes = lanes.filter { $0.value.worker != nil }
    }

    private func isCurrent(_ request: Request, on lane: Lane) -> Bool {
        request.epoch == lane.epoch && request.revision == lane.latestRevision
    }

    private func finish(_ request: Request, on lane: Lane,
                        result: Result<Void, any Error>) {
        guard !request.completed else { return }
        request.completed = true
        // Invalidation suppresses stale UI updates, including cancellation.
        guard request.epoch == lane.epoch else { return }
        request.completion(result)
    }

    private func drain(key: String, lane: Lane) async {
        while let request = lane.pending {
            lane.pending = nil
            var failure: (any Error)?
            for item in request.writes {
                // Recheck after every awaited write. In particular, an old
                // left write can finish, but its obsolete right write must not
                // run after a newer pair's requested values have arrived.
                guard isCurrent(request, on: lane) else { break }
                do { try await request.write(item) }
                catch { failure = error; break }
            }
            if !isCurrent(request, on: lane) {
                finish(request, on: lane, result: .failure(CancellationError()))
            } else if let failure {
                finish(request, on: lane, result: .failure(failure))
            } else {
                finish(request, on: lane, result: .success(()))
            }
        }
        lane.worker = nil
        if lanes[key] === lane { lanes.removeValue(forKey: key) }
    }
}
