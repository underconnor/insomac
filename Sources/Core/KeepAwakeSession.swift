import Foundation

enum AssertionKind: String, CaseIterable {
    case system = "PreventUserIdleSystemSleep"
    case display = "PreventUserIdleDisplaySleep"
}

struct OwnedAssertion: Equatable {
    let id: UInt32
    let kind: AssertionKind
}

struct AssertionFailure: Error, Equatable, CustomStringConvertible {
    enum Operation: String {
        case create
        case release
    }

    let operation: Operation
    let kind: AssertionKind
    let code: Int32

    var description: String {
        let status = String(UInt32(bitPattern: code), radix: 16, uppercase: true)
        return "Could not \(operation.rawValue) \(kind.rawValue) (0x\(status))."
    }
}

protocol AssertionBackend: AnyObject {
    func create(_ kind: AssertionKind) -> Result<UInt32, AssertionFailure>
    func release(_ assertion: OwnedAssertion) -> Result<Void, AssertionFailure>
}

enum SessionState: String, Sendable {
    case off = "Off"
    case on = "On"
    case error = "Error"
}

final class KeepAwakeSession {
    private let backend: any AssertionBackend
    private let virtualDisplay: (any VirtualDisplayBackend)?
    private var assertions: [OwnedAssertion] = []

    private(set) var state: SessionState = .off
    private(set) var failures: [AssertionFailure] = []
    private(set) var displayFailures: [VirtualDisplayFailure] = []
    private(set) var mode: KeepAwakeMode = .screen

    var hasAssertions: Bool { !assertions.isEmpty }
    var hasResources: Bool { hasAssertions || virtualDisplay?.hasResources == true }
    var errorMessages: [String] { failures.map(\.description) + displayFailures.map(\.description) }
    var virtualDisplayID: UInt32? { virtualDisplay?.displayID }
    var virtualDisplayUnavailableReason: String? {
        guard let virtualDisplay else { return "Virtual display support is unavailable in this build." }
        return virtualDisplay.unavailabilityReason
    }

    init(backend: any AssertionBackend, virtualDisplay: (any VirtualDisplayBackend)? = nil) {
        self.backend = backend
        self.virtualDisplay = virtualDisplay
    }

    @discardableResult
    func selectMode(_ newMode: KeepAwakeMode) -> Bool {
        guard newMode != mode else { return true }
        guard newMode != .virtualDisplay || virtualDisplayUnavailableReason == nil else { return false }
        stop()
        guard !hasResources, state == .off else { return false }
        mode = newMode
        return true
    }

    func toggle() {
        if hasResources {
            stop()
        } else {
            start()
        }
    }

    func start() {
        guard state != .on else { return }
        if hasResources {
            stop()
            guard !hasResources else { return }
        }

        failures = []
        displayFailures = []
        if mode == .virtualDisplay {
            guard let virtualDisplay, virtualDisplayUnavailableReason == nil else {
                displayFailures = [VirtualDisplayFailure(description:
                    (virtualDisplayUnavailableReason ?? "Virtual display support is unavailable.")
                    + " Choose Keep Screen On instead.")]
                state = .error
                return
            }
            let result = virtualDisplay.start().flatMap { virtualDisplay.validate() }
            if case .failure(let failure) = result {
                displayFailures.append(failure)
                releaseAll()
                state = .error
                return
            }
        }
        for kind in AssertionKind.allCases {
            switch backend.create(kind) {
            case .success(let id):
                assertions.append(OwnedAssertion(id: id, kind: kind))
            case .failure(let failure):
                failures.append(failure)
                releaseAll()
                state = .error
                return
            }
        }
        state = .on
    }

    func stop() {
        failures = []
        displayFailures = []
        releaseAll()
        state = hasResources || !errorMessages.isEmpty ? .error : .off
    }

    // Returns true when the currently owned display should be checked again.
    @discardableResult
    func validateResources(retryUntil deadline: DispatchTime? = nil) -> Bool {
        guard state == .on, mode == .virtualDisplay, let virtualDisplay,
              case .failure(let failure) = virtualDisplay.validate() else { return false }
        if failure.canRetryTopology, let deadline, DispatchTime.now() < deadline { return true }

        displayFailures = [failure]
        releaseAll()
        state = .error
        return false
    }

    private func releaseAll() {
        var remaining: [OwnedAssertion] = []
        for assertion in assertions.reversed() {
            switch backend.release(assertion) {
            case .success:
                break
            case .failure(let failure):
                failures.append(failure)
                remaining.append(assertion)
            }
        }
        // Keep failed handles so a later stop can retry them.
        assertions = remaining.reversed()
        if let virtualDisplay, virtualDisplay.hasResources,
           case .failure(let failure) = virtualDisplay.stop() {
            displayFailures.append(failure)
        }
    }

    deinit {
        for assertion in assertions.reversed() {
            _ = backend.release(assertion)
        }
        if let virtualDisplay, virtualDisplay.hasResources {
            _ = virtualDisplay.stop()
        }
    }
}
