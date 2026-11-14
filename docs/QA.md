# InsoMac QA

Verified on 14 November 2026. This is a local prototype review, not a release certification.

## Identity and build

| Item | Result |
| --- | --- |
| App and executable | `build/InsoMac.app`, `Contents/MacOS/InsoMac` |
| Bundle identifier | `io.github.underconnor.insomac.prototype` |
| Version | `0.1.0` / build `1` |
| Architectures | Universal `arm64` and `x86_64`; both compiled successfully |
| Minimum macOS | `13.0` in the plist and both Mach-O slices |
| Local host | Apple Silicon, macOS `27.2.1` (`26B8132`) |
| Toolchain | Apple Swift `6.4.2`, macOS SDK `27.2`, selected Xcode tools |
| Signing | Ad-hoc; identifier matches the bundle; no Developer ID team |
| Distribution | No notarization or public binary release |

`plutil -lint`, `codesign --verify --strict`, architecture inspection, and shell syntax checks passed. Bundle identity is local prototype metadata, not evidence of Apple Developer team ownership.

## Existing checks

`./scripts/check.sh` passed with warnings treated as errors. Existing checks now also verify the renamed bundle, executable, display name, running-app identity, and accessibility-label prefix. No new test suite was added for the rename.

- All 22 session tests passed, including selection, rollback, release retry, runtime unavailability, and deinitialization.
- Distinct state symbols, accessible labels, and mode-specific limitations passed.
- Both real IOKit assertions were acquired, read back, released, and confirmed absent.
- Assertion cleanup after normal process exit and SIGKILL passed for owned test processes.
- Parent identity rejection and cleanup of a deliberately blocked worker passed. No native API hang was reproduced.
- The renamed app launched off as a menu bar accessory and terminated normally.
- Light and dark rendered previews were regenerated and visually reviewed. Names, checkmarks, mode limits, and actions were legible without clipping.

The README references `docs/assets/insomac-states-light.png`; the dark variant is alongside it. These files are outside ignored build output and can be included with source. They are rendered previews, not desktop screenshots.

## Experimental virtual display

The existing bounded smoke test passed after initializing AppKit and screen metadata in the controlling process. Each case created one temporary 1280 × 720 display, verified full mode metadata through its isolated owner and a fresh independent observer, and preserved the physical display's mode, main status, and mirroring.

Explicit stop, abrupt controlling-process exit, and abrupt display-owner exit all restored exact baseline topology. Unexpected owner loss produced Error with no owned resources remaining. Only owned test processes were terminated.

The final read-only cleanup audit found zero project workers and zero project assertions. Display topology matched the pre-test baseline. Existing system power state and unrelated applications were left unchanged.

A long-lived observer can still see an active ID while receiving no mode from `CGDisplayCopyDisplayMode`. Isolated ownership enables this prototype's own full readback, and a fresh observer confirms metadata visibility. This does not prove discovery by an existing capture client, fresh frames, input delivery, closed-lid survival, or physical-panel illumination.

## Size and bounded resource sample

The universal executable is **363,616 bytes**. The app occupies **368 KiB** on disk. `build/InsoMac-prototype.zip` is **109,666 bytes** and passed `unzip -t`.

Five one-second-spaced off-state samples reported **73.08–73.13 MiB RSS**. CPU was initially `0.6%`, then `0.0%` in the remaining samples; displayed cumulative CPU stayed at `0:00.08`. The finished-launch flag was observed after `0.110` seconds with 50 ms polling. These are short local observations, not sustained-performance or launch benchmarks. The initial under-50 MiB RSS target remains unmet.

The virtual smoke's controlling test process increased from 29,920 KiB before activation to 31,808 KiB during active samples; its separate display owner used 11,520 KiB at readiness. Summed additional RSS was about 13.09 MiB. This test-controller measurement excludes WindowServer/GPU cost and may count shared pages twice; it is not total production-app overhead.

## Attribution and remaining limits

Global power overrides and other apps' assertions can invalidate sleep attribution. They were left unchanged. Verification covers ownership, display metadata, and cleanup; no lid, sleep, lock, physical-panel, or computer-use conclusion follows from these checks.

- Physical Keep Screen On behavior is limited to the open-lid idle-sleep path.
- Closed-lid physical illumination and fresh Codex capture/input remain unproven in both modes.
- Private virtual interfaces have no universal compatibility guarantee. Intel and macOS 13 execution remain untested.
- Actual mouse/keyboard menu interaction, VoiceOver, long sessions, battery and thermal overrides, lock behavior, and capture-client recovery need human hardware testing.
- No power settings, login registration, privileged helper, or unrelated application was changed by this verification.

## Evidence retention

The rename run is recorded under ignored `build/qa/insomac-rename-2026-11-14/`. Earlier logs and the private power-state attribution audit are preserved. Pre-rename QA notes are retained there separately; historical measurements and captured names were not rewritten as current InsoMac evidence.

Only references to unrelated third-party projects retain the former name in the public text. Obsolete generated app, archive, slice, and preview artifacts were removed after the renamed build passed.
