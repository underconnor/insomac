# InsoMac QA

The 24 November 2026 build 2 checks verified open-lid virtual display capture, targeted keyboard input, accessibility actions, window-targeted clicks, and cleanup in the normal signed app. Clicks made with the earlier global-coordinate Core Graphics method missed the test window. Closed-lid operation, physical panel illumination with the lid closed, and actual Codex capture and input remain unverified. [v0.1.0-preview.2](https://github.com/underconnor/insomac/releases/tag/v0.1.0-preview.2)

## Distribution artifact

| Item | Verified result |
| --- | --- |
| Package | `InsoMac-0.1.0-preview.2-universal.zip`, 177,973 bytes |
| Bundle | `io.github.underconnor.insomac.prototype`, version `0.1.0`, build `2` |
| Architectures | Universal arm64 and x86_64 |
| Minimum macOS | 13.0 in the plist and both Mach-O slices. The 13.0 VM checks used build 1. |
| Signing | Exact Developer ID Application identity/team, hardened runtime, secure timestamp, empty entitlements |
| Apple notarization | Accepted; status code zero, no issues |
| Ticket and assessment | Stapled ticket validates; Gatekeeper reports `Notarized Developer ID` |
| ZIP integrity | Checksum, extraction, executable permissions, signature, ticket, and Gatekeeper checks passed |

ZIP SHA-256

```text
1a144647cd7299cc3c880ce9ccba762160098f90345df87a33e06b85612a7a97
```

The app was compiled with Swift 6.4.2 and the macOS 27.2 SDK. The manifest records the source commit and notarized executable hash. Per-architecture comparison verified that the notarized export matches the compiled code and data after accounting for signature allocation metadata.

## Native CI

[Build 2 run 45206379996](https://github.com/underconnor/insomac/actions/runs/45206379996) passed all four jobs at commit `207df43dd6bbac70cba1ec56cd225667d03a70df`.

| macOS runners | Architectures | Xcode | Result |
| --- | --- | --- | --- |
| 15 | arm64 and x86_64 | 16.4 | Passed |
| 26 | arm64 and x86_64 | 26.6 | Passed |

Each job built both slices and checked bundle identity, permissions, deployment metadata, and its ad-hoc build signature. It executed the native rejected-parent startup path, which exits before graphics, assertions, or display creation. This establishes native loading/startup on those hosts, not menu or private-display compatibility.

The suite passed 22 session cases, ten coordinator cases, bounded process I/O, display policy, and real IOKit assertion cleanup. The new cases simulate transient recovery with the same owner and assertions, cleanup after persistent or terminal failure, and retry cancellation on Off or Quit. Packaging and extracted-bundle checks also passed.

## Build 2 open-lid virtual desktop

On Apple Silicon macOS 27.2.1, the normal signed and notarized app started Off. The test selected **Virtual Display (Experimental)** and used **Turn On**. The app owned an active 1280 × 720 secondary display and two idle-sleep assertions while On.

- A display-filtered ScreenCaptureKit live stream and screenshots of the exact test window showed the expected changing marker on all four samples. Display screenshots also included the fixture marker.
- The background test window received targeted key events and accessibility button presses on all four samples. Tagged clicks created as window-numbered AppKit `NSEvent` events retained window-local coordinates and reached the target view on both attempts when posted via `CGEvent.postToPid`. Clicks constructed directly with global coordinates in Core Graphics missed both attempts. The pointer stayed in place during all four samples. The menu bar right-click worked separately.
- **Turn Off** restored the original display topology and released both assertions. After **Quit InsoMac**, the audit found no owned assertions or processes.

The lid remained open and macOS reported the built-in display active and awake. The test used a private fixture window and standalone capture and input tools. No Codex session or closed-lid capture was exercised. The comparison is recorded locally in `build/qa/virtual-desktop-2026-11-24/normal-open-20261123T154044Z.jsonl`. The earlier global-coordinate-only run is retained in `normal-open-20261123T153604Z.jsonl` in the same directory.

## Earlier macOS 13 validation (build 1)

A genuine macOS Ventura 13.0 (`22A380`) arm64 virtual machine passed the separate baseline: all 13 original artifact hashes matched, the original app's rejected-parent startup exited with status 2, and all eight native suites exited zero. This covers native loading and the core/IOKit/process/policy/timebase suites.

The final V3 check verified the exact preview.1 ZIP and executable hashes, bundle metadata, all-architecture Developer ID signature, team/identifier/runtime, native rejected-parent exit 2, and offline Gatekeeper acceptance as `Notarized Developer ID`. All mandatory checks passed. Guest stapler was unavailable. The host verified the stapled ticket. Build 2 has no macOS 13 runtime result.

A separate normal AppKit smoke of the final candidate showed the moon/Off status icon, Keep Screen On selected, menu Off → On through Turn On, and removal of the menu/status icon after Quit while On. This is visual/native-input evidence. It is not an independent guest assertion-inventory audit, a private virtual-display test, physical hardware testing, or a lid/panel test.

## Earlier signed native GUI and cleanup (build 1)

An isolated Developer ID signed copy passed actual native AX/CGEvent interaction on Apple Silicon macOS 27.2.1:

- Left-click Off → On → Off, right-click and Control-click menus, and the menu's Turn On action.
- Accessible state/scope text, mode checkmarks, and exactly two owned idle-sleep assertions while On.
- Changing an active session in either direction stops it and leaves the selected mode Off.
- Virtual activation through the icon, with a fresh observer confirming 1280 × 720 logical and pixel dimensions.
- Off sent while Starting was visible, followed by Off with no resources.
- Normal menu Quit while Keep Screen On was active, with exit status zero and assertion cleanup.

The physical display's mode, main status, and mirroring were preserved. Final topology and pointer matched their starting state, with no owned assertion or process remaining. The signed run captured no screenshots. Earlier native-menu crops and the current light/dark rendered illustrations were visually checked for legibility; illustrations omit busy states and are not screenshots.

The worker suite separately passed explicit stop, abrupt controlling-process exit, and abrupt owner exit. Each restored the starting topology. Owner loss produced Error without retained resources. Graphical lifecycle checks passed accessory identity, launch Off, and normal AppKit termination.

A long-lived observer can still see an active display ID while `CGDisplayCopyDisplayMode` returns no mode. Fresh-observer metadata and native mouse-input success do not establish capture-client discovery, fresh captured frames, Codex Computer Use, or physical illumination.

## Bounded resource sample

A 60.004-second build 1 pre-signing off-state sample recorded 31 observations after a five-second settling period. No project assertion appeared, cleanup completed, and both read-only memory diagnostics succeeded. Build 2 has no equivalent resource sample.

| Measurement | Observation |
| --- | --- |
| RSS | 73.17–73.53 MiB; the under-50 MiB target remains unmet |
| Physical footprint | 13.27–13.64 MiB; a separate kernel ledger |
| CPU delta | 7.923 ms, averaging about 0.0132% of one core |
| Finished-launch observation | 0.378 seconds with 50 ms polling; one observation, not a benchmark |

Raw CPU ticks were corrected using the independently measured host Mach timebase, 125/3 ns per tick. Original evidence is preserved, with the derivation in `corrected-summary.json`. The profiler now records ticks and timebase explicitly; its unit/non-unit conversion and native `getrusage` regression pass locally and on all four CI hosts.

The memory map reports about 13.4 MiB dirty/physical footprint and 7.9 MiB resident malloc zones, alongside shared framework/cache mappings. Mapping totals cannot be summed as process RSS or used to attribute the target gap exactly. RSS varied by less than 0.4 MiB during the minute; no long-session conclusion follows. No app optimization has been made from this sample.

## Remaining coverage and retained evidence

Physical Intel GUI behavior, macOS 13 private-display behavior, VoiceOver, long sessions, battery/thermal behavior, lock behavior, and capture-client recovery require separate verification. No closed-lid, physical-panel, or Codex continuity claim follows from signing, notarization, native GUI tests, or source research.

Global power overrides and other apps' assertions can affect sleep independently. These checks installed no helper or login item, changed no persistent power setting, and terminated no unrelated application.

CI logs and candidates, signed GUI evidence, source/payload comparisons, Apple distribution logs, resource data, and the exact prerelease ZIP are retained under ignored `build/qa/`. The key directories are `release-engineering-2026-11-14/`, `signed-native-gui-regression-2026-11-14/`, `macos13-runtime-2026-11-14/`, and the separately retained earlier native-menu reports. GitHub CI artifacts have a 14-day retention period. See [release preparation](RELEASE.md) for the two signing workflows.
