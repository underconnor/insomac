# InsoMac QA

Verified on 14 November 2026 for the [v0.1.0-preview.1 preview release](https://github.com/underconnor/insomac/releases/tag/v0.1.0-preview.1). Closed-lid built-in-panel illumination and fresh Codex capture/input remain unproven.

## Distribution artifact

| Item | Verified result |
| --- | --- |
| Package | `InsoMac-0.1.0-preview.1-universal.zip`, 152,546 bytes |
| Bundle | `io.github.underconnor.insomac.prototype`, version `0.1.0`, build `1` |
| Architectures | Universal arm64 and x86_64 |
| Minimum macOS | 13.0 in the plist and both Mach-O slices; bounded native/runtime/UI checks passed in an arm64 13.0 VM |
| Signing | Exact Developer ID Application identity/team, hardened runtime, secure timestamp, empty entitlements |
| Apple notarization | Accepted; status code zero, no issues |
| Ticket and assessment | Stapled ticket validates; Gatekeeper reports `Notarized Developer ID` |
| ZIP integrity | Checksum, extraction, executable permissions, signature, ticket, and Gatekeeper checks passed |

ZIP SHA-256:

```text
3cb10a665d41fda07dd2068e7f1820473cf27251d3989ffe9c64056208378aae
```

The app was compiled with Swift 6.4.2 and the macOS 27.2 SDK, then re-signed and packaged without recompilation. The manifest distinguishes the original build, the signed GUI-tested app, and the notarized export. Per-architecture comparison confirms matching code/data; signature allocation metadata is accounted for separately. Runtime policy and empty entitlements match the signed GUI-tested app. Later research-only commits are not represented as a rebuild.

## Native CI

[Main run 43564206723](https://github.com/underconnor/insomac/actions/runs/43564206723) passed all four jobs at code-reference commit `b54932f2018e0f976e37068d8e79dd983e11dda9`:

| Runner | Actual macOS | Native architecture | Xcode | Result |
| --- | --- | --- | --- | --- |
| `macos-15` | 15.8.2 | arm64 | 16.4 | Passed |
| `macos-15-intel` | 15.7.9 | x86_64 | 16.4 | Passed |
| `macos-26` | 26.7.2 | arm64 | 26.6 | Passed |
| `macos-26-intel` | 26.6.1 | x86_64 | 26.6 | Passed |

Each job built both slices and checked bundle identity, permissions, deployment metadata, and its ad-hoc build signature. It executed the native rejected-parent startup path, which exits before graphics, assertions, or display creation. This establishes native loading/startup on those hosts, not menu or private-display compatibility.

The suite passed 22 session cases, six serialized-coordinator cases, two bounded process-I/O cases, and display-policy checks. It also verified real IOKit assertion acquisition/release, normal/abrupt-exit cleanup, blocked-worker parent monitoring, three immutable-input packaging regressions, and Mach CPU-time scaling against independent `getrusage`. Profiler compilation, preview packaging, extracted-bundle checks, and rejection of missing notarization credentials passed on every runner.

## macOS 13 validation

A genuine macOS Ventura 13.0 (`22A380`) arm64 virtual machine passed the separate baseline: all 13 original artifact hashes matched, the original app's rejected-parent startup exited with status 2, and all eight native suites exited zero. This covers native loading and the core/IOKit/process/policy/timebase suites.

The final V3 check verified the exact release ZIP and executable hashes, bundle metadata, all-architecture Developer ID signature, team/identifier/runtime, native rejected-parent exit 2, and offline Gatekeeper acceptance as `Notarized Developer ID`. All mandatory checks passed and the runner exited zero. Guest stapler was explicitly unavailable because only a developer-tool shim was present; no toolchain was installed and no guest stapler pass is claimed. The host had already validated the exact package's stapled ticket. Earlier runner/tool-availability failures remain in the private evidence.

A separate normal AppKit smoke of the final candidate showed the moon/Off status icon, Keep Screen On selected, menu Off → On through Turn On, and removal of the menu/status icon after Quit while On. This is visual/native-input evidence. It is not an independent guest assertion-inventory audit, a private virtual-display test, physical hardware testing, or a lid/panel test.

## Signed native GUI and cleanup

An isolated Developer ID signed copy passed actual native AX/CGEvent interaction on Apple Silicon macOS 27.2.1:

- Left-click Off → On → Off, right-click and Control-click menus, and the menu's Turn On action.
- Accessible state/scope text, mode checkmarks, and exactly two owned idle-sleep assertions while On.
- Changing an active session in either direction stops it and leaves the selected mode Off.
- Virtual activation through the icon, with a fresh observer confirming 1280 × 720 logical and pixel dimensions.
- Off sent while Starting was visible, followed by Off with no resources.
- Normal menu Quit while Keep Screen On was active, with exit status zero and assertion cleanup.

The physical display's mode, main status, and mirroring were preserved. Final topology and pointer matched their starting state, with no owned assertion or process remaining. The signed run captured no screenshots. Earlier native-menu crops and the current light/dark rendered illustrations were visually checked for legibility; illustrations omit busy states and are not screenshots.

The current worker suite separately passed explicit stop, abrupt controlling-process exit, and abrupt owner exit. Each restored the starting topology; owner loss produced Error without retained resources. Graphical lifecycle checks passed accessory identity, launch Off, and normal AppKit termination.

A long-lived observer can still see an active display ID while `CGDisplayCopyDisplayMode` returns no mode. Fresh-observer metadata and native mouse-input success do not establish capture-client discovery, fresh captured frames, Codex Computer Use, or physical illumination.

## Bounded resource sample

A 60.004-second pre-signing off-state sample recorded 31 observations after a five-second settling period. No project assertion appeared, cleanup completed, and both read-only memory diagnostics succeeded. The final notarized package was not re-profiled.

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
