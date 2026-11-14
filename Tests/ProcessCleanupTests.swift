import Foundation
import IOKit.pwr_mgt

struct ProcessCheckFailure: Error, CustomStringConvertible {
    let description: String
}

@main
struct ProcessCleanupTests {
    static func main() throws {
        if CommandLine.arguments.contains("--owner") {
            runOwner()
            return
        }
        try verifyCleanup(forceKill: false)
        try verifyCleanup(forceKill: true)
    }

    private static func runOwner() {
        // Bound every child even if its parent stops responding.
        alarm(5)
        let session = KeepAwakeSession(backend: IOKitAssertionBackend())
        session.start()
        guard session.state == .on else { _exit(1) }
        FileHandle.standardOutput.write(Data("ready\n".utf8))
        withExtendedLifetime(session) {
            _ = FileHandle.standardInput.readData(ofLength: 1)
            // Bypass explicit release to check macOS process ownership.
            _exit(0)
        }
    }

    private static func assertionCount(for pid: Int32) throws -> Int {
        var result: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&result) == kIOReturnSuccess,
              let dictionary = result?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else {
            throw ProcessCheckFailure(description: "Could not inspect assertions for the test process.")
        }
        // Inspect only our child; do not log other processes or assertion metadata.
        return (dictionary[NSNumber(value: pid)] ?? []).filter {
            $0[kIOPMAssertionNameKey] as? String == "InsoMac: open-lid keep-awake"
        }.count
    }

    private static func verifyCleanup(forceKill: Bool) throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        child.arguments = ["--owner"]
        let input = Pipe()
        let output = Pipe()
        child.standardInput = input
        child.standardOutput = output
        try child.run()
        defer {
            if child.isRunning {
                kill(child.processIdentifier, SIGKILL)
                child.waitUntilExit()
            }
        }
        let ready = output.fileHandleForReading.availableData
        guard String(data: ready, encoding: .utf8) == "ready\n",
              try assertionCount(for: child.processIdentifier) == 2 else {
            throw ProcessCheckFailure(description: "Test child did not own exactly two assertions.")
        }
        if forceKill {
            kill(child.processIdentifier, SIGKILL)
        } else {
            input.fileHandleForWriting.write(Data([1]))
        }
        child.waitUntilExit()
        guard (forceKill && child.terminationReason == .uncaughtSignal && child.terminationStatus == SIGKILL)
            || (!forceKill && child.terminationReason == .exit && child.terminationStatus == 0) else {
            throw ProcessCheckFailure(description: "Test child did not exit as requested.")
        }
        for _ in 0..<50 {
            if try assertionCount(for: child.processIdentifier) == 0 {
                print("PASS: macOS removed both assertions after \(forceKill ? "SIGKILL" : "process exit without explicit release")")
                return
            }
            usleep(20_000)
        }
        throw ProcessCheckFailure(description: "Test assertions remain after child exit.")
    }
}
