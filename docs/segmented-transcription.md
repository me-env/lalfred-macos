# Segmented transcription of long dictations

A long dictation is sent as several transcription requests, cut at pauses in the speech. Earlier
segments are transcribed while the user is still speaking, so when the dictation stops only the
last segment is still waiting for its text, and none at all when the user stops after a pause:
the text is then already there.

## Policy

1. **The detector listens from the start** of the dictation: one detector per dictation, kept
   across cuts. It classifies 0.5 s windows of the audio (hop 0.25 s), and `PauseTracker` looks for
   a clear transition from speech to silence in the current segment:
   - a window confidently holding speech (confidence ≥ 0.7);
   - then, starting at most 1 s after that window's end (the speech fading out), consecutive windows
     confidently without speech (confidence < 0.4) whose mean energy is at least 10 dB below that
     speech window's.

   A window in between, ambiguous by confidence or too loud for silence (speech the classifier
   missed), breaks the silence, and a silence can only start again within 1 s of confident speech
   in the same segment. Silence that no confident speech of the segment came before, as at the very
   start of a dictation, right after a cut, or in a segment the classifier finds unclear throughout,
   never cuts. When in doubt, no cut.
2. **Two pauses cut**:
   - **a 5 s silence cuts at any segment length**: the user has clearly stopped, so even an 8 s
     segment is sent right away;
   - **a 3 s silence cuts once the segment is 20 s long**: the user stopping to think about what to
     say next, not the gap between two sentences. The cut lands in the part of the silence after the
     20 s mark, so a short pause that starts at 18.5 s still cuts, after 20 s. A dictation shorter
     than 20 s without a 5 s pause is one request, as before.
3. **The cut lands on the quietest 20 ms frame of the pause** (lowest energy), the furthest from
   any word. Measured once per cut, over about 150 frames.
4. **No pause, no cut.** A segment without a pause keeps growing until the next pause or the end of
   the dictation; there is no forced cut. A forced cut would split a word, which costs accuracy on
   both sides, while a long segment only costs the speed-up we had not had before.
5. **Each new segment starts the count again**: the next 3 s pause cuts at least 20 s after the
   previous cut, and any cut needs speech in the new segment first.
6. **A segment is requested once it holds sound.** After a cut, the new segment's audio is held,
   and its request isn't opened, until a window is classified as something other than clear silence
   (speech, ambiguous, or too loud next to the latest speech, measured on the part of the window
   after the cut). The held silence is then sent first, so nothing is lost. For a streaming provider
   (Scribe), the request opens at the first sound instead of at the cut.
