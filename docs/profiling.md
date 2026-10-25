# Memory and energy profiling

Notes from the October 2026 investigation into memory and energy use when the app runs for a long time. A stress harness and in-app resource monitoring were built for it, then dropped to save maintenance once the leaks were fixed. This page is what you need to rebuild them.

## Data from users' Macs

The app is distributed outside the App Store, so there are no Organizer metrics. The dropped monitoring sampled `proc_pid_rusage(RUSAGE_INFO_V4)` once a minute: `ri_phys_footprint`, `ri_billed_energy`, idle and interrupt wakeups, CPU time (in mach ticks; convert with `mach_timebase_info`), plus the thread count and the number of dictations so far. It wrote them as JSONL in Application Support, rotated at 5 MB, and users exported the file from Settings. The dictation count lets you tell growth per dictation from growth over time, and separate dictating from idle drain.

## Reproducing locally

- **Virtual mic.** Install BlackHole 2ch, `sox` and `switchaudio-osx` with brew. Make BlackHole the default input with `SwitchAudioSource -t input -s "BlackHole 2ch"`, then play a speech recording into it with `sox`. Restore the input afterwards. Without real speech, providers return empty transcripts and the test isn't realistic.
- **Driving dictations.** Add a Debug-only hook that calls the coordinator's shortcut-toggle path (`handleShortcutPress`), so each dictation runs the real record → transcribe → paste flow. Wait for the session to go idle before starting the next one.
- **Isolation.** The Debug build has the same bundle id as the installed app (`fr.lalfred.dictate`), so it shares its UserDefaults. Quit the installed app first, and give SwiftData a separate store so the test doesn't touch the user's history. Set `LLVM_PROFILE_FILE=/dev/null`, or a `default.profraw` file ends up in the repo.
- **Paste.** Paste only while a scratch TextEdit document is the frontmost app. A stray click once sent synthetic typing into the terminal.

## Measuring

- **Trend:** footprint, energy and wakeups sampled as above. Compute growth from the first dictation on, to leave out launch warm-up.
- **What grows:** take `heap -s <pid>` after about 5 dictations and again at the end, then diff the two by class.
- **Who holds it:** `leaks <pid>` lists leaked objects, and `leaks --traceTree=<address> <pid>` shows what retains one. `vmmap --summary <pid>` breaks memory down by region.

## Baseline (Mac mini, macOS 26.6.2, after the fixes)

| | |
|---|---|
| Footprint | ~25 MB, flat over 150 four-second dictations, 0 leaks |
| While dictating | ~5% CPU, ~99 interrupt wakeups/s (mostly the audio IOProc; the level meter is capped at 30 updates/s) |
| Idle | 0.04% CPU, < 0.1 mW, 0.2 wakeups/s |

A cancelled `Task.sleep` keeps about 450 B until its original deadline, which for `LastRecordingStore`'s expiry is 15 minutes. That shows up in heap diffs and is harmless.

## Findings

- **CoreAudio keeps removed listener blocks.** `AudioObjectRemovePropertyListenerBlock` returns success but never releases the block, or anything it captures. The app used to add and remove device listeners on every recording, so each one leaked a whole capture session and its audio: about 13 MB per 100 dictations. The fix registers listeners once per device, capturing only `[weak self]` (see `AudioRecordingService`).
- **`URLSessionWebSocketTask` is never freed** on macOS 26.6.2. Each one stays alive at about 70 KB, with its SecTrust and certificates. This reproduces in a standalone program, even with no I/O, an ephemeral session, `invalidateAndCancel` or an autorelease pool; plain data tasks are freed. The realtime models leaked about 7 MB per 100 dictations through this, and were later removed. If streaming transcription comes back, re-check this first. `NWConnection` with `NWProtocolWebSocket` is the alternative, but it hasn't been tested.
- **`xcodebuild test`** hung on the test Mac with "test runner hung before establishing connection", even on unmodified code. `build-for-testing` worked.
