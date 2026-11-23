enum KeepAwakeMode: String, CaseIterable, Sendable {
    case screen = "Keep Screen On"
    case virtualDisplay = "Virtual Display (Experimental)"

    var limitation: String {
        switch self {
        case .screen: "Keep Screen On: open-lid only"
        case .virtualDisplay: "Virtual Display: closed-lid use unverified"
        }
    }
}

struct VirtualDisplayFailure: Error, Equatable, CustomStringConvertible {
    let description: String
    let canRetryTopology: Bool

    init(description: String, canRetryTopology: Bool = false) {
        self.description = description
        self.canRetryTopology = canRetryTopology
    }
}

protocol VirtualDisplayBackend: AnyObject {
    var unavailabilityReason: String? { get }
    var hasResources: Bool { get }
    var displayID: UInt32? { get }
    func start() -> Result<Void, VirtualDisplayFailure>
    func validate() -> Result<Void, VirtualDisplayFailure>
    func stop() -> Result<Void, VirtualDisplayFailure>
}
