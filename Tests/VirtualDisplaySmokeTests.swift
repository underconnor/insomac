import CoreGraphics
import Foundation
import AppKit
import IOKit.pwr_mgt

struct VirtualSmokeFailure: Error, CustomStringConvertible {
    let description: String
}

struct DisplaySnapshot: Codable, Equatable {
    let id: UInt32
    let active: Bool
    let main: Bool
    let builtIn: Bool
    let asleep: Bool
    let mirrorID: UInt32
    let x: Double
    let y: Double
    let width: Int
    let height: Int
    let pixelWidth: Int
    let pixelHeight: Int
}

struct DisplayTopology: Codable, Equatable {
    let active: [UInt32]
    let online: [UInt32]
    let displays: [DisplaySnapshot]

    static func read() throws -> Self {
        var online = [CGDirectDisplayID](repeating: 0, count: 64)
        var active = online
        var onlineCount: UInt32 = 0
        var activeCount: UInt32 = 0
        guard CGGetOnlineDisplayList(64, &online, &onlineCount) == .success,
              CGGetActiveDisplayList(64, &active, &activeCount) == .success,
              onlineCount < 64, activeCount < 64 else {
            throw VirtualSmokeFailure(description: "Could not snapshot display topology.")
        }
        let ids = online.prefix(Int(onlineCount)).sorted()
        return Self(active: active.prefix(Int(activeCount)).sorted(), online: ids, displays: ids.map { id in
            let mode = CGDisplayCopyDisplayMode(id)
            let bounds = CGDisplayBounds(id)
            return DisplaySnapshot(id: id, active: CGDisplayIsActive(id) != 0, main: CGDisplayIsMain(id) != 0,
                builtIn: CGDisplayIsBuiltin(id) != 0, asleep: CGDisplayIsAsleep(id) != 0,
                mirrorID: CGDisplayMirrorsDisplay(id), x: bounds.origin.x, y: bounds.origin.y,
                width: mode?.width ?? 0, height: mode?.height ?? 0,
                pixelWidth: mode?.pixelWidth ?? 0, pixelHeight: mode?.pixelHeight ?? 0)
        })
    }
}

@main
@MainActor
struct VirtualDisplaySmokeTests {
    static func main() {
        do {
            if VirtualDisplayHost.runIfRequested() { return }
            if CommandLine.arguments.contains("--observe") {
                alarm(3)
                NSApplication.shared.setActivationPolicy(.prohibited)
                _ = NSScreen.screens
                try emit(["event": "fresh_observer", "topology": try jsonObject(DisplayTopology.read())])
            } else if CommandLine.arguments.contains("--owner") {
                try runOwner()
            } else {
                try runParent()
            }
        } catch {
            FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
            exit(1)
        }
    }

