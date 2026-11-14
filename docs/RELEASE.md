# Release preparation

The packaging workflow produces candidates, not a claim that closed-lid physical illumination or computer use works. Those product requirements remain unverified. Signing and notarization do not establish them.

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

Runner labels and Xcode availability were checked against [GitHub's runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) and the [official runner images](https://github.com/actions/runner-images). Runner image updates can change patch versions; the workflow records what ran.

## Local preview candidate

```sh
./scripts/release.sh --mode local-preview --output build/release-candidate
```

Use an empty output directory. The script captures checkout identity and all relevant app/build inputs, then builds from an immutable copy. It rejects source, permission, or checkout changes after the build and before archive/manifest emission. Notarized candidates also require a clean committed checkout throughout.

The output includes a versioned `local-preview` ZIP, `SHA256SUMS`, `release-manifest.json`, and concrete `RELEASE_NOTES.md`. The archive is extracted and inspected again, including executable permissions and signatures. A local preview uses ad-hoc signing and is not notarized. No release is published by this command.

`INSOMAC_BUILD_DIR` selects a separate build directory. Historical QA and approved snapshot records under ignored `build/` are preserved.

## Developer ID and notarization

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

## Bounded resource profile

```sh
./scripts/measure-idle.sh 60 build/qa/profile-run
```

The tool launches only its owned app off, waits five seconds for startup loading, then samples for 60–120 seconds. `proc_pid_rusage(RUSAGE_INFO_V4)` reports RSS bytes, the kernel physical-footprint ledger, and cumulative user/system CPU nanoseconds. Average one-core CPU is derived from the counter delta and measured elapsed time. The 50 MiB RSS target remains an RSS target; physical footprint does not replace it.

Read-only `footprint` and `vmmap -summary` diagnostics are bounded and confined to the owned app. Permission failures are reported instead of elevated. The tool verifies no project keep-awake assertions, requests normal app termination, and reports cleanup. It captures no screen content. `INSOMAC_APP_PATH` selects an isolated app copy; `--compile-only` compiles the profiler without launching anything.
