import CoreGraphics
import Foundation

extension Notification.Name {
    static let virtualDisplayOwnerDidExit = Notification.Name("io.github.underconnor.insomac.virtual-display-owner-did-exit")
}

final class NativeVirtualDisplay: VirtualDisplayBackend {
    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var ownedID: UInt32?
    private var baselineIDs: Set<UInt32>?

    var unavailabilityReason: String? { InsoMacVirtualDisplayOwner.unavailabilityReason }
    var hasResources: Bool { process?.isRunning == true || ownedID != nil || baselineIDs != nil }
    var displayID: UInt32? { ownedID }
    var ownerProcessIdentifier: Int32? { process?.isRunning == true ? process?.processIdentifier : nil }

    func start() -> Result<Void, VirtualDisplayFailure> {
        guard !hasResources else { return failure("Release the previous virtual session first.") }
        if let reason = unavailabilityReason { return failure(reason) }
        guard let baseline = onlineIDs() else { return failure("Could not read the display list. Try again.") }
        baselineIDs = baseline
        let child = Process()
        child.executableURL = Bundle.main.executableURL
            ?? URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        child.arguments = [VirtualDisplayHost.argument, String(getpid())]
        let input = Pipe()
        let output = Pipe()
        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
            baselineIDs = nil
            return failure("Could not prepare the virtual display owner. Choose Keep Screen On.")
        }
        child.standardInput = input
        child.standardOutput = output
        child.standardError = FileHandle.nullDevice
        child.terminationHandler = { _ in
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .virtualDisplayOwnerDidExit, object: nil)
            }
        }
        self.input = input
        self.output = output
        process = child
        do {
            try child.run()
            let response = try readResponse(timeout: 5_000)
            if let number = response["display_id"] as? NSNumber, number.uint32Value != 0 { ownedID = number.uint32Value }
            guard response["ok"] as? Bool == true, ownedID != nil else {
                return failure(response["error"] as? String ?? "Virtual display startup failed. Choose Keep Screen On.")
            }
            return validate()
        } catch {
            return failure("Could not start the virtual display owner. Turn off and try again.")
        }
    }

    func validate() -> Result<Void, VirtualDisplayFailure> {
        guard process?.isRunning == true, let id = ownedID,
              CGDisplayIsOnline(id) != 0, CGDisplayIsActive(id) != 0,
              CGDisplayIsAsleep(id) == 0, CGDisplayIsBuiltin(id) == 0,
              CGDisplayIsMain(id) == 0, CGDisplayMirrorsDisplay(id) == 0,
              CGDisplayBounds(id).width == 1280, CGDisplayBounds(id).height == 720 else {
            return failure("The virtual display owner or display is unavailable. Turn off and try again.")
        }
        do {
            try input?.fileHandleForWriting.write(contentsOf: Data([0x76]))
            let response = try readResponse(timeout: 2_000)
            guard response["ok"] as? Bool == true,
                  (response["display_id"] as? NSNumber)?.uint32Value == id,
                  response["width"] as? Int == 1280, response["height"] as? Int == 720 else {
                return failure(response["error"] as? String ?? "Virtual display mode readback failed. Turn off and try again.")
            }
            return .success(())
        } catch {
            return failure("The virtual display owner did not confirm its mode. Turn off and try again.")
        }
    }

    func stop() -> Result<Void, VirtualDisplayFailure> {
        var stopError: String?
        if process?.isRunning == true {
            do {
                try input?.fileHandleForWriting.write(contentsOf: Data([0x73]))
                let response = try readResponse(timeout: 3_000)
                if response["ok"] as? Bool != true { stopError = response["error"] as? String ?? "Virtual display cleanup failed." }
            } catch {
                stopError = "The virtual display owner did not finish cleanup."
            }
        }
        try? input?.fileHandleForWriting.close()
        let exitDeadline = Date().addingTimeInterval(1)
        while process?.isRunning == true && Date() < exitDeadline { Thread.sleep(forTimeInterval: 0.01) }
        if let process, process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
            stopError = "The unresponsive virtual display owner was terminated."
        }
        let removalDeadline = Date().addingTimeInterval(2)
        while !displayWasRemoved() && Date() < removalDeadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if !displayWasRemoved() {
            return failure("macOS has not removed the virtual display. Choose Release Again, or quit InsoMac.")
        }
        ownedID = nil
        baselineIDs = nil
        process = nil
        input = nil
        output = nil
        if let stopError { return failure(stopError + " Choose Keep Screen On or try again.") }
        return .success(())
    }

    private func readResponse(timeout: Int32) throws -> [String: Any] {
        guard let handle = output?.fileHandleForReading else { throw CocoaError(.fileReadUnknown) }
        var descriptor = pollfd(fd: handle.fileDescriptor, events: Int16(POLLIN), revents: 0)
        guard poll(&descriptor, 1, timeout) > 0 else { throw CocoaError(.fileReadUnknown) }
        let data = handle.availableData
        guard !data.isEmpty,
              let response = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadUnknown)
        }
        return response
    }

    private func onlineIDs() -> Set<UInt32>? {
        var ids = [UInt32](repeating: 0, count: 32)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(32, &ids, &count) == .success, count < 32 else { return nil }
        return Set(ids.prefix(Int(count)))
    }

    private func displayWasRemoved() -> Bool {
        guard let current = onlineIDs() else { return false }
        if let ownedID { return !current.contains(ownedID) }
        return baselineIDs.map { current.isSubset(of: $0) } ?? true
    }

    private func failure(_ message: String) -> Result<Void, VirtualDisplayFailure> {
        .failure(VirtualDisplayFailure(description: message))
    }

    deinit {
        // EOF also releases the display when the app exits abruptly.
        try? input?.fileHandleForWriting.close()
    }
}
