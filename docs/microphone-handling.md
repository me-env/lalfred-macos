# Microphone handling during a dictation

How L'Alfred picks the microphone, keeps it working while the user speaks, and what it does when it
cannot. Built after comparing VoiceInk, FluidVoice, Hex, OpenSuperWhisper, Handy and Whispering.

## Policy

1. **The microphone is chosen once, at start**, by `MicrophoneSelector` (priority list, Bluetooth
   avoidance, lid state). A change of the macOS default input during a dictation is ignored: AirPods
   connecting mid-sentence no longer take over the mic or force them into call mode.
2. **Capture is rebuilt only on a real disruption** of the active microphone:
   - `deviceLost`: it disappeared from the device list or is no longer alive;
   - `formatChanged`: its sample rate or stream layout changed (Bluetooth profile switch);
   - `startTimedOut`: no callback arrived within 3 s of starting;
   - `stalled`: callbacks stopped for 2 s;
   - `silent`: a built-in mic delivered exact zeros for 3 s after having delivered sound.
3. **Events are debounced** (300 ms, restarted by each new event), since one Bluetooth connect fires
   several properties over 1–2 s, and our own capture start can fire them too.
4. **Recovery** (`CaptureRecoveryBudget`): a format change rebuilds on the same mic; a failure
   rebuilds once on the same mic, then excludes it; a lost mic is excluded right away. The next mic
   comes from `MicrophoneSelector` minus the excluded ones. At most 5 rebuilds per dictation.
5. **A rebuild is confirmed by its first callback**, not by `AudioDeviceStart` returning `noErr`:
   the watchdog reports `startTimedOut` otherwise, which feeds recovery again.
6. **When recovery gives up, the dictation ends cleanly**: the stream finishes normally, the audio
   recorded so far is transcribed and pasted, and the user is told the mic was lost.
7. **A recording of only exact zeros is not transcribed** (models hallucinate text from silence);
   the user is told the microphone sent no sound.

Other behaviours:
- The start sound plays once audio is flowing (first non-zero sample, or 1.2 s), for every device.
- The input mute of the chosen device is cleared before capturing.
- Fallbacks rank virtual devices (loopback, aggregate) last; one chosen as system default is kept.
- With the lid closed, the internal mic (built-in, data source `imic`) is skipped unless it is the
  only input; a mic on the headphone jack is still allowed.

## Components

```
dictate/Services/Audio/
  InputDevice.swift                 value: id, uid, name, transport, isInternalMic, isAlive (pure)
  MicrophonePreferences.swift       mode, priority list, avoidBluetoothMicrophone + store (pure + UserDefaults)
  MicrophoneSelector.swift          picks the mic from a device snapshot                  (pure)
  CaptureDisruption.swift           disruption kinds + detection from a snapshot          (pure)
  CaptureRecoveryBudget.swift       next mic to try after a disruption, or give up        (pure)
  CaptureWatchdog.swift             CaptureActivity -> disruption verdict                 (pure)
  RecordedAudio.swift               isDigitallySilent(Data)                               (pure)
  ClamshellState.swift              lid closed? (IOKit)
  AudioDevices.swift                + inputDevices(), clearInputMute(_:)                   (CoreAudio reads)
  AudioDeviceChangeObserver.swift   + device list, DeviceIsAlive; − default input         (CoreAudio listeners)
  InputDeviceListMonitor.swift      app-lifetime device-list notification for the settings UI
  DeviceCapture.swift               one IOProc, now tagged with a capture generation
  AudioCaptureSession.swift         + CaptureActivity (last callback, zero run), generation filter,
                                      finishKeepingAudio()
  AudioRecordingService.swift       start / stop / cancel, readiness, live signal, and the recovery
                                      loop: debounce, detection, rebuild, watchdog timer, give-up
dictate/Services/Settings/MicrophoneSection.swift   General tab section
```

Rules that keep this clean:
- Every decision is a pure function or value type over plain values (`InputDevice`,
  `CaptureActivity`, `TimeInterval`), so it is unit-tested without CoreAudio.
- CoreAudio is touched only by `AudioDevices`, `DeviceCapture`, `AudioDeviceChangeObserver`,
  `InputDeviceListMonitor`; IOKit only by `ClamshellState`.
- `AudioRecordingService` only orchestrates: it gathers a snapshot, asks the pure types, and acts.
- Main thread owns the orchestration state; the capture queue owns per-buffer state;
  `AudioCaptureSession`'s lock is the only bridge (stop state, recorded audio, activity).

### Generations

Each `DeviceCapture` gets a generation number. `AudioCaptureSession` only accepts buffers from the
current generation, and resets its activity when a new generation starts, so a late callback from a
stopped IOProc can neither add audio nor count as the new capture's first callback or first sound.

### Watchdog

