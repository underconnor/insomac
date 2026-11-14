import Foundation

final class ParentProcessMonitor {
    private let source: any DispatchSourceProcess

    init?(expectedParent: Int32) {
        guard expectedParent > 1, getppid() == expectedParent else { return nil }
        source = DispatchSource.makeProcessSource(identifier: expectedParent, eventMask: .exit,
            queue: DispatchQueue(label: "io.github.underconnor.insomac.parent-exit", qos: .utility))
        // This queue can exit the owner even when its main thread is blocked.
        source.setEventHandler { _exit(0) }
        source.resume()
        guard getppid() == expectedParent else {
            source.cancel()
            return nil
        }
    }

    deinit { source.cancel() }
}
