import Foundation

final class FakeBackend: AssertionBackend {
    var createFailure: AssertionKind?
    var releaseFailures: Set<UInt32> = []
    var created: [AssertionKind] = []
    var released: [UInt32] = []
    var live: Set<UInt32> = []
    private var nextID: UInt32 = 1

    func create(_ kind: AssertionKind) -> Result<UInt32, AssertionFailure> {
        created.append(kind)
        if createFailure == kind {
            return .failure(AssertionFailure(operation: .create, kind: kind, code: -1))
        }
        let id = nextID
        nextID += 1
        live.insert(id)
        return .success(id)
    }

    func release(_ assertion: OwnedAssertion) -> Result<Void, AssertionFailure> {
        released.append(assertion.id)
        if releaseFailures.contains(assertion.id) {
            return .failure(AssertionFailure(operation: .release, kind: assertion.kind, code: -2))
        }
        live.remove(assertion.id)
        return .success(())
    }
}

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

final class FakeVirtualDisplay: VirtualDisplayBackend {
    var unavailabilityReason: String?
    var hasResources = false
    var displayID: UInt32? { hasResources ? 42 : nil }
    var startFails = false
    var validateFails = false
    var stopFails = false
    var calls: [String] = []

    func start() -> Result<Void, VirtualDisplayFailure> {
        calls.append("start")
        hasResources = true
        return startFails ? .failure(VirtualDisplayFailure(description: "Setup refused.")) : .success(())
    }

    func validate() -> Result<Void, VirtualDisplayFailure> {
        calls.append("validate")
        return validateFails ? .failure(VirtualDisplayFailure(description: "Display is unusable.")) : .success(())
    }

    func stop() -> Result<Void, VirtualDisplayFailure> {
        calls.append("stop")
        guard !stopFails else { return .failure(VirtualDisplayFailure(description: "Cleanup pending.")) }
        hasResources = false
        return .success(())
    }
}

func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw CheckFailure(description: message) }
}

