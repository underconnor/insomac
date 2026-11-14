import Foundation

private struct ProcessIOFailure: Error, CustomStringConvertible {
    let description: String
}

@main
struct VirtualDisplayProcessIOTests {
    static func main() throws {
        if CommandLine.arguments.contains("--silent-owner") {
            alarm(5)
            _ = FileHandle.standardInput.readData(ofLength: 1)
            return
        }
        if CommandLine.arguments.contains("--responding-owner") {
            alarm(5)
            try FileHandle.standardOutput.write(contentsOf: Data("{\"ok\":true}\n".utf8))
            _ = FileHandle.standardInput.readData(ofLength: 1)
            return
        }
        try testSilentOwnerAndBrokenPipe()
        try testGracefulExitAndEOF()
    }

    private static func testSilentOwnerAndBrokenPipe() throws {
        let input = Pipe()
        let output = Pipe()
        let process = try child("--silent-owner", input: input, output: output)
        defer { _ = VirtualDisplayProcessIO.finish(process, gracePeriod: 0, killTimeout: 1) }
        let started = ProcessInfo.processInfo.systemUptime
        do {
            _ = try VirtualDisplayProcessIO.readResponse(from: output.fileHandleForReading, timeout: 80)
            throw ProcessIOFailure(description: "A silent owner unexpectedly replied.")
        } catch is CocoaError {}
        try check(ProcessInfo.processInfo.systemUptime - started < 0.5, "Silent-owner read must honor its timeout.")
        let exitStarted = ProcessInfo.processInfo.systemUptime
        let result = VirtualDisplayProcessIO.finish(process, gracePeriod: 0.03, killTimeout: 1)
        try check(result == .killed && !process.isRunning, "A non-exiting owned child must be killed and observed exited.")
        try check(ProcessInfo.processInfo.systemUptime - exitStarted < 1.2, "Forced exit must have a bounded wait.")
        do {
            try input.fileHandleForWriting.write(contentsOf: Data([0x76]))
            throw ProcessIOFailure(description: "Writing after owner exit unexpectedly succeeded.")
        } catch is CocoaError {}
        print("PASS: silent child times out, forced exit is bounded, and broken control pipe does not signal the parent")
    }

    private static func testGracefulExitAndEOF() throws {
        let input = Pipe()
        let output = Pipe()
        let process = try child("--responding-owner", input: input, output: output)
        defer { _ = VirtualDisplayProcessIO.finish(process, gracePeriod: 0, killTimeout: 1) }
        let response = try VirtualDisplayProcessIO.readResponse(from: output.fileHandleForReading, timeout: 1_000)
        try check(response["ok"] as? Bool == true, "A complete owner reply must decode.")
        try input.fileHandleForWriting.close()
        try check(VirtualDisplayProcessIO.finish(process, gracePeriod: 1, killTimeout: 1) == .exited,
                  "Closing the control pipe must permit normal child exit.")
        let started = ProcessInfo.processInfo.systemUptime
        do {
            _ = try VirtualDisplayProcessIO.readResponse(from: output.fileHandleForReading, timeout: 1_000)
            throw ProcessIOFailure(description: "EOF unexpectedly decoded as a response.")
        } catch is CocoaError {}
        try check(ProcessInfo.processInfo.systemUptime - started < 0.2, "EOF must fail promptly instead of waiting for another response.")
        print("PASS: normal reply, graceful EOF exit, and response EOF handling")
    }

    private static func child(_ argument: String, input: Pipe, output: Pipe) throws -> Process {
        try check(VirtualDisplayProcessIO.prepareControlWriter(input.fileHandleForWriting), "Could not suppress SIGPIPE for test control writer.")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = [argument]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }

    private static func check(_ condition: Bool, _ description: String) throws {
        if !condition { throw ProcessIOFailure(description: description) }
    }
}
