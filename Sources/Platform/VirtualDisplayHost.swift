import Foundation

enum VirtualDisplayHost {
    static let argument = "--virtual-display-owner"

    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.contains(argument) else { return false }
        guard CommandLine.arguments.count == 3, let expectedParent = Int32(CommandLine.arguments[2]),
              let monitor = ParentProcessMonitor(expectedParent: expectedParent) else { _exit(2) }
        defer { withExtendedLifetime(monitor) {} }
        let owner = InsoMacVirtualDisplayOwner()
        defer { try? owner.stop() }
        do {
            try owner.start()
            try owner.validate()
            try emit(["ok": true, "display_id": owner.displayID, "width": 1280, "height": 720])
            while true {
                let data = FileHandle.standardInput.readData(ofLength: 1)
                guard let command = data.first else { break }
                if command == 0x73 {
                    try owner.stop()
                    try emit(["ok": true])
                    return true
                }
                if command == 0x76 {
                    var response: [String: Any]
                    do {
                        try owner.validate()
                        response = ["ok": true, "display_id": owner.displayID, "width": 1280, "height": 720]
                    } catch {
                        let topologyUnavailable = (error as? InsoMacVirtualDisplayError)?.code == .topologyUnavailable
                        response = ["ok": false, "display_id": owner.displayID,
                                    "topology_unavailable": topologyUnavailable, "error": error.localizedDescription]
                    }
                    try emit(response)
                }
            }
        } catch {
            try? emit(["ok": false, "display_id": owner.displayID, "error": error.localizedDescription])
        }
        return true
    }

    private static func emit(_ response: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: response, options: [.sortedKeys])
        data.append(0x0A)
        try FileHandle.standardOutput.write(contentsOf: data)
    }
}
