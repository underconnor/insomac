import CoreGraphics
import Foundation

struct ProbeFailure: Error, CustomStringConvertible {
    let description: String
}

@main
struct DisplayProbe {
    static func main() {
        do {
            try run()
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(2)
        }
    }

    private static func run() throws {
        let arguments = CommandLine.arguments
        guard arguments.count <= 2,
              let seconds = Int(arguments.count == 2 ? arguments[1] : "10"),
              (1...120).contains(seconds) else {
            throw ProbeFailure(description: "Usage: insomac-display-probe [seconds], from 1 through 120.")
        }
        let started = Date()
        let deadline = started.addingTimeInterval(Double(seconds))
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var heartbeat = 0
        repeat {
            let active = try displayIDs(active: true)
            let online = try displayIDs(active: false)
            let displays: [[String: Any]] = Set(active + online).sorted().map { id in
                var properties: [String: Any] = [
                    "id": id,
                    "active": active.contains(id),
                    "online": online.contains(id),
                    "built_in": CGDisplayIsBuiltin(id) != 0,
                    "main": CGDisplayIsMain(id) != 0,
                    "asleep": CGDisplayIsAsleep(id) != 0
                ]
                if let mode = CGDisplayCopyDisplayMode(id) {
                    properties["mode_width"] = mode.width
                    properties["mode_height"] = mode.height
                    properties["pixel_width"] = mode.pixelWidth
                    properties["pixel_height"] = mode.pixelHeight
                    if mode.width > 0 && mode.height > 0 {
                        properties["scale_x"] = Double(mode.pixelWidth) / Double(mode.width)
                        properties["scale_y"] = Double(mode.pixelHeight) / Double(mode.height)
                    }
                }
                return properties
            }
            try emit([
                "event": "heartbeat",
                "timestamp": formatter.string(from: Date()),
                "elapsed_seconds": Date().timeIntervalSince(started),
                "heartbeat": heartbeat,
                "active_display_ids": active,
                "online_display_ids": online,
                "scale_definition": "pixels per display-mode unit",
                "displays": displays
            ])
            heartbeat += 1
            Thread.sleep(forTimeInterval: max(0, min(1, deadline.timeIntervalSinceNow)))
        } while Date() < deadline
        try emit([
            "event": "complete",
            "timestamp": formatter.string(from: Date()),
            "elapsed_seconds": Date().timeIntervalSince(started)
        ])
    }

    private static func displayIDs(active: Bool) throws -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        let countResult = active
            ? CGGetActiveDisplayList(0, nil, &count)
            : CGGetOnlineDisplayList(0, nil, &count)
        guard countResult == .success else {
            throw ProbeFailure(description: "Could not count displays (\(countResult.rawValue)).")
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        let listResult = active
            ? CGGetActiveDisplayList(count, &ids, &count)
            : CGGetOnlineDisplayList(count, &ids, &count)
        guard listResult == .success else {
            throw ProbeFailure(description: "Could not list displays (\(listResult.rawValue)).")
        }
        return Array(ids.prefix(Int(count))).sorted()
    }

    private static func emit(_ value: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
    }
}