@main
struct SessionTests {
    static func main() throws {
        let tests: [(String, () throws -> Void)] = [
            ("launch defaults to off", {
                let backend = FakeBackend()
                let session = KeepAwakeSession(backend: backend)
                try check(session.state == .off && !session.hasAssertions, "Launch must be off.")
                try check(backend.created.isEmpty && backend.released.isEmpty, "Launch must not touch power assertions.")
            }),
            ("start and stop are idempotent", {
                let backend = FakeBackend()
                let session = KeepAwakeSession(backend: backend)
                session.start()
                session.start()
                try check(session.state == .on && backend.live.count == 2, "On requires both assertions.")
                try check(backend.created == [.system, .display], "Start must not duplicate assertions.")
                session.stop()
                session.stop()
                try check(backend.released == [2, 1], "Stop must release each assertion once, in reverse order.")
                try check(session.state == .off && backend.live.isEmpty, "Stop must clear ownership.")
            }),
            ("first creation failure leaves no assertion", {
                let backend = FakeBackend()
                backend.createFailure = .system
                let session = KeepAwakeSession(backend: backend)
                session.start()
                try check(session.state == .error && !session.hasAssertions, "Failure must not show On.")
                try check(backend.created == [.system] && backend.released.isEmpty, "Stop after the first failure.")
                try check(session.failures.count == 1, "Keep the creation error.")
            }),
            ("second creation failure rolls back", {
                let backend = FakeBackend()
                backend.createFailure = .display
                let session = KeepAwakeSession(backend: backend)
                session.start()
                try check(session.state == .error && backend.live.isEmpty, "Rollback must release the first assertion.")
                try check(backend.released == [1] && !session.hasAssertions, "Rollback must track released ownership.")
            }),
            ("rollback failure retains a retry handle", {
                let backend = FakeBackend()
                backend.createFailure = .display
                backend.releaseFailures = [1]
                let session = KeepAwakeSession(backend: backend)
                session.start()
                try check(session.state == .error && session.hasAssertions, "Failed cleanup must remain visible.")
                try check(session.failures.map(\.operation) == [.create, .release], "Keep both failure causes.")
                backend.releaseFailures = []
                session.toggle()
                try check(session.state == .off && backend.live.isEmpty, "A retry must release the retained handle.")
                try check(backend.created.count == 2, "Cleanup retry must not start a new session.")
            }),
            ("release continues after a partial failure", {
                let backend = FakeBackend()
                let session = KeepAwakeSession(backend: backend)
                session.start()
                backend.releaseFailures = [2]
                session.stop()
                try check(backend.released == [2, 1] && backend.live == [2], "Attempt every release.")
                try check(session.state == .error && session.failures.count == 1, "Report the failed release.")
                backend.releaseFailures = []
                session.stop()
                try check(backend.released == [2, 1, 2] && backend.live.isEmpty, "Retry only the remaining handle.")
                try check(session.state == .off && session.failures.isEmpty, "Successful cleanup clears the error.")
            }),
            ("start cannot compound failed cleanup", {
                let backend = FakeBackend()
                let session = KeepAwakeSession(backend: backend)
                session.start()
                backend.releaseFailures = [1, 2]
                session.stop()
                session.start()
                try check(backend.created.count == 2 && backend.live.count == 2, "Unreleased assertions must block creation.")
                backend.releaseFailures = []
                session.start()
                try check(session.state == .on && backend.live.count == 2, "Start can recover after cleanup.")
                try check(backend.created.count == 4, "Recovery must create one fresh pair.")
            }),
            ("a failed start can be retried", {
                let backend = FakeBackend()
                backend.createFailure = .system
                let session = KeepAwakeSession(backend: backend)
                session.toggle()
                backend.createFailure = nil
                session.toggle()
                try check(session.state == .on && session.failures.isEmpty, "A successful retry clears the error.")
                session.toggle()
                try check(session.state == .off && backend.live.isEmpty, "Toggle must release the new session.")
            }),
            ("deinitialization releases owned assertions", {
                let backend = FakeBackend()
                do {
                    let session = KeepAwakeSession(backend: backend)
                    session.start()
                }
                try check(backend.released == [2, 1] && backend.live.isEmpty, "Deinitialization must attempt cleanup.")
            }),
            ("deinitialization retries a failed release", {
                let backend = FakeBackend()
                do {
                    let session = KeepAwakeSession(backend: backend)
                    session.start()
                    backend.releaseFailures = [1]
                    session.stop()
                    backend.releaseFailures = []
                }
                try check(backend.released == [2, 1, 1] && backend.live.isEmpty, "Final cleanup must retain failed handles.")
            }),
            ("new sessions never restore an earlier state", {
                let backend = FakeBackend()
                do {
                    let session = KeepAwakeSession(backend: backend)
                    session.start()
                }
                let fresh = KeepAwakeSession(backend: backend)
                try check(fresh.state == .off && !fresh.hasAssertions, "A fresh session must start off.")
            }),
            ("mode selection stops an active screen session", {
                let backend = FakeBackend()
                let display = FakeVirtualDisplay()
                let session = KeepAwakeSession(backend: backend, virtualDisplay: display)
                try check(session.mode == .screen, "The default mode must be Keep Screen On.")
                session.start()
                try check(session.selectMode(.virtualDisplay), "Mode selection must succeed after cleanup.")
                try check(session.mode == .virtualDisplay && session.state == .off, "Switching must leave the new mode off.")
                try check(backend.live.isEmpty && display.calls.isEmpty, "Selection must not create a display.")
            }),
            ("failed assertion release blocks mode selection", {
                let backend = FakeBackend()
                let display = FakeVirtualDisplay()
                let session = KeepAwakeSession(backend: backend, virtualDisplay: display)
                session.start()
                backend.releaseFailures = [2]
                try check(!session.selectMode(.virtualDisplay), "An active assertion must block a mode change.")
                try check(session.mode == .screen && session.state == .error && display.calls.isEmpty, "Keep the old mode and do not create a virtual display.")
                backend.releaseFailures = []
                try check(session.selectMode(.virtualDisplay) && session.state == .off && !session.hasResources, "A later selection may finish cleanup and switch off.")
            }),
            ("virtual mode owns one display and one assertion pair", {
                let backend = FakeBackend()
                let display = FakeVirtualDisplay()
                let session = KeepAwakeSession(backend: backend, virtualDisplay: display)
                session.selectMode(.virtualDisplay)
                session.start()
                session.start()
                try check(session.state == .on && session.hasResources && session.virtualDisplayID == 42, "Virtual On requires owned resources.")
                try check(display.calls == ["start", "validate"] && backend.live.count == 2, "Start must verify one display and avoid duplicate resources.")
                session.stop()
                try check(session.state == .off && !session.hasResources && backend.live.isEmpty, "Stop must release both resource types.")
                try check(display.calls.last == "stop", "The owned display must be stopped.")
            }),
            ("unavailable virtual mode cannot be selected", {
                let backend = FakeBackend()
                let display = FakeVirtualDisplay()
                display.unavailabilityReason = "Unavailable on this runtime."
                let session = KeepAwakeSession(backend: backend, virtualDisplay: display)
                try check(!session.selectMode(.virtualDisplay) && session.mode == .screen, "Unavailable mode must stay unselected.")
                try check(session.virtualDisplayUnavailableReason != nil && display.calls.isEmpty, "Expose a reason without creating resources.")
            }),
            ("runtime unavailability never falls back silently", {
                let backend = FakeBackend()
                let display = FakeVirtualDisplay()
                let session = KeepAwakeSession(backend: backend, virtualDisplay: display)
                session.selectMode(.virtualDisplay)
                display.unavailabilityReason = "API unavailable."
                session.start()
                try check(session.state == .error && session.mode == .virtualDisplay, "Keep the selected mode and report its error.")
                try check(!session.errorMessages.isEmpty && backend.created.isEmpty && display.calls.isEmpty, "Unavailable startup must not acquire anything.")
            }),
            ("virtual creation failure rolls back partial ownership", {
                let backend = FakeBackend()
                let display = FakeVirtualDisplay()
                display.startFails = true
                let session = KeepAwakeSession(backend: backend, virtualDisplay: display)
                session.selectMode(.virtualDisplay)
                session.start()
                try check(session.state == .error && !session.hasResources, "Failed creation must not become On.")
                try check(display.calls == ["start", "stop"] && backend.created.isEmpty, "Failed creation must release the partial display before assertions.")
            }),
            ("unusable display is rejected before assertion creation", {
                let backend = FakeBackend()
                let display = FakeVirtualDisplay()
                display.validateFails = true
                let session = KeepAwakeSession(backend: backend, virtualDisplay: display)
                session.selectMode(.virtualDisplay)
                session.start()
                try check(session.state == .error && !session.hasResources, "Invalid readback must roll back.")
                try check(display.calls == ["start", "validate", "stop"] && backend.created.isEmpty, "Verify usability before acquiring assertions.")
            }),
            ("assertion failure tears down the virtual display", {
                let backend = FakeBackend()
                backend.createFailure = .display
                let display = FakeVirtualDisplay()
                let session = KeepAwakeSession(backend: backend, virtualDisplay: display)
                session.selectMode(.virtualDisplay)
                session.start()
                try check(session.state == .error && backend.live.isEmpty && !display.hasResources, "Release every resource after assertion failure.")
                try check(display.calls.last == "stop" && backend.released == [1], "Rollback must include the display and prior assertion.")
            }),
            ("failed virtual cleanup blocks mode changes", {
                let backend = FakeBackend()
                let display = FakeVirtualDisplay()
                let session = KeepAwakeSession(backend: backend, virtualDisplay: display)
                session.selectMode(.virtualDisplay)
                session.start()
                display.stopFails = true
                try check(!session.selectMode(.screen), "A mode change must wait for cleanup.")
                try check(session.state == .error && session.mode == .virtualDisplay && session.hasResources, "Retain the old mode and truthful cleanup error.")
                try check(backend.live.isEmpty, "Display cleanup failure must not prevent assertion release.")
                display.stopFails = false
                session.toggle()
                try check(session.state == .off && !session.hasResources, "Toggle must retry display cleanup.")
                try check(session.selectMode(.screen) && session.state == .off, "Switch only after cleanup succeeds.")
            }),
            ("runtime display loss releases all resources", {
                let backend = FakeBackend()
                let display = FakeVirtualDisplay()
                let session = KeepAwakeSession(backend: backend, virtualDisplay: display)
                session.selectMode(.virtualDisplay)
                session.start()
                display.validateFails = true
                session.validateResources()
                try check(session.state == .error && !session.hasResources && backend.live.isEmpty, "Runtime loss must stop the session.")
                try check(session.mode == .virtualDisplay && !session.errorMessages.isEmpty, "Do not silently enter screen mode.")
            }),
            ("deinitialization releases the virtual display", {
                let backend = FakeBackend()
                let display = FakeVirtualDisplay()
                do {
                    let session = KeepAwakeSession(backend: backend, virtualDisplay: display)
                    session.selectMode(.virtualDisplay)
                    session.start()
                }
                try check(!display.hasResources && backend.live.isEmpty && display.calls.last == "stop", "Final cleanup must include the virtual display.")
            })
        ]

        for (name, test) in tests {
            try test()
            print("PASS: \(name)")
        }
        print("Passed \(tests.count) session tests.")
    }
}
