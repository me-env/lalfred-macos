# Segmented transcription of long dictations

A long dictation is sent as several transcription requests, cut at pauses in the speech. Earlier
segments are transcribed while the user is still speaking, so when the dictation stops only the
last segment (at most about 20 s of audio) is still waiting for its text.

## Policy

1. **No cut before 20 s** of audio in the current segment. A dictation shorter than that is one
   request, exactly as before, and the voice-activity detector is never started.
2. **A cut only in a clear pause of 3 s**: the user stopping to think about what to say next, not
   the gap between two sentences. From 20 s on, the detector classifies 0.5 s windows of the audio
   (hop 0.25 s), and `PauseTracker` looks for a clear transition from speech to silence:
   - a window confidently holding speech (confidence ≥ 0.7);
   - then, starting at most 1 s after that window's end (the speech fading out), consecutive windows
     confidently without speech (confidence < 0.4) whose mean energy is at least 10 dB below that
     speech window's, spanning 3 s or more.

   A window in between, ambiguous by confidence or too loud for silence (speech the classifier
   missed), breaks the silence, and a silence can only start again within 1 s of confident speech.
   Silence that no confident speech came before, as in a segment the classifier finds unclear
   throughout, never cuts. When in doubt, no cut.
3. **The cut lands on the quietest 20 ms frame of the pause** (lowest energy), the furthest from
   any word. Measured once per cut, over about 150 frames.
4. **No pause, no cut.** A segment without a pause keeps growing until the next pause or the end of
   the dictation; there is no forced cut. A forced cut would split a word, which costs accuracy on
   both sides, while a long segment only costs the speed-up we had not had before.
5. **Each new segment starts the count again**: the next cut is at least 20 s after the previous one.
   A pause already under way when the 20 s mark passes doesn't count: the detector hasn't heard the
   speech before it.
6. **Texts are joined in segment order**, whatever order the requests finish in: each text is
   trimmed, empty ones are dropped, and they are joined with a space, except between two
   characters of scripts written without spaces (Chinese, Japanese, Thai). Snippets run on the
   joined text, as before.
7. **A segment continuing a sentence starts in lowercase.** The transcriber capitalized it only
   because it started a request. When the text so far doesn't end with sentence punctuation
   (`.` `?` `!` `…` and CJK `。` `？` `！`, possibly followed by a closing quote or bracket), the
   joined segment's first letter is lowercased, unless its first word keeps its capital anywhere in
   a sentence: an all-caps word or acronym ("OK", "API"), "I" and its contractions ("I'm"), a word of
   the user's dictionary terms, or a name the on-device `NLTagger` (`.nameType`, run on the segment
   alone) tags as a person, place or organization. The rules live in `SentenceContinuation`, shared
   with `PasteTextTransformer`, which lowercases a dictation continuing the sentence at the cursor.

## Detector: SoundAnalysis

Apple's built-in sound classifier (`SNClassifySoundRequest(classifierIdentifier: .version1)`) has a
`speech` label. It ships with macOS, so it adds no dependency, no download and no binary size, and
runs as a Core ML model that the system schedules on the Neural Engine, GPU or CPU.

Measured on an Apple Silicon Mac, `say`-generated speech with 0.4–1.5 s pauses, 0.5 s windows with
50 % overlap: speech windows score 0.6–0.99, silent ones 0.17–0.36, with or without added noise.
Cost: about 5.5 ms of CPU per second of audio analysed (0.5 % of one core), and about 30–70 ms to
create the request, once per segment. The detector only runs between the 20 s mark and the cut,
which now waits for a 3 s pause, so it may run until the end of a dictation without one. Judging
windows adds a mean energy per window (8,000 samples, twice per second of audio), negligible next to
the classifier.

Alternatives considered:
- Silero VAD in Core ML (FluidAudio): more accurate on noisy input and finer (32 ms frames), but adds
  a package that is mostly ASR and diarization, and downloads its model from Hugging Face at
  runtime. Worth it if the built-in classifier misses pauses in practice; the detector is behind a
  protocol, so it can be swapped in.
- WebRTC VAD: a C library to vendor, CPU only, and known to fire on noise.
- Energy and zero-crossing rate: free, but needs a noise-floor estimate and confuses breathing,
  typing or a fan with speech, or quiet speech with silence. Energy is still used, but only to check
  that windows the classifier called silent are much quieter than the speech before them, and to
  place the cut inside the pause.

## Components

```
dictate/Services/Transcription/Segmentation/
  VoiceActivityDetecting.swift            SpeechWindow + detector protocol                (pure)
  SoundAnalysisVoiceActivityDetector.swift  the protocol over SNAudioStreamAnalyzer
  PauseTracker.swift                      windows → clear 3 s pause after speech           (pure)
  PauseCutPoint.swift                     quietest frame of a pause, window energy         (pure)
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
holds the audio back while the detector looks at it, and releases it once it can no longer be part
of a pause: audio before the start of the latest classified window, and before the silence that may
still become a pause. During speech the hold-back is under a second; during a silence it grows to
the silence's length, at most about 3.5 s, until the silence is cut or broken. It only delays the
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

`AudioSegmenterTests`, `PauseTrackerTests`, `PauseCutPointTests`, `TranscriptJoinerTests`,
`SegmentedTranscriberTests` use a fake detector and fake provider:
- no cut before 20 s, and the detector isn't created for a short dictation;
- a cut only in a 3 s pause after confident speech, never during speech; 1–2 s pauses, ambiguous
  windows, silence without confident speech before it, and loud audio classified as silence don't
  cut; the cut lands inside the pause;
- the hold-back stays under a second during speech and covers a silence until it is classified;
- every byte goes to exactly one segment, whatever the chunk sizes;
- texts join in order even when the requests finish out of order;
- a segment continuing a sentence starts in lowercase, except acronyms, "I", names and dictionary
  terms; after sentence punctuation, and in scripts without case, nothing changes;
- a short dictation is one request;
- a recording error, a cancelled task and a failed segment end the dictation with an error.

`SoundAnalysisVoiceActivityDetectorTests` runs the real classifier on silence: windows are placed
at recording positions and score below the threshold.

Checked by hand, with the earlier 0.5 s rule, on 26 s of `say` speech whose only long pause (0.9 s)
starts around 21.2 s: one cut, at 21.51 s, inside the pause. The 3 s rule and its thresholds have not
been checked on real speech yet.

## Decisions

- Scribe's transcript edit is applied to each segment on its own; an instruction about the whole
  text (summarize, reorder) would behave differently. Kept that way: the user confirmed it, and that
  the extra requests don't matter.
