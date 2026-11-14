# Implementation

## Scope

InsoMac is a native menu bar research prototype with two selectable modes. It does not meet the closed-lid physical-display and computer-use requirement. No privileged helper, global sleep override, or closed-lid technique is implemented.

The app uses Swift and AppKit with an `NSStatusItem`. It targets macOS 13 and builds `arm64` and `x86_64` executables into one app bundle. There is no SwiftUI, web view, third-party dependency, persistence, account, analytics, network request, launch agent, or animation timer.

## Session ownership

`KeepAwakeSession` owns assertion and virtual-display backends. A new session is always off in Keep Screen On. Selecting a different mode first stops all resources and leaves the new mode off. Cleanup failure keeps the old mode and error state. Mode selection is not persisted.

Both modes acquire `PreventUserIdleSystemSleep`, then `PreventUserIdleDisplaySleep`, through `IOPMAssertionCreateWithName`. Virtual mode first creates and verifies its display. The state becomes on only after all required resources succeed. A failed creation releases all resources acquired so far. These public idle assertions affect display idle sleep generally; virtual mode does not blank or independently control the physical panel.

Stopping attempts every release even if one fails. Failed handles remain owned for a later cleanup retry; errors never appear as on. A left click in that error state retries cleanup. A creation error with no remaining handle allows a fresh start. Starting cannot accumulate assertions while cleanup continues to fail. An already absent handle (`kIOReturnNotFound`) counts as released.

Normal AppKit termination calls `stop()`. Session destruction makes a final release attempt. macOS removes process-owned assertions after abrupt exit. Virtual ownership uses an unprivileged child process whose input pipe closes when the app exits. The child then releases its display and exits; macOS also removes its display if the child crashes. The bounded tests verify explicit stop, abrupt controlling-process exit, and abrupt display-owner exit. A hung app can retain its session until terminated.

There is no session timeout or automatic restart. Explicit system sleep, lid closure, shutdown, battery conditions, and thermal policy can override idle-sleep prevention. These assertions do not promise physical display continuity.

## Menu and accessibility

The status button handles left mouse-up as toggle, and right mouse-up or Control-click as menu. The native menu shows the state, mode-specific limitation, applicable action, mutually exclusive mode choices, and quit. It states that changing mode turns keep-awake off. Unsupported private interfaces disable the virtual choice with a reason. Errors offer details and a cleanup retry when resources remain. A custom accessibility action opens the menu.

`StatusPresentation` supplies the same labels and symbols to the menu and preview renderer. Off uses `moon.zzz`, on uses `cup.and.saucer.fill`, and error uses `exclamationmark.triangle.fill`. They are monochrome template images. The accessibility label includes the state and scope, so color is not required to understand status.

The app neither synthesizes user activity nor changes authentication, password, screen saver, or lock settings. It has no unlock path. Actual locked-screen behavior remains a manual QA item; idle display-sleep prevention should not be treated as a security policy.

## Experimental virtual display

`VirtualDisplayBridge.m` is an isolated original Objective-C wrapper. It resolves private classes at runtime and verifies every used selector's return and argument encodings before invoking it. There is no hard link to a private class. The current runtime's mode initializer uses 32-bit unsigned width and height arguments (`@32@0:8I16I20d24`), whereas the reference header declares `NSUInteger`. The first strict check rejected that discrepancy before creation; the bridge was corrected to the observed ABI. Unknown signatures remain unsupported.

The descriptor requests one secondary 1280 × 720 display at 60 Hz and 1× scale. Creation must return a new nonzero display ID, settings must apply, and readback must confirm active, online, awake, non-built-in, non-main, non-mirrored geometry and matching mode/pixel dimensions. The code never calls a display configuration API to move the main display, change mirroring, or alter a physical mode. macOS chooses the temporary display's placement.

Testing exposed process-local mode discovery behavior: a process initialized before display creation could see the ID and active flags but `CGDisplayCopyDisplayMode` returned nil, including after RunLoop processing and a reconfiguration callback. A fresh independent observer read the complete mode. Direct creation in an already initialized AppKit process failed the same readback. The app therefore starts a fresh copy of its own executable with a private owner argument, before AppKit initialization. This child retains and validates the display. No service or helper is installed or registered.

`NativeVirtualDisplay` uses bounded pipe exchanges for readiness, validation, and stop. On the app side, active/online flags and geometry must also match. The owner confirms full mode readback before the session can show on. Normal stop requests release and checks disappearance; missing acknowledgments cause an error and bounded termination of the owned child. A pending display ID or unknown creation baseline remains owned until disappearance is confirmed. The control pipe suppresses SIGPIPE so owner loss becomes an error rather than terminating the app.

The owner blocks on its control pipe while active; it has no polling or animation loop. EOF causes cleanup. An independent Dispatch process-exit source on a separate queue also exits the worker when its controlling app dies, even if the worker's main thread is blocked inside start, validation, or stop. The expected parent PID must match before monitoring is installed and again immediately after activation, closing the startup death race. The monitor is retained through all private operations. A controlled blocked-worker test verifies this mechanism; no native private-API hang was reproduced.

