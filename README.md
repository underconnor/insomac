# InsoMac

A small native macOS menu bar app for keeping a Mac awake. [Download InsoMac v0.1.0-preview.2](https://github.com/underconnor/insomac/releases/tag/v0.1.0-preview.2).

Extract the ZIP, move InsoMac.app to Applications, and open it. The universal app is Developer ID signed, notarized, and stapled.

| Mode | Current behavior |
| --- | --- |
| **Keep Screen On** | Prevents idle system and display sleep with the lid open. This is the default. |
| **Virtual Display (Experimental)** | Adds a temporary 1280 × 720 secondary display and prevents idle sleep. Uses private macOS interfaces. |

To start a virtual desktop, keep the lid open and right-click or Control-click the menu bar icon. Select **Virtual Display (Experimental)**. Left-click the icon to turn it on, or reopen the menu and choose **Turn On**. When the icon shows On, move a window onto the new display. Use **Turn Off** to remove it. Every launch starts Off, and changing modes stops any active session.

InsoMac runs without accounts, analytics, network calls, or a privileged helper.

On Apple Silicon macOS 27.2.1 with the lid open, build 2 showed four changing samples in a live ScreenCaptureKit stream and in window screenshots. The test window received targeted keys and accessibility button presses on all four samples. Window-targeted mouse clicks landed twice in two attempts. The earlier global-coordinate Core Graphics method missed both attempts in the same run. **Closed-lid operation, built-in-panel illumination with the lid closed, and actual Codex capture and input remain unverified.** [QA results](docs/QA.md)

Rendered illustration of the resting states and mode menu. Busy states are omitted; this is not a desktop screenshot:

![InsoMac rendered state and mode preview](docs/assets/insomac-states-light.png)

Build with Xcode 16 or later:

```sh
./scripts/build.sh
open build/InsoMac.app
./scripts/check.sh
```

Build 2 passed headless checks on all four Apple Silicon and Intel macOS 15/26 CI runners. The macOS 13.0 arm64 VM checks used the earlier build 1. The deployment target remains macOS 13, and access to the private display interfaces varies by runtime. [Build 2 CI](https://github.com/underconnor/insomac/actions/runs/45206379996)

See [release preparation](docs/RELEASE.md), [implementation notes](docs/IMPLEMENTATION.md), and the [MIT license](LICENSE).
