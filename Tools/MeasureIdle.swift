import AppKit
import CryptoKit
import Darwin
import IOKit.pwr_mgt

struct MeasurementFailure: Error, CustomStringConvertible {
    let description: String
}

struct ResourceSample: Codable {
    let elapsedSeconds: Double
    let rssBytes: UInt64
    let physicalFootprintBytes: UInt64
    let peakPhysicalFootprintBytes: UInt64
    let userCPUTimeMachTicks: UInt64
    let systemCPUTimeMachTicks: UInt64
    var cpuMachTicks: UInt64 { userCPUTimeMachTicks + systemCPUTimeMachTicks }
}

@main
struct MeasureIdle {
    @MainActor
    static func main() {
        do { try run() }
        catch {
            FileHandle.standardError.write(Data("Measurement failed: \(error)\n".utf8))
            exit(2)
        }
    }

    @MainActor
    private static func run() throws {
        guard CommandLine.arguments.count == 4,
              let seconds = Int(CommandLine.arguments[2]), (60...120).contains(seconds) else {
            throw MeasurementFailure(description: "Usage: insomac-measure-idle executable seconds output-directory; seconds must be 60 through 120.")
        }
        let executable = URL(fileURLWithPath: CommandLine.arguments[1])
        let directory = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
        let timebase = try MachTimebase.current()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        _ = NSApplication.shared
        let child = Process()
        child.executableURL = executable
        let before = Date()
        try child.run()
        var measurementError: Error?
        var summary: [String: Any] = [:]
        do {
            let launchDeadline = Date().addingTimeInterval(5)
            while child.isRunning && Date() < launchDeadline {
                if NSRunningApplication(processIdentifier: child.processIdentifier)?.isFinishedLaunching == true { break }
                pump(0.05)
            }
            guard child.isRunning,
                  NSRunningApplication(processIdentifier: child.processIdentifier)?.isFinishedLaunching == true else {
                throw MeasurementFailure(description: "The owned app did not finish launching within five seconds.")
            }
            let launchSeconds = Date().timeIntervalSince(before)
            // Exclude initial framework and font loading from the sampled CPU interval.
            pump(5)
            let start = DispatchTime.now().uptimeNanoseconds
            var samples = [ResourceSample]()
            repeat {
                guard child.isRunning, try assertionCount(for: child.processIdentifier) == 0 else {
                    throw MeasurementFailure(description: "The target exited or acquired keep-awake assertions; this is no longer an off-state sample.")
                }
                let sample = try readSample(pid: child.processIdentifier, started: start)
                samples.append(sample)
                let data = try JSONEncoder().encode(sample)
                FileHandle.standardOutput.write(data + Data([10]))
                let remaining = Double(seconds) - sample.elapsedSeconds
                if remaining <= 0 { break }
                pump(min(2, remaining))
            } while true
            guard let first = samples.first, let last = samples.last else {
                throw MeasurementFailure(description: "No resource samples were recorded.")
            }
            let elapsed = last.elapsedSeconds - first.elapsedSeconds
            let deltaTicks = last.cpuMachTicks - first.cpuMachTicks
            let deltaNanoseconds = timebase.nanoseconds(forTicks: deltaTicks)
            let diagnostics = try captureDiagnostics(pid: child.processIdentifier, directory: directory)
            let binaryHash = SHA256.hash(data: try Data(contentsOf: executable)).map { String(format: "%02x", $0) }.joined()
            summary = [
                "schema_version": 2,
                "method": "proc_pid_rusage RUSAGE_INFO_V4; bytes and Mach CPU ticks scaled with mach_timebase_info",
                "cpu_timebase_numerator": timebase.numerator,
                "cpu_timebase_denominator": timebase.denominator,
                "physical_footprint_definition": "kernel physical-footprint ledger; distinct from RSS and not a redefinition of the RSS target",
                "app_binary_sha256": binaryHash,
                "sampled_seconds": elapsed,
                "settle_seconds": 5,
                "sample_count": samples.count,
                "rss_min_bytes": samples.map(\.rssBytes).min() ?? 0,
                "rss_max_bytes": samples.map(\.rssBytes).max() ?? 0,
                "physical_footprint_min_bytes": samples.map(\.physicalFootprintBytes).min() ?? 0,
                "physical_footprint_max_bytes": samples.map(\.physicalFootprintBytes).max() ?? 0,
                "cpu_delta_mach_ticks": deltaTicks,
                "cpu_delta_nanoseconds": deltaNanoseconds,
                "average_cpu_percent_of_one_core": elapsed > 0 ? deltaNanoseconds / 1e9 / elapsed * 100 : 0,
                "observed_launch_seconds": launchSeconds,
                "launch_poll_seconds": 0.05,
                "off_state_assertions_verified": true,
                "rss_under_50_mib": samples.allSatisfy { $0.rssBytes < 50 * 1024 * 1024 },
                "diagnostics": diagnostics
            ]
        } catch { measurementError = error }
        let cleanup = terminateOwned(child)
        summary["cleanup_completed"] = cleanup.completed
        summary["cleanup_forced"] = cleanup.forced
        if cleanup.completed {
            summary["termination_status"] = child.terminationStatus
            summary["termination_reason"] = child.terminationReason == .exit ? "exit" : "uncaughtSignal"
        }
        summary["timestamp"] = ISO8601DateFormatter().string(from: Date())
        if let measurementError { summary["failure"] = String(describing: measurementError) }
        let data = try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory.appendingPathComponent("summary.json"))
        FileHandle.standardOutput.write(data + Data([10]))
        guard cleanup.completed else { throw MeasurementFailure(description: "The owned app did not exit within the cleanup bound.") }
        if let measurementError { throw measurementError }
    }

    private static func readSample(pid: Int32, started: UInt64) throws -> ResourceSample {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { value in
            value.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { pointer in
                proc_pid_rusage(pid, RUSAGE_INFO_V4, pointer)
            }
        }
        guard result == 0 else { throw MeasurementFailure(description: "The kernel resource query failed.") }
        return ResourceSample(elapsedSeconds: Double(DispatchTime.now().uptimeNanoseconds - started) / 1e9,
            rssBytes: info.ri_resident_size, physicalFootprintBytes: info.ri_phys_footprint,
            peakPhysicalFootprintBytes: info.ri_lifetime_max_phys_footprint,
            userCPUTimeMachTicks: info.ri_user_time, systemCPUTimeMachTicks: info.ri_system_time)
    }

    private static func assertionCount(for pid: Int32) throws -> Int {
        var copied: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&copied) == kIOReturnSuccess,
              let grouped = copied?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else {
            throw MeasurementFailure(description: "Could not verify the owned app's assertion state.")
        }
        return (grouped[NSNumber(value: pid)] ?? []).filter {
            ($0[kIOPMAssertionNameKey] as? String ?? "").lowercased().hasPrefix("insomac:")
        }.count
    }

    private static func captureDiagnostics(pid: Int32, directory: URL) throws -> [String: String] {
        var results: [String: String] = [:]
        for (name, arguments) in [
            ("footprint", ["-p", String(pid), "--noCategories", "-f", "bytes"]),
            ("vmmap", ["-summary", String(pid)])
        ] {
            let path = directory.appendingPathComponent(name + ".txt")
            FileManager.default.createFile(atPath: path.path, contents: nil)
            let output = try FileHandle(forWritingTo: path)
            let diagnostic = Process()
            diagnostic.executableURL = URL(fileURLWithPath: "/usr/bin/" + name)
            diagnostic.arguments = arguments
            diagnostic.standardOutput = output
            diagnostic.standardError = output
            do {
                try diagnostic.run()
                let deadline = Date().addingTimeInterval(5)
                while diagnostic.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
                if diagnostic.isRunning {
                    kill(diagnostic.processIdentifier, SIGKILL)
                    let exitDeadline = Date().addingTimeInterval(1)
                    while diagnostic.isRunning && Date() < exitDeadline { Thread.sleep(forTimeInterval: 0.02) }
                    results[name] = diagnostic.isRunning ? "timeout; owned diagnostic still running" : "timeout; owned diagnostic terminated"
                    if diagnostic.isRunning {
                        throw MeasurementFailure(description: "Owned diagnostic cleanup failed for process \(diagnostic.processIdentifier).")
                    }
                } else { results[name] = "exit " + String(diagnostic.terminationStatus) }
            } catch let error as MeasurementFailure {
                try? output.close()
                throw error
            } catch { results[name] = "unavailable: " + String(describing: error) }
            try output.close()
        }
        return results
    }

    @MainActor
    private static func pump(_ seconds: Double) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline { RunLoop.current.run(until: min(deadline, Date().addingTimeInterval(0.05))) }
    }

    @MainActor
    private static func terminateOwned(_ child: Process) -> (completed: Bool, forced: Bool) {
        var forced = false
        if child.isRunning {
            _ = NSRunningApplication(processIdentifier: child.processIdentifier)?.terminate()
            let deadline = Date().addingTimeInterval(5)
            while child.isRunning && Date() < deadline { pump(0.05) }
        }
        if child.isRunning {
            forced = true
            kill(child.processIdentifier, SIGKILL)
            let deadline = Date().addingTimeInterval(1)
            while child.isRunning && Date() < deadline { pump(0.02) }
        }
        return (!child.isRunning, forced)
    }
}