A 0.5 s main-thread timer runs while recording. It reads the session's `CaptureActivity`
(capture start, first and last callback host times, start of the current run of exact zeros, whether
sound was seen) and asks `CaptureWatchdog.verdict`. A verdict goes straight to recovery (no debounce:
the thresholds already span seconds).

### Recovery flow

```
listener event ──► debounce 300 ms ──► CaptureDisruption.detect(active, snapshot, formatMatches)
watchdog verdict ───────────────────────────────┐            │ nil → nothing
                                                 ▼            ▼
                                   CaptureRecoveryBudget.nextMicrophone(...)
                                       │ mic                         │ nil
                                       ▼                             ▼
                          stop old capture, generation += 1   session.finishKeepingAudio()
                          clear mute, start DeviceCapture      onCaptureLost() → coordinator
                          readiness update (Bluetooth)         stops and processes what it has
```

### Interface changes

`AudioRecordingServicing` gains:
- `onInputLive: (() -> Void)?` — audio is flowing; the coordinator plays the start sound.
- `onCaptureLost: (() -> Void)?` — recovery gave up; the coordinator finishes the dictation.

`ProcessingFlowHandler.performProcessing` gains `captureWasLost: Bool` and checks
`RecordedAudio.isDigitallySilent` before awaiting the transcription.

## Callbacks and session state

v1.16.16 crashed on dictation start: the coordinator passed `sessionState` `inout` into the
listening flow, which called `startRecording()`, whose readiness callback read `sessionState`, and
Swift aborts on overlapping accesses. Two rules, the same ones FluidVoice, VoiceInk, Hex and Handy
follow:

1. The coordinator never mutates `sessionState` across a call into a service, `inout` included: it
   calls the service, then changes its state.
2. `AudioRecordingService` delivers every callback (`onInputReadinessChange`, `onInputLive`,
   `onCaptureLost`) on a later main-queue turn (`notify`), never from inside a call to it.

`DictationLifecycleTests` checks rule 1 with a fake service that breaks rule 2 on purpose (it calls
back synchronously from inside every call), over several dictations in a row, cancel and lost
capture. Each scenario runs in an exit test, so a violation fails that test instead of the run.

## How it is tested

- `ci/test.sh`: unit tests, run by CI on every push (`.github/workflows/test.yml`), required by the
  publish workflow, and run by `release.sh` before tagging.
- `ci/smoke-test.sh`: starts and cancels real dictations of a Debug build with the real microphone
  (CI runners have none). `release.sh` refuses to tag a commit without a passing run, unless
  `--skip-smoke`. Run it once per input device worth covering (built-in, Bluetooth, USB).

## Tests that must pass (`dictateTests`, Swift Testing)

`MicrophoneSelectorTests`
- system default mode returns the default input
- Bluetooth default + avoidance on + built-in mic available → built-in mic
- Bluetooth default + avoidance off → Bluetooth mic
- lid closed → internal mic skipped, jack mic allowed
- lid closed and internal mic is the only input → internal mic
- priority list → first connected entry, skipping missing ones
- priority list with none connected → falls back to the system default rules
- excluded uids are never returned
- default input missing → built-in mic, else first input; no input → nil
- fallback prefers a real mic over a loopback device; a loopback chosen as default is honored

`CaptureDisruptionTests`
- active mic present, alive, same format → nil (a default-input change is ignored)
- active mic missing from snapshot → deviceLost
- active mic not alive → deviceLost
- format mismatch → formatChanged

`CaptureRecoveryBudgetTests`
- formatChanged → same mic
- first stall → same mic; second stall on it → next mic
- deviceLost → next mic, never the lost one
- no other mic left → nil
- more than 5 rebuilds → nil

`CaptureWatchdogTests`
- no callback 3 s after start → startTimedOut; before 3 s → nil
- last callback 2 s ago → stalled
- built-in mic: zeros for 3 s after sound → silent; before sound or Bluetooth → nil

`RecordedAudioTests`
- empty and all-zero data are silent; one non-zero sample is not

`MicrophonePreferencesTests`
- Codable round trip; `remembering(_:)` appends new mics once and refreshes names;
  `moving` and `removing` reorder and drop entries

`ProcessingFlowSilenceTests`
- all-zero recording → "No sound from the microphone", nothing pasted
- capture lost + transcript → pasted, status says the mic was lost

## Manual checks (hardware)

1. Built-in mic, connect AirPods mid-dictation → recording continues on built-in mic, full text.
2. USB mic, unplug mid-dictation → continues on next mic, text from both parts.
3. AirPods first in the priority list, disconnect mid-dictation → continues on fallback.
4. Default input is AirPods, avoidance on → built-in mic used, music stays in high quality.
5. Lid closed with external display and AirPods / USB mic → internal mic never used.
6. Only mic unplugged mid-dictation → dictation ends, what was said is pasted, "mic lost" shown.
7. Logs: `log stream --predicate 'subsystem == "fr.lalfred.dictate" AND category == "Audio"'`
   show every disruption, decision and rebuild.
