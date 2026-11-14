import AppKit

struct MeasurementFailure: Error, CustomStringConvertible {
    let description: String
}

@main
struct MeasureIdle {
    @MainActor
    static func main() {
        do {
            try run()
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(2)
        }
    }

    @MainActor
    private static func run() throws {
        guard CommandLine.arguments.count == 2 else {
            throw MeasurementFailure(description: "Pass the app executable path.")
        }
        _ = NSApplication.shared
        let child = Process()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let started = Date()
        try child.run()
        defer {
            if child.isRunning {
                _ = NSRunningApplication(processIdentifier: child.processIdentifier)?.terminate()
                let deadline = Date().addingTimeInterval(5)
                while child.isRunning && Date() < deadline {
                    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                }
                if child.isRunning {
                    kill(child.processIdentifier, SIGKILL)
                    child.waitUntilExit()
                }
            }
        }
        let launchDeadline = Date().addingTimeInterval(5)
        while child.isRunning && Date() < launchDeadline {
            if NSRunningApplication(processIdentifier: child.processIdentifier)?.isFinishedLaunching == true { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        guard child.isRunning,
              NSRunningApplication(processIdentifier: child.processIdentifier)?.isFinishedLaunching == true else {
            throw MeasurementFailure(description: "The app did not finish launching.")
        }
        print(String(format: "Observed launch to finished-launch flag: %.3f seconds", Date().timeIntervalSince(started)))
        print("Idle samples after launch; RSS in KiB; CPU is ps-reported percent; time is cumulative CPU.")
        print("sample rss_kib cpu_percent cumulative_cpu")
        for index in 1...5 {
            RunLoop.current.run(until: Date().addingTimeInterval(1))
            let sample = Process()
            sample.executableURL = URL(fileURLWithPath: "/bin/ps")
            sample.arguments = ["-p", String(child.processIdentifier), "-o", "rss=,pcpu=,time="]
            let output = Pipe()
            sample.standardOutput = output
            try sample.run()
            sample.waitUntilExit()
            let row = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard sample.terminationStatus == 0 && !row.isEmpty else {
                throw MeasurementFailure(description: "Could not sample the app process.")
            }
            print("\(index) \(row)")
        }
    }
}