7. **A silent last segment is never sent.** When the user stops and the audio after the last cut held
   nothing but clear silence, it is dropped and the text joined so far is the result: stopping after
   a pause is instant. It is dropped only when every window classified after the cut was clearly
   silent and the audio not classified yet is under 0.5 s (a window is classified every 0.25 s);
   otherwise it is sent. This only applies after a cut: a dictation without one, even silent throughout, is one
   request as before (an all-zero recording is still caught before transcription with the "No sound
   from the microphone" notice).
8. **Texts are joined in segment order**, whatever order the requests finish in: each text is
   trimmed, empty ones are dropped, and they are joined with a space, except between two
   characters of scripts written without spaces (Chinese, Japanese, Thai). Snippets run on the
   joined text, as before.
9. **A segment continuing a sentence starts in lowercase.** The transcriber capitalized it only
   because it started a request. When the text so far doesn't end with sentence punctuation
   (`.` `?` `!` `…` and CJK `。` `？` `！`, possibly followed by a closing quote or bracket), the
   joined segment's first letter is lowercased, unless its first word keeps its capital anywhere in
   a sentence: an acronym, i.e. a word whose second letter is a capital too ("OK", "USA", "API"),
   "I" alone or followed by an apostrophe ("I'm", "I’ll"), a word of the user's dictionary terms,
   or a name the on-device `NLTagger` (`.nameType`, run on the segment alone) tags as a person,
   place or organization. At the start of a sentence the text stays as transcribed. The rule lives in
   `SentenceContinuation` and `PasteTextTransformer` applies the same one to a dictation pasted
   after a sentence left unfinished at the cursor (where a `/` before the cursor also counts as a
   start, as in a path or a slash command).

## Detector: SoundAnalysis

Apple's built-in sound classifier (`SNClassifySoundRequest(classifierIdentifier: .version1)`) has a
`speech` label. It ships with macOS, so it adds no dependency, no download and no binary size, and
runs as a Core ML model that the system schedules on the Neural Engine, GPU or CPU.

Measured on an Apple Silicon Mac, `say`-generated speech with 0.4–1.5 s pauses, 0.5 s windows with
50 % overlap: speech windows score 0.6–0.99, silent ones 0.17–0.36, with or without added noise.
Cost: about 5.5 ms of CPU per second of audio analysed (0.5 % of one core); measured again in a
Debug test build, on 60 s of audio in 0.1 s chunks: 8 ms per second (0.8 %). Creating the request
takes about 50 ms, now once per dictation, on the transcription task while the user speaks. The
detector runs for the whole dictation, since a 5 s pause can cut at any length. Judging windows adds
a mean energy per window (8,000 samples, four windows per second of audio): about 3 ms per second in
that Debug build, much less optimized.

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
  PauseTracker.swift                      windows → clear 3 s or 5 s pause after speech    (pure)
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
                              │   ▲                    .cut: finish N
                              │   │windows             next .audio: open N+1, start request N+1
                              ▼   │
                      VoiceActivityDetecting
```

The segmenter holds the audio back while the detector looks at it, and releases it once it can no
longer be part of a pause: audio before the start of the latest classified window, and before the
silence that may still become a pause. During speech the hold-back is under a second; during a
silence after speech it grows to the silence's length, at most about 5.5 s (5 s plus a window),
until the silence is cut or broken. It only delays the upload, not the end of the dictation: the
stream's end flushes it at once. For a streaming provider, that is at most about 5.5 s of audio
(176 KB) left to upload at the stop, instead of a fraction of a second before. After a cut, a
silence is held until sound is heard (rule 6); that hold isn't bounded, but at the stop it is either
dropped or flushed at once.

Every byte goes to exactly one segment: a cut splits the held-back audio at a sample boundary. The
only audio never sent is a silent last segment (rule 7).

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
  way, and drops the same silent last segment, so the segments are transcribed in parallel.
- **Detector unavailable** (the request cannot be created): no cut, one request, as before.

The indicator and the processing states don't change: segmentation happens inside the transcription
task, which `ProcessingFlowHandler` still awaits as one value.

## Tests

`AudioSegmenterTests`, `PauseTrackerTests`, `PauseCutPointTests`, `TranscriptJoinerTests`,
`SegmentedTranscriberTests` use a fake detector and fake provider:
- a 3 s pause cuts only from 20 s on, in the part after the 20 s mark; a 5 s pause cuts at any
  length, but only after confident speech, not at the very start nor after unclear audio;
- never a cut during speech; 1–2 s pauses, ambiguous windows, silence without confident speech
  before it, and loud audio classified as silence don't cut; the cut lands inside the pause;
- one detector per dictation;
- the hold-back stays under a second during speech and covers a silence until it is classified:
  under 4 s for a possible short pause, under 5.75 s for a possible long one;
- after a cut, silence until the stop is never requested and the result is the earlier segments'
  joined text; an ambiguous window, speech, or more than 0.5 s left unclassified gets it sent; a
  silence followed by speech is sent with it, and its request opens only once sound is heard;
- every byte goes to exactly one segment, whatever the chunk sizes, but a silent last segment;
- texts join in order even when the requests finish out of order;
- a segment continuing a sentence starts in lowercase, except acronyms, "I", names and dictionary
  terms; after sentence punctuation, and in scripts without case, nothing changes;
- a short dictation is one request, and so is one silent throughout;
- a recording error, a cancelled task and a failed segment end the dictation with an error.

`SoundAnalysisVoiceActivityDetectorTests` runs the real classifier on silence: windows are placed
at recording positions and score below the threshold.

Checked by hand, with the earlier 0.5 s rule, on 26 s of `say` speech whose only long pause (0.9 s)
starts around 21.2 s: one cut, at 21.51 s, inside the pause. The 3 s and 5 s rules and their
thresholds have not been checked on real speech yet.

## Decisions

- Scribe's transcript edit is applied to each segment on its own; an instruction about the whole
  text (summarize, reorder) would behave differently. Kept that way: the user confirmed it, and that
  the extra requests don't matter.
