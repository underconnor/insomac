import AppKit
import IOKit.pwr_mgt

final class RecordingBackend: AssertionBackend {
    let native = IOKitAssertionBackend()
    var acquired: [OwnedAssertion] = []

    func create(_ kind: AssertionKind) -> Result<UInt32, AssertionFailure> {
        let result = native.create(kind)
        if case .success(let id) = result {
            acquired.append(OwnedAssertion(id: id, kind: kind))
        }
        return result
    }

    func release(_ assertion: OwnedAssertion) -> Result<Void, AssertionFailure> {
        native.release(assertion)
    }
}

struct SmokeFailure: Error, CustomStringConvertible {
    let description: String
}

@main
struct SmokeTests {
    @MainActor
    static func main() throws {
        let presentations = [
            StatusPresentation(state: .off, hasResources: false),
            StatusPresentation(state: .on, hasResources: true),
            StatusPresentation(state: .error, hasResources: false),
            StatusPresentation(state: .error, hasResources: true)
        ]
        guard Set(presentations.prefix(3).map(\.symbol)).count == 3,
              presentations.map(\.action) == ["Turn On", "Turn Off", "Try Again", "Release Again"] else {
            throw SmokeFailure(description: "Status shapes or recovery actions are incorrect.")
        }
        for presentation in presentations {
            guard NSImage(systemSymbolName: presentation.symbol, accessibilityDescription: presentation.label) != nil,
                  presentation.label.hasPrefix("InsoMac: "),
                  presentation.label.contains(presentation.state.rawValue),
                  presentation.label.contains(presentation.mode.rawValue),
                  presentation.label.contains("Open-lid only") else {
                throw SmokeFailure(description: "Missing status symbol or accessibility label.")
            }
        }
        let virtual = StatusPresentation(state: .on, hasResources: true, mode: .virtualDisplay)
        guard virtual.label.contains("Experimental"), virtual.label.contains("Closed-lid use unverified"),
              virtual.scope == "Virtual Display: closed-lid use unverified",
              virtual.action == "Turn Off" else {
            throw SmokeFailure(description: "The virtual mode must identify itself and its limitation.")
        }
        print("PASS: distinct status symbols, accessibility labels, and recovery actions")

        let backend = RecordingBackend()
        let session = KeepAwakeSession(backend: backend)
        defer { session.stop() }
        guard session.state == .off && backend.acquired.isEmpty else {
            throw SmokeFailure(description: "Native session did not start off.")
        }
        session.start()
        guard session.state == .on && backend.acquired.count == 2 else {
            throw SmokeFailure(description: session.failures.map(\.description).joined(separator: "\n"))
        }
        for assertion in backend.acquired {
            guard let properties = IOPMAssertionCopyProperties(assertion.id)?.takeRetainedValue() as? [String: Any],
                  properties[kIOPMAssertionTypeKey] as? String == assertion.kind.rawValue,
                  (properties[kIOPMAssertionLevelKey] as? NSNumber)?.uint32Value == UInt32(kIOPMAssertionLevelOn) else {
                throw SmokeFailure(description: "Could not verify active \(assertion.kind.rawValue).")
            }
        }
        print("PASS: both process-owned IOKit assertions acquired and verified")
        session.stop()
        guard session.state == .off && !session.hasAssertions else {
            throw SmokeFailure(description: "Native assertion release failed.")
        }
        for assertion in backend.acquired {
            guard IOPMAssertionCopyProperties(assertion.id) == nil else {
                throw SmokeFailure(description: "Assertion remains after release: \(assertion.kind.rawValue).")
            }
        }
        print("PASS: both IOKit assertions explicitly released and absent")
    }
}
