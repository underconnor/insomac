import AppKit
import IOKit.pwr_mgt

struct LifecycleFailure: Error, CustomStringConvertible {
    let description: String
}

@main
struct AppLifecycleTests {
    @MainActor
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw LifecycleFailure(description: "Pass the app executable path.")
        }
        let executable = URL(fileURLWithPath: CommandLine.arguments[1])
        let appURL = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard let bundle = Bundle(url: appURL),
              bundle.bundleIdentifier == "io.github.underconnor.insomac.prototype",
              bundle.object(forInfoDictionaryKey: "CFBundleName") as? String == "InsoMac",
              bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String == "InsoMac",
              bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String == "InsoMac",
              bundle.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String == "13.0",
              bundle.object(forInfoDictionaryKey: "LSUIElement") as? Bool == true else {
            throw LifecycleFailure(description: "The app bundle metadata does not match InsoMac.")
        }
        print("PASS: InsoMac bundle identity, executable, and macOS 13 metadata")
        _ = NSApplication.shared
        let child = Process()
        child.executableURL = executable
        try child.run()
        defer {
            if child.isRunning {
                kill(child.processIdentifier, SIGKILL)
                child.waitUntilExit()
            }
        }

        var app: NSRunningApplication?
        let launchDeadline = Date().addingTimeInterval(5)
        while Date() < launchDeadline && child.isRunning {
            app = NSRunningApplication(processIdentifier: child.processIdentifier)
            if app?.isFinishedLaunching == true { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        guard let app, app.isFinishedLaunching, app.activationPolicy == .accessory,
              app.bundleIdentifier == bundle.bundleIdentifier, app.localizedName == "InsoMac" else {
            throw LifecycleFailure(description: "The app did not finish launching as a menu bar app.")
        }
        var result: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&result) == kIOReturnSuccess,
              let dictionary = result?.takeRetainedValue() as? [NSNumber: [[String: Any]]],
              (dictionary[NSNumber(value: child.processIdentifier)] ?? []).allSatisfy({
                  $0[kIOPMAssertionNameKey] as? String != "InsoMac: open-lid keep-awake"
              }) else {
            throw LifecycleFailure(description: "The app must launch without keep-awake assertions.")
        }
        print("PASS: app bundle launches as an accessory with keep-awake off")
        guard app.terminate() else {
            throw LifecycleFailure(description: "The app refused normal termination.")
        }
        let exitDeadline = Date().addingTimeInterval(5)
        while child.isRunning && Date() < exitDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        guard !child.isRunning, child.terminationReason == .exit, child.terminationStatus == 0 else {
            throw LifecycleFailure(description: "The app did not exit normally within five seconds.")
        }
        print("PASS: app exits normally through AppKit termination")
    }
}
