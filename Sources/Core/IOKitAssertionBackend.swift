import Foundation
import IOKit.pwr_mgt

final class IOKitAssertionBackend: AssertionBackend {
    func create(_ kind: AssertionKind) -> Result<UInt32, AssertionFailure> {
        let type: CFString
        switch kind {
        case .system:
            type = kIOPMAssertionTypePreventUserIdleSystemSleep as CFString
        case .display:
            type = kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString
        }

        var id = IOPMAssertionID(kIOPMNullAssertionID)
        let status = IOPMAssertionCreateWithName(
            type,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "InsoMac: open-lid keep-awake" as CFString,
            &id
        )
        guard status == kIOReturnSuccess else {
            return .failure(AssertionFailure(operation: .create, kind: kind, code: status))
        }
        return .success(id)
    }

    func release(_ assertion: OwnedAssertion) -> Result<Void, AssertionFailure> {
        let status = IOPMAssertionRelease(assertion.id)
        guard status == kIOReturnSuccess || status == kIOReturnNotFound else {
            return .failure(AssertionFailure(operation: .release, kind: assertion.kind, code: status))
        }
        return .success(())
    }
}
