import AppKit

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let coordinator: SessionCoordinator
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let stateItem = NSMenuItem()
    private let toggleItem = NSMenuItem()
    private let errorItem = NSMenuItem()
    private let scopeItem = NSMenuItem()
    private var modeItems: [NSMenuItem] = []
    private let unavailableItem = NSMenuItem()

    init(coordinator: SessionCoordinator) {
        self.coordinator = coordinator
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        menu.autoenablesItems = false
        menu.delegate = self
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        scopeItem.isEnabled = false
        menu.addItem(scopeItem)
        menu.addItem(.separator())
        toggleItem.target = self
        toggleItem.action = #selector(toggle)
        menu.addItem(toggleItem)
        errorItem.title = "Show Error…"
        errorItem.target = self
        errorItem.action = #selector(showError)
        menu.addItem(errorItem)
        menu.addItem(.separator())
        for (index, mode) in KeepAwakeMode.allCases.enumerated() {
            let item = NSMenuItem(title: mode.rawValue, action: #selector(selectMode(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            modeItems.append(item)
            menu.addItem(item)
        }
        unavailableItem.isEnabled = false
        menu.addItem(unavailableItem)
        let help = NSMenuItem(title: "Changing mode turns keep-awake off", action: nil, keyEquivalent: "")
        help.isEnabled = false
        menu.addItem(help)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit InsoMac", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityCustomActions([
                NSAccessibilityCustomAction(name: "Open Menu", target: self, selector: #selector(openMenu))
            ])
        }
        NotificationCenter.default.addObserver(self, selector: #selector(displaysChanged(_:)),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(displaysChanged(_:)),
                                               name: .virtualDisplayOwnerDidExit, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(workspaceDidWake(_:)),
                                                           name: NSWorkspace.didWakeNotification, object: NSWorkspace.shared)
        coordinator.onChange = { [weak self] _ in self?.refresh() }
        refresh()
    }

    func menuWillOpen(_ menu: NSMenu) {
        coordinator.validateResources()
        refresh()
    }

    @objc private func displaysChanged(_ notification: Notification) {
        coordinator.validateResources()
        refresh()
    }

    @objc nonisolated private func workspaceDidWake(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.coordinator.validateResources() }
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard KeepAwakeMode.allCases.indices.contains(sender.tag) else { return }
        coordinator.selectMode(KeepAwakeMode.allCases[sender.tag])
        refresh()
    }

    @objc private func handleClick() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            _ = openMenu()
        } else {
            toggle()
        }
    }

    @objc private func openMenu() -> Bool {
        guard let button = statusItem.button else { return false }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
        return true
    }

    @objc private func toggle() {
        coordinator.toggle()
        refresh()
    }

    @objc private func showError() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Keep-awake needs attention"
        let snapshot = coordinator.snapshot
        let nextStep = snapshot.hasResources
            ? "Choose Release Again to retry cleanup, or quit InsoMac."
            : "Choose Try Again to start a new session."
        alert.informativeText = snapshot.errorMessages.joined(separator: "\n") + "\n\n" + nextStep
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func refresh() {
        let snapshot = coordinator.snapshot
        let presentation = StatusPresentation(state: snapshot.state, hasResources: snapshot.hasResources,
                                              mode: snapshot.mode, activity: snapshot.activity,
                                              requestedOn: snapshot.requestedOn)
        let image = NSImage(systemSymbolName: presentation.symbol, accessibilityDescription: presentation.label)
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = presentation.label + " Click to toggle. Right-click for menu."
        statusItem.button?.setAccessibilityLabel(presentation.label)
        statusItem.button?.setAccessibilityValue(snapshot.activity?.rawValue ?? snapshot.state.rawValue)
        stateItem.title = presentation.title
        scopeItem.title = presentation.scope
        toggleItem.title = presentation.action
        toggleItem.isEnabled = !coordinator.isQuitting
        errorItem.isHidden = snapshot.errorMessages.isEmpty
        for (index, item) in modeItems.enumerated() {
            let mode = KeepAwakeMode.allCases[index]
            item.state = snapshot.mode == mode ? .on : .off
            item.isEnabled = !snapshot.isBusy && !coordinator.isQuitting
                && (mode != .virtualDisplay || snapshot.virtualDisplayUnavailableReason == nil)
            item.toolTip = mode.limitation
        }
        unavailableItem.isHidden = snapshot.virtualDisplayUnavailableReason == nil
        unavailableItem.title = snapshot.virtualDisplayUnavailableReason ?? ""
    }
}
