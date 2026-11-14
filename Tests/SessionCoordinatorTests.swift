import Foundation

private struct CoordinatorFailure: Error, CustomStringConvertible {
    let description: String
}

private final class CoordinatorTrace: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    private var active = 0
    private var maximumActive = 0
    private var mainThreadCalls = 0

    func record(_ name: String, delay: TimeInterval = 0) {
        lock.withLock {
            recorded.append(name)
            active += 1
            maximumActive = max(maximumActive, active)
            if Thread.isMainThread { mainThreadCalls += 1 }
        }
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        lock.withLock { active -= 1 }
    }

    var events: [String] { lock.withLock { recorded } }
    var remainedSerialAndOffMain: Bool { lock.withLock { maximumActive == 1 && mainThreadCalls == 0 } }
}

private final class CoordinatorAssertions: AssertionBackend {
    let trace: CoordinatorTrace
    private var nextID: UInt32 = 0

    init(trace: CoordinatorTrace) { self.trace = trace }

    func create(_ kind: AssertionKind) -> Result<UInt32, AssertionFailure> {
        trace.record("create.\(kind.rawValue)")
        nextID += 1
        return .success(nextID)
    }

    func release(_ assertion: OwnedAssertion) -> Result<Void, AssertionFailure> {
        trace.record("release.\(assertion.kind.rawValue)")
        return .success(())
    }
}

private final class SlowCoordinatorDisplay: VirtualDisplayBackend {
    let trace: CoordinatorTrace
    let startDelay: TimeInterval
    let failStart: Bool
    var hasResources = false
    var unavailabilityReason: String? { nil }
    var displayID: UInt32? { hasResources ? 42 : nil }

    init(trace: CoordinatorTrace, startDelay: TimeInterval, failStart: Bool) {
        self.trace = trace
        self.startDelay = startDelay
        self.failStart = failStart
    }

    func start() -> Result<Void, VirtualDisplayFailure> {
        trace.record("display.start", delay: startDelay)
        hasResources = true
        return failStart ? .failure(VirtualDisplayFailure(description: "Deliberate startup failure.")) : .success(())
    }

    func validate() -> Result<Void, VirtualDisplayFailure> {
        trace.record("display.validate", delay: 0.02)
        return .success(())
    }

    func stop() -> Result<Void, VirtualDisplayFailure> {
        trace.record("display.stop", delay: 0.02)
        hasResources = false
        return .success(())
    }
}

@main
@MainActor
struct SessionCoordinatorTests {
    static func main() async throws {
        try await testResponsiveQueuedStop()
        try await testFailedStartDoesNotTurnOffIntoRetry()
        try await testOrderedModeChanges()
        try await testValidationCoalescing()
        try await testQuitDuringActivation()
        try await testQuitDeadline()
    }

    private static func makeCoordinator(trace: CoordinatorTrace, delay: TimeInterval = 0.25,
                                        failStart: Bool = false, quitTimeout: TimeInterval = 2) -> SessionCoordinator {
        SessionCoordinator(terminationTimeout: quitTimeout) {
            KeepAwakeSession(backend: CoordinatorAssertions(trace: trace),
                virtualDisplay: SlowCoordinatorDisplay(trace: trace, startDelay: delay, failStart: failStart))
        }
    }

    private static func readyVirtual(_ coordinator: SessionCoordinator) async throws {
        try await waitUntil { !coordinator.snapshot.isBusy }
        coordinator.selectMode(.virtualDisplay)
        try await waitUntil { !coordinator.snapshot.isBusy && coordinator.snapshot.mode == .virtualDisplay }
    }

    private static func testResponsiveQueuedStop() async throws {
        let trace = CoordinatorTrace()
        let coordinator = makeCoordinator(trace: trace)
        try await readyVirtual(coordinator)
        let started = ProcessInfo.processInfo.systemUptime
        coordinator.toggle()
        try check(ProcessInfo.processInfo.systemUptime - started < 0.15, "Starting must return to the main actor promptly.")
        var heartbeat = false
        DispatchQueue.main.async { heartbeat = true }
        try await Task.sleep(nanoseconds: 20_000_000)
        try check(heartbeat && coordinator.snapshot.isBusy, "Main-queue work must run while the backend is deliberately slow.")
        coordinator.toggle()
        try check(!coordinator.snapshot.requestedOn, "A second click during activation must request Off.")
        try await waitUntil { !coordinator.snapshot.isBusy }
        try check(coordinator.snapshot.state == .off && !coordinator.snapshot.hasResources, "Queued Off must release the completed activation.")
        try check(trace.events.filter { $0 == "display.start" }.count == 1
            && trace.events.filter { $0 == "display.stop" }.count == 1, "Off must not start another owner.")
        try check(trace.remainedSerialAndOffMain, "All backend operations must share one background executor.")
        try await quit(coordinator)
        print("PASS: slow activation leaves main responsive and preserves queued Off")
    }

