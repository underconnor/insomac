import AppKit

@MainActor
final class PreviewView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        drawText("InsoMac", x: 24, y: 20, size: 22, weight: .semibold)
        drawText("Local research prototype · Two modes · Closed-lid continuity unverified", x: 24, y: 52, size: 13, secondary: true)

        let presentations = [
            StatusPresentation(state: .off, hasResources: false, mode: .screen),
            StatusPresentation(state: .on, hasResources: true, mode: .virtualDisplay),
            StatusPresentation(state: .error, hasResources: true, mode: .virtualDisplay)
        ]
        for (index, presentation) in presentations.enumerated() {
            let x = CGFloat(24 + index * 376)
            let card = NSRect(x: x, y: 88, width: 352, height: 352)
            NSColor.controlBackgroundColor.setFill()
            NSBezierPath(roundedRect: card, xRadius: 12, yRadius: 12).fill()
            let image = NSImage(systemSymbolName: presentation.symbol, accessibilityDescription: presentation.label)?
                .withSymbolConfiguration(.init(paletteColors: [.labelColor]))
            image?.draw(in: NSRect(x: x + 18, y: 104, width: 24, height: 24), from: .zero,
                        operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            drawText(presentation.state.rawValue, x: x + 54, y: 106, size: 16, weight: .semibold)
            drawText(presentation.title, x: x + 18, y: 150, size: 13)
            drawText(presentation.scope, x: x + 18, y: 174, size: 11, secondary: true)
            NSColor.separatorColor.setFill()
            NSRect(x: x + 18, y: 202, width: 316, height: 1).fill()
            drawText(presentation.action, x: x + 18, y: 217, size: 13)
            if presentation.state == .error {
                drawText("Show Error…", x: x + 18, y: 245, size: 13)
            }
            for (modeIndex, mode) in KeepAwakeMode.allCases.enumerated() {
                let mark = mode == presentation.mode ? "✓ " : "   "
                drawText(mark + mode.rawValue, x: x + 18, y: CGFloat(287 + modeIndex * 26), size: 13)
            }
            drawText("Changing mode turns keep-awake off", x: x + 18, y: 348, size: 11, secondary: true)
            drawText("Quit InsoMac", x: x + 18, y: 402, size: 13)
        }
        drawText("State preview using the app's labels and symbols. The running app uses a native menu.",
                 x: 24, y: 464, size: 11, secondary: true)
    }

    private func drawText(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat,
                          weight: NSFont.Weight = .regular, secondary: Bool = false) {
        (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: secondary ? NSColor.secondaryLabelColor : NSColor.labelColor
        ])
    }
}

@main
struct RenderPreview {
    @MainActor
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw NSError(domain: "Preview", code: 1, userInfo: [NSLocalizedDescriptionKey: "Pass an output directory."])
        }
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            let view = PreviewView(frame: NSRect(x: 0, y: 0, width: 1176, height: 496))
            view.appearance = NSAppearance(named: appearance)
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                throw NSError(domain: "Preview", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create preview image."])
            }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "Preview", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not encode preview image."])
            }
            let output = directory.appendingPathComponent("insomac-states-\(name).png")
            try data.write(to: output)
            print("Rendered \(output.path)")
        }
    }
}
