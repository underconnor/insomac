import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let coordinator = SessionCoordinator {
        KeepAwakeSession(backend: IOKitAssertionBackend(), virtualDisplay: NativeVirtualDisplay())
    }
    private var controller: StatusItemController?
    private var terminationRequested = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = StatusItemController(coordinator: coordinator)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if !terminationRequested {
            terminationRequested = true
            coordinator.prepareToQuit { _ in
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }
}

@main
struct InsoMacApp {
    @MainActor
    static func main() {
        if VirtualDisplayHost.runIfRequested() { return }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
