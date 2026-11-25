# Segmented transcription of long dictations

A long dictation is sent as several transcription requests, cut at pauses in the speech. Earlier
segments are transcribed while the user is still speaking, so when the dictation stops only the
last segment (at most about 20 s of audio) is still waiting for its text.

## Policy

1. **No cut before 20 s** of audio in the current segment. A dictation shorter than that is one
   request, exactly as before, and the voice-activity detector is never started.
2. **A cut only at a pause.** From 20 s on, the detector classifies 0.5 s windows of the audio
   (hop 0.25 s). The first window whose speech confidence is below 0.5 is a pause: at least half a
   second without speech.
3. **The cut lands on the quietest 20 ms frame of that window** (lowest energy), the furthest from
   any word.
4. **No pause, no cut.** A segment without a pause keeps growing until the next pause or the end of
   the dictation; there is no forced cut. A forced cut would split a word, which costs accuracy on
   both sides, while a long segment only costs the speed-up we had not had before. Continuous
   speech for a minute without half a second of silence is rare in dictation.
5. **Each new segment starts the count again**: the next cut is at least 20 s after the previous one.
6. **Texts are joined in segment order**, whatever order the requests finish in: each text is
   trimmed, empty ones are dropped, and they are joined with a space, except between two
   characters of scripts written without spaces (Chinese, Japanese, Thai). Snippets run on the
   joined text, as before.

## Detector: SoundAnalysis

Apple's built-in sound classifier (`SNClassifySoundRequest(classifierIdentifier: .version1)`) has a
`speech` label. It ships with macOS, so it adds no dependency, no download and no binary size, and
runs as a Core ML model that the system schedules on the Neural Engine, GPU or CPU.

Measured on an Apple Silicon Mac, `say`-generated speech with 0.4–1.5 s pauses, 0.5 s windows with
50 % overlap: speech windows score 0.6–0.99, silent ones 0.17–0.36, with or without added noise.
Cost: about 5.5 ms of CPU per second of audio analysed (0.5 % of one core), and about 30–70 ms to
create the request, once per segment. The detector only runs between the 20 s mark and the cut,
usually a few seconds per segment.

Alternatives considered:
- Silero VAD in Core ML (FluidAudio): more accurate on noisy input and finer (32 ms frames), but adds
  a package that is mostly ASR and diarization, and downloads its model from Hugging Face at
  runtime. Worth it if the built-in classifier misses pauses in practice; the detector is behind a
  protocol, so it can be swapped in.
- WebRTC VAD: a C library to vendor, CPU only, and known to fire on noise.
- Energy and zero-crossing rate: free, but needs a noise-floor estimate and confuses breathing,
  typing or a fan with speech, or quiet speech with silence. Energy is still used, but only to place
  the cut inside a window the classifier already called silent.

## Components

```
dictate/Services/Transcription/Segmentation/
  VoiceActivityDetecting.swift            SpeechWindow + detector protocol                (pure)
  SoundAnalysisVoiceActivityDetector.swift  the protocol over SNAudioStreamAnalyzer
  PauseCutPoint.swift                     first pause window → cut sample                 (pure)
  AudioSegmenter.swift                    chunks in → [.audio(Data), .cut] out             (pure but for the detector)
  SegmentedTranscriber.swift              one request per segment, texts joined in order
  TranscriptJoiner.swift                  joins segment texts                             (pure)
```

`runTransformationPipeline(audio:)` wraps the selected provider in a `SegmentedTranscriber`; the
providers themselves are unchanged and still receive one `AsyncThrowingStream<Data, Error>` per
request, with the same keyterms, language and transcript edit.

### Data flow

```
capture queue ──chunks──► AudioSegmenter ──.audio──► segment N stream ──► provider request N
                              │   ▲                    .cut: finish N, open N+1, start request N+1
                    after 20 s│   │windows
                              ▼   │
                      VoiceActivityDetecting
```

Before the 20 s mark, chunks pass straight through to the current segment. After it, the segmenter
holds the audio back while the detector looks at it, and releases it once a window covering it has
been classified as speech (audio before the start of the latest classified window can no longer be
in a pause the detector has yet to report). The hold-back is under a second, and only delays the
upload, not the end of the dictation: the stream's end flushes it.

Every byte goes to exactly one segment: a cut splits the held-back audio at a sample boundary.

## Threading

`SegmentedTranscriber.transcribe` is `@concurrent`: the segmenter and the detector run off the main
thread, in the transcription task. Provider requests are child tasks of a task group; they run as
they did before. SoundAnalysis delivers results synchronously from `analyze`, on the calling thread;
the detector collects them under a lock anyway, so a later delivery is picked up on the next call.

## Errors, cancellation, lost capture, retry

- **Recording error or cancellation** (the audio stream throws): the current segment's stream ends
  with the error, and the transcriber throws it; leaving the task group cancels requests in flight.
- **A segment's request fails**: the error comes out when the results are collected, which fails the
  dictation as a single request failure does today; the other requests are cancelled. The existing
  transient-error retry then transcribes the whole recording again, through the same segmenting
  pipeline.
- **Cancelling the transcription task** cancels every segment request (structured concurrency).
- **Capture lost**: the stream finishes normally, so the segments recorded so far are transcribed and
  joined, as before.
- **Retry Last Recording** sends the whole recording as one chunk; the segmenter cuts it the same
  way, so the segments are transcribed in parallel.
- **Detector unavailable** (the request cannot be created): no cut, one request, as before.

The indicator and the processing states don't change: segmentation happens inside the transcription
task, which `ProcessingFlowHandler` still awaits as one value.

## Tests

`AudioSegmenterTests`, `PauseCutPointTests`, `TranscriptJoinerTests`, `SegmentedTranscriberTests`
use a fake detector and fake provider:
- no cut before 20 s, and the detector isn't created for a short dictation;
- a cut only at a pause, never during speech; the cut lands inside the silence;
- every byte goes to exactly one segment, whatever the chunk sizes;
- texts join in order even when the requests finish out of order;
- a short dictation is one request;
- a recording error, a cancelled task and a failed segment end the dictation with an error.

`SoundAnalysisVoiceActivityDetectorTests` runs the real classifier on silence: windows are placed
at recording positions and score below the threshold.

Checked by hand with the real detector on 26 s of `say` speech whose only long pause (0.9 s) starts
around 21.2 s, with shorter comma pauses before: one cut, at 21.51 s, inside the pause.

## Open questions

- Scribe's transcript edit is applied to each segment on its own; an instruction about the whole
  text (summarize, reorder) would behave differently. It could be sent with the last segment only,
  or segmentation disabled while a transcript edit is set.
- A cut at a mid-sentence pause may make the next segment start with a capital letter.
