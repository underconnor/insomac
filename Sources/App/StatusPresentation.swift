struct StatusPresentation {
    let state: SessionState
    let hasResources: Bool
    var mode: KeepAwakeMode = .screen

    var symbol: String {
        switch state {
        case .off: "moon.zzz"
        case .on: "cup.and.saucer.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    var scope: String { mode.limitation }
    var label: String {
        let detail = mode == .screen ? "Open-lid only" : "Closed-lid use unverified"
        return "InsoMac: \(state.rawValue). \(mode.rawValue). \(detail)."
    }
    var title: String { "Keep Awake: \(state.rawValue)" }

    var action: String {
        if hasResources {
            state == .error ? "Release Again" : "Turn Off"
        } else {
            state == .error ? "Try Again" : "Turn On"
        }
    }
}