AppKit screen-change notifications and child termination trigger session validation. Runtime loss stops assertions and display ownership and exposes an error. There is no fallback to Keep Screen On.

This resolves ownership-process initialization for this prototype. It does not repair discovery in existing capture clients. A fresh observer's mode metadata is not evidence of fresh rendered frames, successful input, closed-lid survival, or physical illumination.

## Build and review

The app name and executable are `InsoMac`, in `build/InsoMac.app`. Its local bundle identifier is `io.github.underconnor.insomac.prototype`, using the confirmed GitHub owner namespace. This identifies a local prototype; it does not establish Apple Developer team or domain ownership. Notifications, error domains, and process-monitor queues use the `io.github.underconnor.insomac` namespace.

`scripts/build.sh` uses the selected Xcode SDK, Swift 6, and Clang with ARC. It compiles each architecture with deployment target 13.0 and warnings as errors, links the small bridge, combines binaries with `lipo`, validates the plist, and applies an ad-hoc local signature. It does not fetch dependencies or require an Xcode project. Full Xcode 16 or later is expected; Command Line Tools alone have not been validated.

`scripts/check.sh` is a single entry point for macOS checks. It builds the app, runs dependency-free test executables, checks bundle and running-app identity, launches and normally terminates its own app instance, and renders only its own state previews. New output goes to a dated `build/qa/insomac-*` directory; `INSOMAC_QA_DIR` can select a specific directory. Historical logs are preserved. A logged-in macOS graphics session is needed for the app lifecycle and AppKit preview checks. Developer ID signing and notarization are not configured.

`scripts/test-virtual-display.sh` is separate because it temporarily changes topology. It primes AppKit and screen metadata in a controlling test process, creates one virtual session at a time, reads full mode metadata from a fresh observer, and checks that physical display attributes are unchanged. It tests explicit stop, controlling-process SIGKILL, and display-owner SIGKILL. Each controlling test child has a twelve-second fail-safe. A full topology comparison follows every case, including failures. It records only display IDs and geometry/flags, never screen contents.

Generated app files and private logs stay under ignored `build/`. `Tools/RenderPreview.swift` paints `insomac-states-light.png` and `insomac-states-dark.png` from the app's labels and symbols. The preview script also copies them to `docs/assets/` for the README and source review. They are rendered illustrations, not screenshots of the native menu or desktop.

## Developer measurements

`scripts/measure-idle.sh` launches its own off-state app instance, waits for AppKit's finished-launch flag, takes five one-second-spaced `ps` samples, and requests normal termination. It reports RSS, reported CPU percent, and cumulative CPU time. RSS includes resident shared pages; these short samples do not establish sustained CPU use or physical memory footprint.

`scripts/probe-displays.sh [seconds]` compiles a separate CoreGraphics tool under `build/tools/`. It is never linked into the app. A run defaults to ten seconds and accepts a duration from one through 120 seconds. JSON lines include UTC timestamps, elapsed time, heartbeat, active and online display IDs, built-in/main/asleep flags, display-mode dimensions, pixel dimensions, and the pixel-to-mode scale ratio. No display name, serial number, UUID, image, or screen content is collected.

The probe makes read-only display queries and holds no keep-awake assertions. It cannot prove fresh GUI rendering, capture success, input delivery, physical panel illumination, or Codex computer use. A heartbeat can pause if the system sleeps; the next time the process runs after the deadline it finishes. Display lists are snapshots and can change during a hot-plug event. No lid, display-sleep, lock, or capture experiment was run here.

Global power overrides and other apps' assertions can affect sleep independently of this app. Creation, assertion ownership, and cleanup checks do not establish lid-close behavior under those conditions.

## Sources

- [Apple: IOPMAssertionCreateWithName](https://developer.apple.com/documentation/iokit/1557134-iopmassertioncreatewithname).
- [Apple: IOPMAssertionRelease](https://developer.apple.com/documentation/iokit/1557090-iopmassertionrelease).
- [Apple's IOPMLib header](https://github.com/apple-oss-distributions/IOKitUser/blob/main/pwr_mgt.subproj/IOPMLib.h), including idle-sleep and lid-close limits. The installed macOS 27.2 SDK header was also checked.

Apple's [power assertion implementation](https://github.com/apple-oss-distributions/PowerManagement/blob/main/pmconfigd/PMAssertions.c) is a reference for process ownership, not an application dependency.

The [DeskPad private header](https://github.com/Stengo/DeskPad/blob/main/DeskPad/CGVirtualDisplayPrivate.h), credited there to Khaos Tian, was reviewed for interface names and signatures. The [Dispres README](https://github.com/adevra/macOS-Dispres) was reviewed for limitations. No third-party implementation, header file, binary, or dependency was copied into this project; the bridge and ownership protocol are original code. Dispres's separate global sleep-setting prerequisite is not implemented.
