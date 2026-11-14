import Foundation

struct MonitorTestFailure: Error, CustomStringConvertible {
    let description: String
}

@main
struct ParentProcessMonitorTests {
    static func main() throws {
        if CommandLine.arguments.contains("--blocked") {
            alarm(8)
            guard let expected = Int32(CommandLine.arguments.last ?? ""),
                  let monitor = ParentProcessMonitor(expectedParent: expected) else { _exit(2) }
            defer { withExtendedLifetime(monitor) {} }
            FileHandle.standardOutput.write(Data("\(getpid())\n".utf8))
            while true { pause() }
        }
        if CommandLine.arguments.contains("--parent") {
            alarm(5)
            let worker = Process()
            worker.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            worker.arguments = ["--blocked", String(getpid())]
            worker.standardOutput = FileHandle.standardOutput
            try worker.run()
            while true { pause() }
        }

        let wrongParent = Process()
        wrongParent.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        wrongParent.arguments = ["--blocked", String(getppid())]
        wrongParent.standardOutput = FileHandle.nullDevice
        try wrongParent.run()
        wrongParent.waitUntilExit()
        guard wrongParent.terminationReason == .exit, wrongParent.terminationStatus == 2 else {
            throw MonitorTestFailure(description: "A mismatched parent must be rejected before work starts.")
        }
        print("PASS: owner rejects a mismatched startup parent")

        let parent = Process()
        parent.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        parent.arguments = ["--parent"]
        let output = Pipe()
        parent.standardOutput = output
        try parent.run()
        var workerPID: Int32?
        defer {
            if parent.isRunning {
                kill(parent.processIdentifier, SIGKILL)
                parent.waitUntilExit()
            }
            if let workerPID { kill(workerPID, SIGKILL) }
        }
        let ready = String(data: output.fileHandleForReading.availableData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let pid = Int32(ready), pid > 1 else {
            throw MonitorTestFailure(description: "The blocked worker did not become ready.")
        }
        workerPID = pid
        kill(parent.processIdentifier, SIGKILL)
        parent.waitUntilExit()
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if kill(pid, 0) == -1 && errno == ESRCH {
                workerPID = nil
                print("PASS: parent exit ends a worker with its main thread deliberately blocked")
                return
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        throw MonitorTestFailure(description: "The blocked worker outlived its parent for more than two seconds.")
    }
}
