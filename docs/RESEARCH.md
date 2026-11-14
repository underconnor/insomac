# InsoMac: sleep and display research

Research conducted 13 November 2026; naming updated 14 November 2026. Primary documentation and original source were reviewed. Research did not change persistent power settings, physical display settings, login items, or helpers. Bounded implementation tests created and removed temporary virtual displays.

## What is established

**Idle sleep prevention is straightforward.** Public IOKit assertions can hold off idle system and display sleep. Apple's documentation explicitly leaves lid closure, manual sleep, and low-battery sleep outside the idle-system assertion. The current SDK also calls the older PreventSystemSleep assertion unsupported. This supports a small process-owned implementation with automatic cleanup when the process exits. [IOPMLib.h](https://github.com/apple-oss-distributions/IOKitUser/blob/323ead896d04424f87184d8f6ff0cce811aab106/pwr_mgt.subproj/IOPMLib.h), [Apple QA1340](https://developer.apple.com/library/archive/qa/qa1340/_index.html)

**Keeping a process awake does not prove that computer use works.** Apple developer support describes SCScreenshotManager failing when a display sleeps while the application's server keeps running. This supports testing display availability separately, but does not identify the capture path used by a particular Codex installation. [Apple DTS discussion](https://developer.apple.com/forums/thread/827059)

**A lit physical panel and a usable desktop are distinct.** Apple High Performance Screen Sharing can use virtual displays while hardware displays are blanked. That feature requires Apple silicon and macOS Sonoma or later; it does not establish a general-purpose display API or guarantee Codex compatibility. Apple's ordinary closed-lid display guidance specifies an external display, a power source, and external keyboard/mouse. Neither addresses the requested battery-only, closed built-in panel behavior. [Screen Sharing options](https://support.apple.com/en-mn/guide/mac-help/mchl1883115d/mac), [external display guidance](https://support.apple.com/en-us/102501)

**Codex's lock support is a separate concern.** OpenAI documents background computer use on macOS and opt-in locked use. Those are not a closed-lid/no-display guarantee. This project must preserve screen-lock security and test the actual computer-use path rather than infer success from a shell job. [Computer Use](https://learn.chatgpt.com/docs/computer-use), [21 May 2026 changelog entry](https://learn.chatgpt.com/docs/changelog)

## Approaches compared

| Approach | Useful evidence | Limitation |
| --- | --- | --- |
| Public IOKit assertions | Supported idle system/display holds; process-owned lifetime | Cannot promise lid-closed operation |
| Privileged SleepDisabled setting | Used by several closed-lid utilities | Global, persistent state; no promise of an active display |
| Private clamshell override | Used by Amphetamine tooling | Shared state, private API, OS/hardware variability |
| External display | Apple's supported closed-lid setup | Extra hardware and power; does not light the built-in panel |
| Virtual display | A separate drawable desktop can be created by existing tools | Host creation uses private APIs; actual capture and lid behavior need tests |

### Global sleep control

Apple's pmset implementation writes SleepDisabled through IOPMSetSystemPowerSetting. That implementation requires root and persists a system-wide preferences dictionary. powerd reapplies the setting at startup. A restart therefore cannot be promised to restore normal sleep. It is not a process-owned assertion. [pmset](https://github.com/apple-oss-distributions/PowerManagement/blob/d415e45501842834a280930c3eed9186544a67f0/pmset/pmset.m#L798-L809), [persistence](https://github.com/apple-oss-distributions/IOKitUser/blob/323ead896d04424f87184d8f6ff0cce811aab106/pwr_mgt.subproj/IOPMEnergyPrefs.c#L1622-L1660), [powerd startup](https://github.com/apple-oss-distributions/PowerManagement/blob/d415e45501842834a280930c3eed9186544a67f0/pmconfigd/PMSettings.m#L1149-L1162), [reapplication](https://github.com/apple-oss-distributions/PowerManagement/blob/d415e45501842834a280930c3eed9186544a67f0/pmconfigd/PMSettings.m#L1330-L1347)

