import CoreGraphics
import Foundation
import os

extension Notification.Name {
    static let virtualDisplayOwnerDidExit = Notification.Name("io.github.underconnor.insomac.virtual-display-owner-did-exit")
}

final class NativeVirtualDisplay: VirtualDisplayBackend {
    private let logger = Logger(subsystem: "io.github.underconnor.insomac", category: "VirtualDisplay")
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
        guard VirtualDisplayProcessIO.prepareControlWriter(input.fileHandleForWriting) else {
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
            // AppKit's display-change notification can arrive after the owner's
            // readiness reply. Let the parent's readback catch up off the UI thread.
            let deadline = ProcessInfo.processInfo.systemUptime + 2
            while let id = ownedID, child.isRunning,
                  !InsoMacVirtualDisplayLayoutIsUsable(layout(for: id), true),
                  ProcessInfo.processInfo.systemUptime < deadline {
                Thread.sleep(forTimeInterval: 0.02)
            }
            return validate(requiresSecondaryDisplay: true)
        } catch {
            return failure("Could not start the virtual display owner. Turn off and try again.")
        }
    }

    func validate() -> Result<Void, VirtualDisplayFailure> {
        validate(requiresSecondaryDisplay: false)
    }

    private func validate(requiresSecondaryDisplay: Bool) -> Result<Void, VirtualDisplayFailure> {
        guard process?.isRunning == true, let id = ownedID else {
            return failure("The virtual display owner or display is unavailable. Turn off and try again.")
        }
        let readback = layout(for: id)
        guard InsoMacVirtualDisplayLayoutIsUsable(readback, requiresSecondaryDisplay) else {
            let detail = "initial=\(requiresSecondaryDisplay) online=\(readback.online) active=\(readback.active) "
                + "asleep=\(readback.asleep) builtIn=\(readback.builtIn) main=\(readback.main) "
                + "mirrored=\(readback.mirrored) width=\(readback.width) height=\(readback.height)"
            logger.error("Owned virtual-display layout rejected: \(detail, privacy: .public)")
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
        if let process {
            switch VirtualDisplayProcessIO.finish(process) {
            case .exited: break
            case .killed: stopError = "The unresponsive virtual display owner was terminated."
            case .stillRunning:
                return failure("The virtual display owner has not exited. Choose Release Again, or quit InsoMac.")
            }
        }
        let removalDeadline = ProcessInfo.processInfo.systemUptime + 2
        while !displayWasRemoved() && ProcessInfo.processInfo.systemUptime < removalDeadline {
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
        return try VirtualDisplayProcessIO.readResponse(from: handle, timeout: timeout)
    }

    private func layout(for id: UInt32) -> InsoMacVirtualDisplayLayout {
        let bounds = CGDisplayBounds(id)
        return InsoMacVirtualDisplayLayout(
            online: CGDisplayIsOnline(id) != 0, active: CGDisplayIsActive(id) != 0,
            asleep: CGDisplayIsAsleep(id) != 0, builtIn: CGDisplayIsBuiltin(id) != 0,
            main: CGDisplayIsMain(id) != 0, mirrored: CGDisplayMirrorsDisplay(id) != 0,
            width: bounds.width, height: bounds.height)
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
