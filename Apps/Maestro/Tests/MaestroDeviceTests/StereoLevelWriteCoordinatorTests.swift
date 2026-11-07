import Foundation
import Testing
import MaestroCore
@testable import MaestroDevice

@Suite("Serialized stereo level writes across transport awaits")
struct StereoLevelWriteCoordinatorTests {
    private enum WriteFailure: Error { case expected }

    private actor ControlledWriter {
        private let blockFirst: Bool
        private let failingValue: UInt32?
        private var gate: CheckedContinuation<Void, any Error>?
        private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
        private var events: [StereoLevelWrite] = []
        private var values: [Int: UInt32] = [:]
        private var active = 0
        private var maximumActive = 0
        private var didBlock = false

        init(blockFirst: Bool = false, failingValue: UInt32? = nil) {
            self.blockFirst = blockFirst
            self.failingValue = failingValue
        }

        func write(_ item: StereoLevelWrite) async throws {
            active += 1
            maximumActive = max(maximumActive, active)
            defer { active -= 1 }
            events.append(item)
            if blockFirst && !didBlock {
                didBlock = true
                try await withCheckedThrowingContinuation { continuation in
                    gate = continuation
                    notifyWaiters()
                }
            } else {
                notifyWaiters()
            }
            if item.value == failingValue { throw WriteFailure.expected }
            values[item.index] = item.value
        }

        func waitForWrites(_ count: Int) async {
            guard events.count < count else { return }
            await withCheckedContinuation { waiters.append((count, $0)) }
        }

        private func notifyWaiters() {
            let ready = waiters.filter { events.count >= $0.0 }
            waiters.removeAll { events.count >= $0.0 }
            for (_, waiter) in ready { waiter.resume() }
        }

        func releaseFirst() {
            let continuation = gate
            gate = nil
            continuation?.resume()
        }

        func snapshot() -> (events: [StereoLevelWrite], values: [Int: UInt32], maximumActive: Int) {
            (events, values, maximumActive)
        }
    }

    @MainActor
    private final class Completions {
        enum Outcome: Equatable { case success, cancelled, failed }
        private(set) var results: [String: Outcome] = [:]
        private(set) var errors: [String: any Error] = [:]
        private var waiters: [(String, CheckedContinuation<Void, Never>)] = []

        func record(_ key: String, _ result: Result<Void, any Error>) {
            switch result {
            case .success: results[key] = .success
            case .failure(let error):
                results[key] = error is CancellationError ? .cancelled : .failed
                errors[key] = error
            }
            let ready = waiters.filter { $0.0 == key }
            waiters.removeAll { $0.0 == key }
            for (_, waiter) in ready { waiter.resume() }
        }

        func waitFor(_ key: String) async {
            guard results[key] == nil else { return }
            await withCheckedContinuation { waiters.append((key, $0)) }
        }
    }

    private func pair(_ value: UInt32) -> [StereoLevelWrite] {
        [.init(index: 0, selector: .analogIOType, value: value),
         .init(index: 1, selector: .analogIOType, value: value)]
    }

    @Test @MainActor
    func newerMoveSkipsOldRightAndReplacesIntermediatePendingMove() async {
        let coordinator = StereoLevelWriteCoordinator()
        let writer = ControlledWriter(blockFirst: true)
        let completions = Completions()
        coordinator.submit(key: "output:0", writes: pair(1), write: { try await writer.write($0) },
                           completion: { completions.record("old", $0) })
        await writer.waitForWrites(1)
        coordinator.submit(key: "output:0", writes: pair(2), write: { try await writer.write($0) },
                           completion: { completions.record("middle", $0) })
        coordinator.submit(key: "output:0", writes: pair(3), write: { try await writer.write($0) },
                           completion: { completions.record("latest", $0) })
        await writer.releaseFirst()
        await completions.waitFor("latest")
        let snapshot = await writer.snapshot()
        #expect(snapshot.events == [pair(1)[0], pair(3)[0], pair(3)[1]])
        #expect(snapshot.values == [0: 3, 1: 3])
        #expect(snapshot.maximumActive == 1)
        #expect(completions.results == ["old": .cancelled, "middle": .cancelled, "latest": .success])
    }

    @Test @MainActor
    func transportFailureStopsItsPairAndDoesNotPoisonLaterMove() async {
        let coordinator = StereoLevelWriteCoordinator()
        let writer = ControlledWriter(failingValue: 7)
        let completions = Completions()
        coordinator.submit(key: "input:0", writes: pair(7), write: { try await writer.write($0) },
                           completion: { completions.record("failed", $0) })
        await completions.waitFor("failed")
        #expect(completions.results["failed"] == .failed)
        #expect(completions.errors["failed"] is WriteFailure)
        coordinator.submit(key: "input:0", writes: pair(8), write: { try await writer.write($0) },
                           completion: { completions.record("recovered", $0) })
        await completions.waitFor("recovered")
        let snapshot = await writer.snapshot()
        #expect(snapshot.events == [pair(7)[0], pair(8)[0], pair(8)[1]])
        #expect(snapshot.values == [0: 8, 1: 8])
        #expect(snapshot.maximumActive == 1)
        #expect(completions.results["recovered"] == .success)
    }

    @Test @MainActor
    func invalidateSuppressesOldCallbacksAndRetainsWorkerUntilInFlightWriteFinishes() async {
        let coordinator = StereoLevelWriteCoordinator()
        let writer = ControlledWriter(blockFirst: true)
        let completions = Completions()
        coordinator.submit(key: "output:0", writes: pair(1), write: { try await writer.write($0) },
                           completion: { completions.record("old", $0) })
        await writer.waitForWrites(1)
        coordinator.submit(key: "output:0", writes: pair(2), write: { try await writer.write($0) },
                           completion: { completions.record("discarded", $0) })
        coordinator.invalidateAll()
        coordinator.submit(key: "output:0", writes: pair(3), write: { try await writer.write($0) },
                           completion: { completions.record("new-session", $0) })
        // Allow a wrongly started replacement worker to enter the fake writer;
        // the first transport call remains held until explicitly released.
        await Task.yield()
        await writer.releaseFirst()
        await completions.waitFor("new-session")
        let snapshot = await writer.snapshot()
        #expect(snapshot.events == [pair(1)[0], pair(3)[0], pair(3)[1]])
        #expect(snapshot.values == [0: 3, 1: 3])
        #expect(snapshot.maximumActive == 1)
        #expect(completions.results == ["new-session": .success])
    }

    @Test @MainActor
    func completionCanSubmitAnotherMoveReentrantlyWithoutOverlappingWorkers() async {
        let coordinator = StereoLevelWriteCoordinator()
        let writer = ControlledWriter()
        let completions = Completions()
        let second = pair(5)
        coordinator.submit(key: "output:0", writes: pair(4), write: { try await writer.write($0) },
                           completion: { result in
            completions.record("first", result)
            coordinator.submit(key: "output:0", writes: second, write: { try await writer.write($0) },
                               completion: { completions.record("second", $0) })
        })
        await completions.waitFor("second")
        let snapshot = await writer.snapshot()
        #expect(snapshot.events == pair(4) + pair(5))
        #expect(snapshot.values == [0: 5, 1: 5])
        #expect(snapshot.maximumActive == 1)
        #expect(completions.results == ["first": .success, "second": .success])
    }
}