    private static func runParent() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let callback: CGDisplayReconfigurationCallBack = { _, _, _ in }
        guard CGDisplayRegisterReconfigurationCallback(callback, nil) == .success else {
            throw VirtualSmokeFailure(description: "Could not observe display reconfiguration.")
        }
        defer { CGDisplayRemoveReconfigurationCallback(callback, nil) }
        let baseline = try DisplayTopology.read()
        try emit(["event": "baseline", "topology": try jsonObject(baseline)])
        for (forceKill, ownerFailure) in [(true, false), (false, false), (false, true)] {
            let result = Result { try runChild(forceKill: forceKill, baseline: baseline, ownerFailure: ownerFailure) }
            try verifyRestored(baseline)
            let outcome = try? result.get()
            let scenario = ownerFailure ? "display_owner_SIGKILL" : (forceKill ? "app_SIGKILL" : "explicit_stop")
            let label = outcome.map { $0 ? scenario : "availability_check" } ?? "failed_run"
            try emit(["event": "baseline_restored", "after": label,
                      "topology": try jsonObject(DisplayTopology.read())])
            let started = try result.get()
            if !started { return }
        }
        try emit(["event": "passed", "checks": "active mode readback, assertions, explicit stop, app death, owner death, baseline restoration"])
    }

    private static func runOwner() throws {
        // A stuck owner cannot keep a display or assertions beyond this bound.
        alarm(12)
        NSApplication.shared.setActivationPolicy(.prohibited)
        _ = NSScreen.screens
        _ = try DisplayTopology.read()
        let display = NativeVirtualDisplay()
        if let reason = display.unavailabilityReason {
            try emit(["event": "unavailable", "reason": reason])
            return
        }
        let baselineRSS = try psSample(pid: getpid())
        let session = KeepAwakeSession(backend: IOKitAssertionBackend(), virtualDisplay: display)
        session.selectMode(.virtualDisplay)
        session.start()
        guard session.state == .on, let id = session.virtualDisplayID else {
            let messages = session.errorMessages
            session.stop()
            try emit(["event": "creation_failed", "errors": messages + session.errorMessages])
            _exit(2)
        }
        try emit(["event": "ready", "display_id": id, "state": session.state.rawValue,
                  "assertions_owned": session.hasAssertions, "before": baselineRSS,
                  "display_owner_resources": try display.ownerProcessIdentifier.map { try psSample(pid: $0) } ?? [:],
                  "owner_topology": try jsonObject(DisplayTopology.read())])
        let command = withExtendedLifetime(session) {
            FileHandle.standardInput.readData(ofLength: 1).first
        }
        if command == 0x63 {
            guard let pid = display.ownerProcessIdentifier else {
                throw VirtualSmokeFailure(description: "No display owner to terminate.")
            }
            kill(pid, SIGKILL)
            let deadline = Date().addingTimeInterval(1)
            while display.ownerProcessIdentifier != nil && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
            session.validateResources()
            guard session.state == .error && !session.hasResources && !session.errorMessages.isEmpty else {
                throw VirtualSmokeFailure(description: "Unexpected owner death was not cleaned up and reported.")
            }
            try emit(["event": "owner_failure_handled", "state": session.state.rawValue,
                      "resources_owned": session.hasResources, "errors": session.errorMessages])
            return
        }
        session.stop()
        guard session.state == .off && !session.hasResources else {
            throw VirtualSmokeFailure(description: session.errorMessages.joined(separator: " "))
        }
        try emit(["event": "stopped", "state": session.state.rawValue, "resources_owned": session.hasResources])
    }

    private static func runChild(forceKill: Bool, baseline: DisplayTopology, ownerFailure: Bool) throws -> Bool {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        child.arguments = ["--owner"]
        let input = Pipe()
        let output = Pipe()
        child.standardInput = input
        child.standardOutput = output
        child.standardError = FileHandle.nullDevice
        try child.run()
        defer {
            if child.isRunning {
                kill(child.processIdentifier, SIGKILL)
                child.waitUntilExit()
            }
        }
        let data = output.fileHandleForReading.availableData
        guard let ready = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw VirtualSmokeFailure(description: "The virtual display owner did not report readiness.")
        }
        try emit(ready)
        if ready["event"] as? String == "unavailable" {
            child.waitUntilExit()
            return false
        }
        guard ready["event"] as? String == "ready", ready["assertions_owned"] as? Bool == true,
              let number = ready["display_id"] as? NSNumber else {
            throw VirtualSmokeFailure(description: "Virtual display creation failed. See the owner result.")
        }
        let id = number.uint32Value
        guard try assertionCount(for: child.processIdentifier) == 2 else {
            throw VirtualSmokeFailure(description: "The owner did not hold exactly two keep-awake assertions.")
        }
        var active = try DisplayTopology.read()
        let readbackDeadline = Date().addingTimeInterval(2)
        while Date() < readbackDeadline,
              active.displays.first(where: { $0.id == id })?.width != 1280 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            active = try DisplayTopology.read()
        }
        try emit(["event": "active_topology", "topology": try jsonObject(active)])
        if active.displays.first(where: { $0.id == id })?.width != 1280 {
            active = try readIndependentTopology()
        }
        guard Set(active.online).subtracting(baseline.online) == [id],
              active.displays.filter({ $0.id != id }) == baseline.displays,
              active.active.contains(id),
              let own = active.displays.first(where: { $0.id == id }),
              !own.builtIn, !own.main, !own.asleep, own.mirrorID == 0,
              own.width == 1280, own.height == 720, own.pixelWidth == 1280, own.pixelHeight == 720 else {
            throw VirtualSmokeFailure(description: "The display was unusable or the pre-existing display layout changed.")
        }
        try emit(["event": "active_verified", "display": try jsonObject(own)])
        if forceKill {
            kill(child.processIdentifier, SIGKILL)
        } else if ownerFailure {
            input.fileHandleForWriting.write(Data([0x63]))
        } else {
            for index in 1...3 {
                Thread.sleep(forTimeInterval: 1)
                try emit(["event": "active_resource_sample", "sample": index, "values": try psSample(pid: child.processIdentifier)])
            }
            input.fileHandleForWriting.write(Data([1]))
        }
        child.waitUntilExit()
        let remainder = output.fileHandleForReading.readDataToEndOfFile()
        if !remainder.isEmpty {
            if let stopped = try JSONSerialization.jsonObject(with: remainder) as? [String: Any] { try emit(stopped) }
        }
        guard (forceKill && child.terminationReason == .uncaughtSignal && child.terminationStatus == SIGKILL)
            || (!forceKill && child.terminationReason == .exit && child.terminationStatus == 0) else {
            throw VirtualSmokeFailure(description: "The virtual display owner did not exit as requested.")
        }
        guard try assertionCount(for: child.processIdentifier) == 0 else {
            throw VirtualSmokeFailure(description: "The owner left keep-awake assertions after exit.")
        }
        return true
    }

    private static func readIndependentTopology() throws -> DisplayTopology {
        let observer = Process()
        observer.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        observer.arguments = ["--observe"]
        let output = Pipe()
        observer.standardOutput = output
        observer.standardError = FileHandle.nullDevice
        try observer.run()
        observer.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard observer.terminationReason == .exit, observer.terminationStatus == 0,
              let record = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let topology = record["topology"] else {
            throw VirtualSmokeFailure(description: "The fresh observer could not inspect the temporary display.")
        }
        try emit(record)
        return try JSONDecoder().decode(DisplayTopology.self, from: JSONSerialization.data(withJSONObject: topology))
    }

    private static func assertionCount(for pid: Int32) throws -> Int {
        var result: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&result) == kIOReturnSuccess,
              let dictionary = result?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else {
            throw VirtualSmokeFailure(description: "Could not inspect the test owner's assertions.")
        }
        return (dictionary[NSNumber(value: pid)] ?? []).filter {
            $0[kIOPMAssertionNameKey] as? String == "InsoMac: open-lid keep-awake"
        }.count
    }

    private static func verifyRestored(_ baseline: DisplayTopology) throws {
        for _ in 0..<150 {
            if try DisplayTopology.read() == baseline { return }
            Thread.sleep(forTimeInterval: 0.02)
        }
        throw VirtualSmokeFailure(description: "Display topology did not return to baseline. Stop this experiment and inspect Displays settings.")
    }

    private static func psSample(pid: Int32) throws -> [String: Any] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-p", String(pid), "-o", "rss=,pcpu=,time="]
        let output = Pipe()
        task.standardOutput = output
        try task.run()
        task.waitUntilExit()
        let row = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let columns = row.split(whereSeparator: { $0.isWhitespace })
        guard task.terminationStatus == 0, columns.count == 3,
              let rss = Int(columns[0]), let cpu = Double(columns[1]) else {
            throw VirtualSmokeFailure(description: "Could not read the test owner's resource sample.")
        }
        return ["rss_kib": rss, "cpu_percent": cpu, "cumulative_cpu": String(columns[2])]
    }

    private static func jsonObject<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
    }

    private static func emit(_ fields: [String: Any]) throws {
        var record = fields
        record["timestamp"] = ISO8601DateFormatter().string(from: Date())
        var data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
    }
}
