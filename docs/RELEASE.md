# Release preparation

The current preview ZIP is Developer ID signed, notarized, stapled, and accepted by Gatekeeper after extraction. Build 2 passed open-lid virtual display capture, targeted keys, and accessibility button actions in a fixture window. Window-targeted clicks reached the fixture on both attempts. The earlier global-coordinate Core Graphics method missed both attempts. Closed-lid operation, physical-panel illumination with the lid closed, and actual Codex capture and input remain unverified. [Download v0.1.0-preview.2](https://github.com/underconnor/insomac/releases/tag/v0.1.0-preview.2) · [QA results and checksum](QA.md)

To use the virtual display, right-click or Control-click the menu bar icon, select **Virtual Display (Experimental)**, and choose **Turn On**. When the app shows On, move a window onto the new display. Choose **Turn Off** when finished.

## Native checks

```sh
./scripts/check.sh --headless
```

Headless checks cover session logic, real process-owned IOKit assertions, abrupt-exit cleanup, the independent parent monitor, responsive serialized coordination, bounded pipe I/O, and display metadata policy. Bundle checks inspect both architectures, macOS 13 deployment metadata, and the local signature.

The packaged native executable also runs its rejected-parent startup path and must return status 2 before graphics, assertions, or display creation. This proves native loading and startup execution, not graphical or private-display compatibility. Graphical checks remain separate:

```sh
./scripts/test-graphics.sh
./scripts/test-virtual-display.sh
```

The native CI matrix uses `macos-15` and `macos-26` for arm64, and `macos-15-intel` and `macos-26-intel` for x86_64. Xcode 16.4 and 26.6 are selected explicitly. Action revisions are pinned. Actual host, toolchain, test, and package evidence is uploaded per job. macOS 13 remains a separate runtime requirement.

The earlier macOS 13.0 arm64 VM checks used preview.1 (build 1). They covered native startup, eight native suites, offline Gatekeeper, and a basic AppKit menu smoke. Build 2 targets 13.0, with runtime verification from the macOS 15/26 CI matrix and the macOS 27.2.1 open-lid host checks.

Build 2 passed all four jobs at `207df43dd6bbac70cba1ec56cd225667d03a70df`, including the bounded topology recovery and cleanup regressions. [Build 2 CI](https://github.com/underconnor/insomac/actions/runs/45206379996)

Runner labels and Xcode availability were checked against [GitHub's runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) and the [official runner images](https://github.com/actions/runner-images). Runner image updates can change patch versions; the workflow records what ran.

## Local preview candidate

```sh
./scripts/release.sh --mode local-preview --output build/release-candidate
```

Use an empty output directory. The script captures checkout identity and all relevant app/build inputs, then builds from an immutable copy. It rejects source, permission, or checkout changes after the build and before archive/manifest emission. Notarized candidates also require a clean committed checkout throughout.

The output includes a versioned `local-preview` ZIP, `SHA256SUMS`, `release-manifest.json`, and concrete `RELEASE_NOTES.md`. The archive is extracted and inspected again, including executable permissions and signatures. A local preview uses ad-hoc signing and is not notarized. No release is published by this command.

`INSOMAC_BUILD_DIR` selects a separate build directory. Historical QA and approved snapshot records under ignored `build/` are preserved.

## Scripted notarytool route

The following configuration contains references and public identifiers, not passwords:

- `INSOMAC_SIGNING_IDENTITY`: SHA-1 fingerprint of an existing valid Developer ID Application identity in the local Keychain.
- `INSOMAC_TEAM_ID`: matching ten-character team identifier.
- `INSOMAC_NOTARY_PROFILE`: a notarization credential profile already stored securely with `notarytool store-credentials`.

Provision certificates and credentials using Apple's secure account/Keychain tools. Do not place private keys, passwords, or tokens in source or logs.

```sh
./scripts/release.sh --mode notarized --preflight-only
./scripts/release.sh --mode notarized --output build/notarized-candidate
```

Missing or mismatched prerequisites fail before a candidate is built. The real path checks the identity and team, signs with hardened runtime and a secure timestamp, verifies the signature, submits with `notarytool --wait`, requires `Accepted`, inspects the notary log, staples and validates the ticket, and requires successful Gatekeeper assessment. It then rebuilds the ZIP from the stapled app and verifies the extracted archive again. No success is inferred from an upload or an ad-hoc signature.

The resulting name remains `notarized-candidate`; product acceptance and final publication review are separate. No stable binary, tag, or release is created automatically.

See Apple's [notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) and [command-line workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

## Existing Xcode-account route

This preview used a separate Xcode archive of the frozen validated app, without recompiling it. Local signing selected the verified Developer ID Application certificate by exact SHA-1, enabled hardened runtime and a secure timestamp, and added no entitlements. The archive's signing identity and team matched the real signature.

For an existing signed application archive, `xcodebuild -exportArchive` can use the account already signed into Xcode. Export options select `method=developer-id`, `destination=upload`, `signingStyle=manual`, the exact `signingCertificate` fingerprint and `teamID`, and `stripSwiftSymbols=false`. This entitlement-free app needs no provisioning profile. Automatic/cloud signing and new certificate creation are not part of this route.

```sh
xcodebuild -exportArchive \
  -archivePath "$INSOMAC_ARCHIVE_PATH" \
  -exportOptionsPlist "$INSOMAC_EXPORT_OPTIONS" \
  -exportPath "$INSOMAC_UPLOAD_OUTPUT" \
  -allowProvisioningUpdates

xcodebuild -exportNotarizedApp \
  -archivePath "$INSOMAC_ARCHIVE_PATH" \
  -exportPath "$INSOMAC_NOTARIZED_OUTPUT"
```

`-allowProvisioningUpdates` permits developer-site communication; manual targets may download missing profiles. Use the exact existing certificate and explicit manual signing rather than enabling automatic resource creation. Native Keychain access may require the user's password in the macOS dialog; never capture it or change key-access settings to bypass the prompt.

Upload once and retain the submission and distribution logs. Poll that existing submission; `-exportNotarizedApp` exports an already notarized archive and does not submit a new one. This preview's Apple job was Accepted with status code zero and no issues. The exported ticket validated, Gatekeeper reported `Notarized Developer ID`, and the extracted final ZIP passed the same checks. Empty-entitlement, certificate/team, runtime/timestamp, and code/data comparisons also passed. The original archives and GUI-tested app were preserved separately.

Signing changes executable signature metadata. The manifest distinguishes the original build, signed GUI-tested app, and notarized export; later research-documentation commits are not represented as a rebuild. Keep the exact verified ZIP unchanged for older-OS validation and publication.

Apple documents this route in its [Developer ID overview](https://developer.apple.com/developer-id/), [Xcode 15 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-15-release-notes/), and [WWDC21 distribution session](https://developer.apple.com/videos/play/wwdc2021/10204/). See [TN3125](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles) for the entitlement/provisioning boundary.

## Bounded resource profile

```sh
./scripts/measure-idle.sh 60 build/qa/profile-run
```

The tool launches only its owned app off, waits five seconds for startup loading, then samples for 60–120 seconds. `proc_pid_rusage(RUSAGE_INFO_V4)` reports RSS bytes, the kernel physical-footprint ledger, and cumulative user/system CPU in Mach ticks. The tool records those ticks and the host's `mach_timebase_info`, scales the delta to nanoseconds, and divides by measured elapsed time for average one-core CPU. The 50 MiB RSS target remains an RSS target; physical footprint does not replace it.

Apple XNU's [rusage implementation](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/osfmk/kern/bsd_kern.c#L1260) copies the [task's Mach-time CPU counters](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/osfmk/kern/task.c#L6811). A regression verifies non-unit scaling and compares a native CPU-load fixture with independent `getrusage`, which prevents an Intel 1:1 timebase from hiding an Apple Silicon unit error.

Read-only `footprint` and `vmmap -summary` diagnostics are bounded and confined to the owned app. Permission failures are reported instead of elevated. The tool verifies no project keep-awake assertions, requests normal app termination, and reports cleanup. It captures no screen content. `INSOMAC_APP_PATH` selects an isolated app copy; `--compile-only` compiles the profiler without launching anything.
