import Foundation

private struct DisplayPolicyFailure: Error, CustomStringConvertible {
    let description: String
}

@main
struct VirtualDisplayPolicyTests {
    static func main() throws {
        let secondary = InsoMacVirtualDisplayLayout(online: true, active: true, asleep: false,
            builtIn: false, main: false, mirrored: false, width: 1280, height: 720)
        try check(InsoMacVirtualDisplayLayoutIsUsable(secondary, true)
            && InsoMacVirtualDisplayLayoutIsUsable(secondary, false), "A usable secondary display must pass both phases.")
        var promoted = secondary
        promoted.main = true
        try check(!InsoMacVirtualDisplayLayoutIsUsable(promoted, true), "Initial creation must remain secondary.")
        try check(InsoMacVirtualDisplayLayoutIsUsable(promoted, false), "An owned usable display promoted to main must remain valid.")
        let invalid: [InsoMacVirtualDisplayLayout] = [
            changing(promoted) { $0.online = false }, changing(promoted) { $0.active = false },
            changing(promoted) { $0.asleep = true }, changing(promoted) { $0.builtIn = true },
            changing(promoted) { $0.mirrored = true }, changing(promoted) { $0.width = 1920 },
            changing(promoted) { $0.height = 1080 }
        ]
        for layout in invalid {
            try check(!InsoMacVirtualDisplayLayoutIsUsable(layout, false), "Promotion must not relax another usability guard.")
        }
        print("PASS: initial secondary policy, later main promotion, and all remaining layout guards")
    }

    private static func changing(_ value: InsoMacVirtualDisplayLayout,
                                 _ update: (inout InsoMacVirtualDisplayLayout) -> Void) -> InsoMacVirtualDisplayLayout {
        var changed = value
        update(&changed)
        return changed
    }

    private static func check(_ condition: Bool, _ description: String) throws {
        if !condition { throw DisplayPolicyFailure(description: description) }
    }
}
