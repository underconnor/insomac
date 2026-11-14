# InsoMac product brief

14 November 2026 · Research prototype

## Purpose

A small Mac menu bar switch for keeping long tasks running. Click once to turn it on; click again to release its sleep assertions. The icon must make the current state obvious. Other apps and system settings may still prevent sleep after InsoMac turns off.

The intended use includes Codex computer use, not just terminal jobs. The finished product is intended to work with the MacBook open or closed, on battery as well as power. Keeping the physical built-in screen lit with the lid closed remains a requested capability because losing the desktop may interrupt computer use. This requirement is **unresolved**.

Provide **both physical-screen and virtual-display modes**, selectable in the app. Virtual-display support is an additional capability and does not satisfy the physical-screen requirement by substitution. InsoMac is the approved public name.

## What we can build now

The local prototype uses Swift, AppKit, and IOKit. Its physical-screen path prevents idle system and display sleep while the lid is open. Its experimental virtual-display path creates a temporary secondary display without changing global sleep settings. Both modes remain subject to the closed-lid and computer-use acceptance tests below; neither should be presented as the finished product yet.

| Interaction | Behavior |
| --- | --- |
| Launch | Start off; show only a menu bar item |
| Left click | Toggle an indefinite session |
| On | Filled cup icon and an accessible state label |
| Off | Sleeping-moon icon; no InsoMac sleep assertions |
| Right click | State, toggle, mode selection, current limitation, and Quit |
| Change mode while on | Stop the session, clean up owned resources, then select the new mode; remain off |
| Failure | Distinct error state; never show a successful session before assertions succeed |
| Quit or process exit | Release process-owned assertions |

No accounts, telemetry, network service, third-party dependencies, or animation loop. Keep native dark-mode and accessibility behavior. Preserve the user's screen-lock policy. The utility itself must not capture screens or control other apps.

## Selectable modes

| Mode | Intended behavior | Current evidence boundary |
| --- | --- | --- |
| Keep Screen On | Keep the physical display and Mac awake | Existing implementation covers idle sleep with the lid open; a lit closed built-in panel remains unverified |
| Virtual Display (Experimental) | Maintain a separate desktop display for computer use | Temporary display creation and cleanup tested locally; continued rendering, lid behavior, and actual Codex input/capture remain unverified |

Keep Screen On is the default. Start every launch off. Virtual Display must be explicitly selected, created only for an active session, and removed on stop or process exit. It must not replace or reconfigure the user's main display. Selecting a new mode during a session turns that session off. On a creation or configuration failure, roll back and show an error instead of silently starting the other mode. If the private API is unavailable, disable that mode with a concise explanation. A successful private API call alone is not proof of an active, usable desktop.

Target macOS 13 and later, with arm64 and x86_64 builds. No helper is included. This is a build target, not a claim that every version and Mac has been tested. The current runtime test environment is an Apple M5 Pro running macOS 27.2.1.

## The unresolved requirement

Three conditions need separate evidence: the computer is awake, an interactive desktop is available, and the physical panel is lit. An IOKit assertion or a successful shell heartbeat proves neither of the latter two.

No supported portable API for keeping the built-in panel lit with the lid shut was established by this research. A virtual display may address desktop availability, but does not satisfy the literal physical-panel requirement. Maintain separate capability claims and tests for each mode.

The next experiment must check actual Codex computer use across a lid close/open cycle. Use a harmless local test window with a changing counter and editable field. Record whether screenshots are fresh, clicks hit the correct target, typed text is visible, and the task continues without manual recovery. Record display configuration, global power settings, and other apps' sleep assertions alongside a process heartbeat. Existing sleep overrides invalidate attribution to InsoMac. Repeat with and without an external display, then with any explicitly selected virtual-display experiment. Test lock and display sleep separately from lid closure.

## Completion criteria

1. Provide both selectable modes and establish which configurations satisfy physical-panel continuity and actual computer-use continuity. Keep any unsupported physical closed-lid case explicit; the virtual mode does not fulfill that requirement by substitution.
2. Implement the approved closed-lid approach and prove recovery after off, quit, crash, helper failure, power changes, and reboot.
3. Verify on a physical Intel Mac and an Apple silicon Mac, including the oldest supported macOS. Record failures rather than generalizing from one machine.
4. Measure idle CPU, memory, launch time, and archive size. Initial engineering targets: under 0.5% sustained idle CPU, under 50 MiB resident memory, and under 10 MiB for the app. Report measured values and method; these are not marketing claims.
5. Review repository contents and license before repository creation. The public name InsoMac is approved; repository creation and publication still require review. Prepare a Developer ID signed and notarized download before a general public launch.

Sessions have no arbitrary time limit. Do not advertise guaranteed operation until exactly 0% battery or override thermal and battery protection. Any proposed earlier cutoff is a product decision that must be presented explicitly.

## Scope discipline

Timers, schedules, agent integrations, themes, automatic updates, and login launch can wait. First prove the one-click interaction and the desktop continuity that motivated the app. Public copy should be short, specific, and supported by test results.
