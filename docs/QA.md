# InsoMac QA

Verified on 14 November 2026. InsoMac remains a prototype with no public binary release. Closed-lid physical-panel illumination and fresh Codex capture/input remain unproven.

## Native CI

[Run 43561932870](https://github.com/underconnor/insomac/actions/runs/43561932870) passed all four jobs at source commit `e6d0abe7d6efa1fe52c3eccc3be170397b419500`:

| Runner | Actual macOS | Native architecture | Xcode | Result |
| --- | --- | --- | --- | --- |
| `macos-15` | 15.8.2 | arm64 | 16.4 | Passed |
| `macos-15-intel` | 15.7.9 | x86_64 | 16.4 | Passed |
| `macos-26` | 26.7.2 | arm64 | 26.6 | Passed |
| `macos-26-intel` | 26.6.1 | x86_64 | 26.6 | Passed |

Each job built both slices of the universal app, checked its identity, executable permissions, macOS 13 deployment metadata, and ad-hoc signature, then executed its native slice through the rejected-parent startup path. That path exits before graphics, assertions, or display creation. It establishes native loading and startup, not menu or private-display compatibility.

All jobs also passed:

- 22 session cases covering selection, rollback, failed-release retry, unavailable backends, and destruction.
- Six coordinator cases covering responsiveness, accepted request ordering, notification coalescing, and bounded Quit handling.
- Two process-I/O cases covering silent children, broken pipes, EOF, and bounded termination.
- Display-policy checks for initial secondary status, later main-display promotion, and the remaining metadata guards.
- Real IOKit assertion acquisition/readback/release and cleanup after normal exit and SIGKILL.
- Parent rejection and cleanup of a deliberately blocked owned worker.
- Three packaging regressions rejecting changed source, changed HEAD, or a newly dirty notarized checkout.
- Resource-profiler compilation, local-preview packaging, extracted-bundle verification, and rejection of missing notarization prerequisites.

The four CI candidates record the same captured build-input digest and clean source commit. Their checksums were verified after download. Logs, manifests, checksums, and candidate ZIPs are retained locally under ignored `build/qa/release-engineering-2026-11-14/ci-run-43561932870/`; GitHub artifacts have a 14-day retention period.

## Local build and graphical checks

The updated local bundle is version `0.1.0`, build `1`, with identifier `io.github.underconnor.insomac.prototype`. It compiles with Swift 6.4.2 and the macOS 27.2 SDK on Apple Silicon macOS 27.2.1. The universal executable is 448,352 bytes and the bundle occupies 452 KiB on disk. These sizes describe the local Xcode 27.2 build; CI toolchains produce their own recorded binaries.

The updated headless suite passes locally. The updated native-menu retest remains incomplete. The earlier bundle passed left-click, right-click, Control-click, and Keep Screen On toggling, but virtual activation through its menu failed the parent metadata guard. Updated and earlier bundles were both undiscoverable in a subsequent shared menu-bar environment; the updated app finished launching and its main thread was idle in the normal AppKit event loop. No successful updated-menu activation is inferred from those observations.

The app now presents Preparing, Starting, Stopping, Changing Mode, Checking, and Quitting activities with an hourglass. The README's rendered illustration shows resting states and mode choices only. Earlier light/dark illustration checks do not verify the current native menu or busy states.

## Historical virtual-display smoke checks

Earlier bounded worker tests created a temporary 1280 × 720 display, read complete mode metadata from its owner and a fresh observer, and preserved the physical display's mode, main status, and mirroring. Explicit stop, abrupt controlling-process exit, and abrupt owner exit restored the baseline topology. Unexpected owner loss produced Error with no owned resources remaining. Only owned test processes were terminated.

These results predate the current coordinator/readback changes and are retained as a historical baseline. They do not resolve the native-menu activation failure. A long-lived observer can see an active display ID while `CGDisplayCopyDisplayMode` returns no mode. Fresh-observer metadata does not prove capture-client discovery, fresh frames, input delivery, or physical illumination.

## Resource measurements

The longer profiler compiles on all four CI hosts, but a 60–120 second updated-app sample has not run. It records kernel RSS, physical footprint, and cumulative CPU deltas separately; physical footprint does not replace the under-50 MiB RSS target.

The earlier five-sample off-state baseline reported 73.08–73.13 MiB RSS, above that target. Reported CPU was initially 0.6%, then 0.0%, with cumulative CPU at 0:00.08. These short observations are historical, not sustained-performance results for the updated app.

## Distribution and remaining coverage

The current bundles and CI candidates use ad-hoc signatures. Developer ID signing, notarization, ticket stapling, and Gatekeeper acceptance have not completed. Missing credentials fail before a notarized candidate is built; a passing negative gate is not a signed release.

macOS 13 runtime, physical Intel hardware, the updated native menu and private-display path, VoiceOver, long sessions, battery/thermal behavior, lock behavior, and capture-client recovery still require separate verification. The macOS 13 minimum is a build/deployment target, not tested runtime coverage.

Global power overrides and other apps' assertions can affect sleep independently. They were left unchanged. No lid, forced sleep, lock, or physical-panel experiment establishes product acceptance. Verification has not installed a helper, registered login startup, changed power settings, or terminated an unrelated application.

Historical evidence and the private power-state attribution audit remain under ignored `build/qa/`. See [release preparation](RELEASE.md) for the candidate and signing workflow.
