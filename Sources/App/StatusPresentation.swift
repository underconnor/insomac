struct StatusPresentation {
    let state: SessionState
    let hasResources: Bool
    var mode: KeepAwakeMode = .screen
    var activity: SessionActivity?
    var requestedOn: Bool?

    var symbol: String {
        if activity != nil { return "hourglass" }
        return switch state {
        case .off: "moon.zzz"
        case .on: "cup.and.saucer.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    var scope: String { mode.limitation }
    var label: String {
        let detail = mode == .screen ? "Open-lid only" : "Closed-lid use unverified"
        return "InsoMac: \(activity?.rawValue ?? state.rawValue). \(mode.rawValue). \(detail)."
    }
    var title: String { "Keep Awake: \(activity?.rawValue ?? state.rawValue)" }

    var action: String {
        if activity == .quitting { return "Quitting…" }
        if activity != nil, let requestedOn { return requestedOn ? "Turn Off" : "Turn On" }
        return if hasResources {
            state == .error ? "Release Again" : "Turn Off"
        } else {
            state == .error ? "Try Again" : "Turn On"
        }
    }
}
