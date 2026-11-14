import Foundation
import IOKit.pwr_mgt

struct AssertionSmokeFailure: Error, CustomStringConvertible {
    let description: String
}

@main
struct AssertionSmokeTests {
    @MainActor
    static func main() throws {
        let backend = IOKitAssertionBackend()
        var owned: [OwnedAssertion] = []
        defer { for assertion in owned.reversed() { _ = backend.release(assertion) } }
        for kind in AssertionKind.allCases {
            switch backend.create(kind) {
            case .success(let id): owned.append(OwnedAssertion(id: id, kind: kind))
            case .failure(let failure): throw failure
            }
        }
        for assertion in owned {
            guard let properties = IOPMAssertionCopyProperties(assertion.id)?.takeRetainedValue() as? [String: Any],
                  properties[kIOPMAssertionTypeKey] as? String == assertion.kind.rawValue,
                  (properties[kIOPMAssertionLevelKey] as? NSNumber)?.uint32Value == UInt32(kIOPMAssertionLevelOn) else {
                throw AssertionSmokeFailure(description: "Native assertion readback failed.")
            }
        }
        print("PASS: both native IOKit assertion types and levels verified without graphics")
        for assertion in owned.reversed() {
            if case .failure(let failure) = backend.release(assertion) { throw failure }
            guard IOPMAssertionCopyProperties(assertion.id) == nil else {
                throw AssertionSmokeFailure(description: "An explicitly released assertion remains active.")
            }
        }
        owned = []
        print("PASS: both native assertions explicitly released and absent")
    }
}
