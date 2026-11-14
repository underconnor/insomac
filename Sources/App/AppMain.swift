import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let session = KeepAwakeSession(backend: IOKitAssertionBackend(), virtualDisplay: NativeVirtualDisplay())
    private var controller: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = StatusItemController(session: session)
    }

    func applicationWillTerminate(_ notification: Notification) {
        session.stop()
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