    private static func testFailedStartDoesNotTurnOffIntoRetry() async throws {
        let trace = CoordinatorTrace()
        let coordinator = makeCoordinator(trace: trace, failStart: true)
        try await readyVirtual(coordinator)
        coordinator.toggle()
        coordinator.toggle()
        try await waitUntil { !coordinator.snapshot.isBusy }
        try check(trace.events.filter { $0 == "display.start" }.count == 1, "Off after failed startup must not retry startup.")
        try check(coordinator.snapshot.state == .off && coordinator.snapshot.errorMessages.isEmpty
            && !coordinator.snapshot.hasResources, "Explicit Off must clear startup errors after rollback.")
        try await quit(coordinator)
        print("PASS: queued Off after failed activation clears errors without restarting")
    }

    private static func testOrderedModeChanges() async throws {
        let trace = CoordinatorTrace()
        let coordinator = makeCoordinator(trace: trace, delay: 0.05)
        try await waitUntil { !coordinator.snapshot.isBusy }
        coordinator.selectMode(.virtualDisplay)
        coordinator.toggle()
        coordinator.stop()
        coordinator.selectMode(.screen)
        coordinator.toggle()
        try await waitUntil { !coordinator.snapshot.isBusy }
        try check(coordinator.snapshot.mode == .screen && coordinator.snapshot.state == .on,
                  "Mode selection, activation, stop, and later activation must retain request order.")
        let events = trace.events
        guard let stopped = events.firstIndex(of: "display.stop"), let lastCreate = events.lastIndex(of: "create.PreventUserIdleSystemSleep") else {
            throw CoordinatorFailure(description: "Expected both sessions in the trace.")
        }
        try check(stopped < lastCreate && trace.remainedSerialAndOffMain, "Virtual cleanup must precede physical-mode activation.")
        try await quit(coordinator)
        print("PASS: rapid mode and activity requests execute serially in accepted order")
    }

    private static func testValidationCoalescing() async throws {
        let trace = CoordinatorTrace()
        let coordinator = makeCoordinator(trace: trace, delay: 0)
        try await readyVirtual(coordinator)
        coordinator.toggle()
        try await waitUntil { !coordinator.snapshot.isBusy }
        let before = trace.events.filter { $0 == "display.validate" }.count
        for _ in 0..<200 { coordinator.validateResources() }
        try await waitUntil { !coordinator.snapshot.isBusy }
        let extra = trace.events.filter { $0 == "display.validate" }.count - before
        try check(extra > 0 && extra <= 2, "A notification flood must create at most one in-flight and one pending validation.")
        try await quit(coordinator)
        print("PASS: notification floods coalesce without concurrent validation")
    }

    private static func testQuitDuringActivation() async throws {
        let trace = CoordinatorTrace()
        let coordinator = makeCoordinator(trace: trace)
        try await readyVirtual(coordinator)
        coordinator.toggle()
        var replies = 0
        coordinator.prepareToQuit { result in
            if case .completed(let snapshot) = result, snapshot.state == .off && !snapshot.hasResources { replies += 1 }
        }
        try await waitUntil { replies == 1 }
        try check(trace.events.last == "display.stop" && trace.remainedSerialAndOffMain,
                  "Quit during activation must await the same executor's cleanup.")
        try check(!coordinator.toggle(), "New activation must be refused once Quit is accepted.")
        print("PASS: Quit during activation waits for serialized cleanup and replies once")
    }

    private static func testQuitDeadline() async throws {
        let trace = CoordinatorTrace()
        let coordinator = makeCoordinator(trace: trace, delay: 0.25, quitTimeout: 0.04)
        try await readyVirtual(coordinator)
        coordinator.toggle()
        var replies = 0
        var timedOut = false
        let started = ProcessInfo.processInfo.systemUptime
        coordinator.prepareToQuit { result in
            replies += 1
            if case .timedOut = result { timedOut = true }
        }
        try await waitUntil { replies == 1 }
        try check(timedOut && ProcessInfo.processInfo.systemUptime - started < 0.2,
                  "A blocked backend must not prevent the main actor's bounded Quit reply.")
        try await waitUntil { !coordinator.snapshot.isBusy && coordinator.snapshot.state == .off }
        try check(replies == 1 && !coordinator.snapshot.hasResources, "Late cleanup must finish without a second termination reply.")
        print("PASS: Quit deadline remains responsive while late cleanup finishes once")
    }

    private static func quit(_ coordinator: SessionCoordinator) async throws {
        var finished = false
        coordinator.prepareToQuit { _ in finished = true }
        try await waitUntil { finished }
    }

    private static func waitUntil(_ predicate: () -> Bool, timeout: TimeInterval = 3) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while !predicate() {
            try check(ProcessInfo.processInfo.systemUptime < deadline, "Timed out waiting for coordinator state.")
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    private static func check(_ condition: Bool, _ description: String) throws {
        if !condition { throw CoordinatorFailure(description: description) }
    }
}