Published XNU checks userDisabledAllSleep before its low-battery and thermal sleep exceptions. This indicates that the switch can suppress those sleep paths; it does not mean hardware shutdown can be prevented. This is source evidence, not a promise about every currently shipping kernel. The setting is too broad to present as a harmless equivalent of caffeinate. [Sleep checks](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/iokit/Kernel/IOPMrootDomain.cpp#L7664-L7731)

If this route is selected later, use a narrowly scoped authenticated helper, an independently enforced session lease, original-state tracking, verified restoration on crash/restart/uninstall, and explicit handling of other utilities changing the same setting. Renewing a lease need not impose a maximum user session duration. Safety policy and battery cutoffs require an explicit product decision. SMAppService provides the macOS 13+ helper registration path, subject to user approval. [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)

### Displays

No supported portable API for keeping the closed built-in panel illuminated was established. Public display APIs can report whether a display is active, online, built-in, or sleeping; they do not establish such an override. Virtualization graphics APIs describe displays inside a VM, rather than an extra display in the host desktop. [Quartz Display Services](https://developer.apple.com/documentation/coregraphics/quartz-display-services), [Virtualization graphics](https://developer.apple.com/documentation/virtualization/graphics)

DeskPad creates and retains a CGVirtualDisplay and captures its separate display ID. Its own private header makes the compatibility tradeoff explicit. Dispres documents clamshell-oriented virtual display behavior and Intel/Apple silicon support. These are useful experiments, not an Apple support contract or evidence that Codex will capture the intended display. [DeskPad header](https://github.com/Stengo/DeskPad/blob/main/DeskPad/CGVirtualDisplayPrivate.h), [DeskPad implementation](https://github.com/Stengo/DeskPad/blob/main/DeskPad/Frontend/Screen/ScreenViewController.swift), [Dispres](https://github.com/adevra/macOS-Dispres)

Dispres requires a separate, manual privileged SleepDisabled setting before closed-lid use. Its virtual display alone does not supply that behavior. The app watches lid state, promotes a virtual display to main on closure, and returns to the built-in display on reopening. Its source explicitly describes the closed built-in panel as off even when it remains listed as active. Thus neither an active-display flag nor a virtual display proves physical illumination. [Pinned prerequisite](https://github.com/adevra/macOS-Dispres/blob/056384069edf8851629aee957f9a3ab0469c2b9f/README.md), [lid handling and panel comments](https://github.com/adevra/macOS-Dispres/blob/056384069edf8851629aee957f9a3ab0469c2b9f/Sources/Dispres/Services/RecoveryService.swift#L220)

The local virtual-mode experiment is limited to resource ownership: create one temporary display, verify configuration, then remove it and verify the original topology returns, including after abrupt owner exit. It does not change the main display, mirror a physical display, or change global sleep settings. This is an implementation stage, not a substitute for the requested closed-lid behavior. A later implementation needs separate evidence for sleep control, desktop handoff, fresh capture, input routing, repeated reopening, and physical-panel behavior.

## Related projects

- [KeepingYouAwake](https://github.com/newmarcel/KeepingYouAwake): useful minimal menu bar precedent; explicitly excludes closed-lid sleep prevention.
- [keepawake](https://github.com/ecc521/keepawake): combines global sleep control, concurrent-session locking, and battery/thermal cutoffs; acknowledges a final killed process can leave sleep disabled.
- [Sleepless](https://github.com/thisissyu/sleepless): native UI around the same global setting. Its claim that reboot clears the setting conflicts with the published Apple persistence path above.
- [Amphetamine Enhancer](https://github.com/x74353/Amphetamine-Enhancer): private clamshell override and a separate recovery process; useful recovery precedent, not universal compatibility evidence.
- [ObservedObserver/Macchiato](https://github.com/ObservedObserver/Macchiato): a related coding-agent keep-awake app with a privileged helper. Its README describes manual crash recovery; the reviewed helper toggles the global setting. No code was copied.
- [matootie/macchiato](https://github.com/matootie/macchiato): a keep-awake app using caffeinate and macchiatoapp.com.

## Next evidence needed

The release blocker is fresh, controllable GUI rendering across lid changes on the actual target Mac, followed by compatibility testing. A heartbeat, an accessibility tree, or a potentially cached screenshot is insufficient. Start with a disposable test window, verify fresh changing content and successful input, and record display state alongside those observations. Physical lid closure and older/Intel hardware remain manual test requirements. Current mode descriptions must distinguish open-lid physical-screen support from unverified closed-lid virtual-display behavior.

An actual Codex Computer Use session and physical lid testing are still needed before making a compatibility claim. The local verification completed so far covers process assertions and display lifetime, not end-to-end capture or input.
