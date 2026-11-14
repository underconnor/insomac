import Foundation

enum VirtualDisplayProcessIO {
    enum ExitResult {
        case exited, killed, stillRunning
    }

    static func prepareControlWriter(_ handle: FileHandle) -> Bool {
        fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1) != -1
    }

    static func readResponse(from handle: FileHandle, timeout: Int32) throws -> [String: Any] {
        var descriptor = pollfd(fd: handle.fileDescriptor, events: Int16(POLLIN), revents: 0)
        guard poll(&descriptor, 1, timeout) > 0 else { throw CocoaError(.fileReadUnknown) }
        let data = handle.availableData
        guard !data.isEmpty,
              let response = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadUnknown)
        }
        return response
    }

    static func finish(_ process: Process, gracePeriod: TimeInterval = 1,
                       killTimeout: TimeInterval = 1) -> ExitResult {
        if waitForExit(process, timeout: gracePeriod) { return .exited }
        if kill(process.processIdentifier, SIGKILL) != 0 && errno != ESRCH { return .stillRunning }
        return waitForExit(process, timeout: killTimeout) ? .killed : .stillRunning
    }

    private static func waitForExit(_ process: Process, timeout: TimeInterval) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + max(0, timeout)
        while process.isRunning {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return false }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return true
    }
}
