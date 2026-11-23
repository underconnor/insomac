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
    let validationFailure: (Int) -> VirtualDisplayFailure?
    private var validationCount = 0
    var hasResources = false
    var unavailabilityReason: String? { nil }
    var displayID: UInt32? { hasResources ? 42 : nil }

    init(trace: CoordinatorTrace, startDelay: TimeInterval, failStart: Bool,
         validationFailure: @escaping (Int) -> VirtualDisplayFailure?) {
        self.trace = trace
        self.startDelay = startDelay
        self.failStart = failStart
        self.validationFailure = validationFailure
    }

    func start() -> Result<Void, VirtualDisplayFailure> {
        trace.record("display.start", delay: startDelay)
        hasResources = true
        return failStart ? .failure(VirtualDisplayFailure(description: "Deliberate startup failure.")) : .success(())
    }

    func validate() -> Result<Void, VirtualDisplayFailure> {
        trace.record("display.validate", delay: 0.02)
        validationCount += 1
        if let failure = validationFailure(validationCount) { return .failure(failure) }
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
    nonisolated private static let transient = VirtualDisplayFailure(description: "Display metadata is temporarily unavailable.",
                                                                     canRetryTopology: true)

    static func main() async throws {
        try await testResponsiveQueuedStop()
        try await testFailedStartDoesNotTurnOffIntoRetry()
        try await testOrderedModeChanges()
        try await testValidationCoalescing()
        try await testTransientValidationRecovers()
        try await testPersistentValidationEndsDespiteNotifications()
        try await testTerminalValidationDoesNotRetry()
        try await testCleanupCancelsDelayedValidation()
        try await testQuitDuringActivation()
        try await testQuitDeadline()
    }

    private static func makeCoordinator(trace: CoordinatorTrace, delay: TimeInterval = 0.25,
                                        failStart: Bool = false, quitTimeout: TimeInterval = 2,
                                        validationGracePeriod: TimeInterval = 2,
                                        validationFailure: @escaping @Sendable (Int) -> VirtualDisplayFailure? = { _ in nil }
    ) -> SessionCoordinator {
        SessionCoordinator(terminationTimeout: quitTimeout, validationGracePeriod: validationGracePeriod) {
            KeepAwakeSession(backend: CoordinatorAssertions(trace: trace),
                virtualDisplay: SlowCoordinatorDisplay(trace: trace, startDelay: delay, failStart: failStart,
                                                       validationFailure: validationFailure))
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

    private static func testTransientValidationRecovers() async throws {
        let trace = CoordinatorTrace()
        let coordinator = makeCoordinator(trace: trace, delay: 0) { count in
            count == 2 ? transient : nil
        }
        try await readyVirtual(coordinator)
        coordinator.toggle()
        try await waitUntil { !coordinator.snapshot.isBusy }
        var checkingUpdates = 0
        coordinator.onChange = { snapshot in
            if snapshot.activity == .validating { checkingUpdates += 1 }
        }
        coordinator.validateResources()
        try await waitUntil { checkingUpdates >= 2 }
        try check(coordinator.snapshot.activity == .validating && coordinator.snapshot.hasResources
            && coordinator.snapshot.errorMessages.isEmpty, "Keep resources and show Checking while waiting for topology.")
        for _ in 0..<200 { coordinator.validateResources() }
        try await waitUntil { !coordinator.snapshot.isBusy }
        try check(coordinator.snapshot.state == .on && coordinator.snapshot.hasResources
            && coordinator.snapshot.errorMessages.isEmpty, "A successful retry must return to On.")
        let events = trace.events
        try check(events.filter { $0 == "display.validate" }.count == 3
            && events.filter { $0 == "display.start" }.count == 1
            && !events.contains { $0 == "display.stop" || $0.hasPrefix("release.") },
            "Recovery must keep the original owner and assertions, with one retry for the notification burst.")
        try check(trace.remainedSerialAndOffMain, "Every topology check must stay on the serial background executor.")
        try await quit(coordinator)
        print("PASS: transient topology recovers with the original owner and assertions")
    }

    private static func testPersistentValidationEndsDespiteNotifications() async throws {
        let trace = CoordinatorTrace()
        let coordinator = makeCoordinator(trace: trace, delay: 0, validationGracePeriod: 0.25) { count in
            count > 1 ? transient : nil
        }
        try await readyVirtual(coordinator)
        coordinator.toggle()
        try await waitUntil { !coordinator.snapshot.isBusy }
        coordinator.validateResources()
        let timeout = ProcessInfo.processInfo.systemUptime + 1.5
        while coordinator.snapshot.isBusy {
            try check(ProcessInfo.processInfo.systemUptime < timeout, "New notifications must not extend the retry deadline.")
            coordinator.validateResources()
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        try check(coordinator.snapshot.state == .error && !coordinator.snapshot.hasResources
            && coordinator.snapshot.errorMessages == [transient.description], "Expired recovery must expose the error and clean up.")
        try check(trace.events.filter { $0 == "display.validate" }.count >= 3
            && trace.events.filter { $0 == "display.stop" }.count == 1
            && trace.events.filter { $0.hasPrefix("release.") }.count == 2,
            "Persistent loss must retry before releasing the owned resources once.")
        try await quit(coordinator)
        print("PASS: persistent topology loss runs one bounded window and cleans up despite new notifications")
    }

    private static func testTerminalValidationDoesNotRetry() async throws {
        let trace = CoordinatorTrace()
        let ownerLost = VirtualDisplayFailure(description: "Owner exited.")
        let coordinator = makeCoordinator(trace: trace, delay: 0) { count in
            count > 1 ? ownerLost : nil
        }
        try await readyVirtual(coordinator)
        coordinator.toggle()
        try await waitUntil { !coordinator.snapshot.isBusy }
        coordinator.validateResources()
        try await waitUntil { !coordinator.snapshot.isBusy }
        try check(coordinator.snapshot.state == .error && !coordinator.snapshot.hasResources
            && coordinator.snapshot.errorMessages == [ownerLost.description], "Owner loss must proceed directly to cleanup.")
        try check(trace.events.filter { $0 == "display.validate" }.count == 2, "Terminal failures must not retry.")
        try await quit(coordinator)
        print("PASS: terminal validation failures bypass the topology retry window")
    }

    private static func testCleanupCancelsDelayedValidation() async throws {
        for quitDuringRetry in [false, true] {
            let trace = CoordinatorTrace()
            let coordinator = makeCoordinator(trace: trace, delay: 0) { count in
                count == 2 ? transient : nil
            }
            try await readyVirtual(coordinator)
            coordinator.toggle()
            try await waitUntil { !coordinator.snapshot.isBusy }
            var checkingUpdates = 0
            coordinator.onChange = { snapshot in
                if snapshot.activity == .validating { checkingUpdates += 1 }
            }
            coordinator.validateResources()
            try await waitUntil { checkingUpdates >= 2 }
            if quitDuringRetry {
                try await quit(coordinator)
            } else {
                coordinator.toggle()
                try await waitUntil { !coordinator.snapshot.isBusy }
            }
            try check(coordinator.snapshot.state == .off && !coordinator.snapshot.hasResources,
                      "Off or Quit must clean up without waiting on the topology grace period.")
            if !quitDuringRetry {
                coordinator.toggle()
                try await waitUntil { !coordinator.snapshot.isBusy && coordinator.snapshot.state == .on }
            }
            try await Task.sleep(nanoseconds: 160_000_000)
            try check(trace.events.filter { $0 == "display.validate" }.count == (quitDuringRetry ? 2 : 3)
                && trace.events.filter { $0 == "display.stop" }.count == 1,
                "A cancelled retry must not run again after cleanup or check a later session.")
            if !quitDuringRetry { try await quit(coordinator) }
        }
        print("PASS: Off and Quit cancel scheduled revalidation and clean up once")
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
