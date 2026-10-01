# Paste context fixtures

Real captures from the **Paste Context Inspector** (Settings → General → Experimental →
Inspect…). `PasteContextFixtureTests` routes each one through `CursorContextRules`, the
same way pasting does, and checks the result against `expectedResult`. So they test both
which method gets picked and what the transformer does with its reading. Snapshots
without an `expectedResult` are ignored.

Snapshots store each method's reading, so changing a reader's code (a strategy) doesn't
change what the fixtures replay: re-capture the affected fixtures to test it.

Files are named `<app>-<editor>-case<N>.json`. The case numbers come from the matrix below,
always pasting `Hello world`:

| # | Field content (⏎ = new line) | Cursor | Expected |
|---|---|---|---|
| 1 | (empty) | start | `Hello world` |
| 2 | `hey` | end | ` hello world` |
| 3 | `hey ` | end | `hello world` |
| 4 | `Done.` | end | ` Hello world` |
| 5 | `Done. ` | end | `Hello world` |
| 6 | `hey,` | end | ` hello world` |
| 7 | `hey⏎` | start of empty line 2 | `Hello world` |
| 8 | `hey⏎there` | after "there" | ` hello world` |
| 9 | `hey⏎there` | end of line 1 | ` hello world` |
| 10 | `hey⏎⏎there` | after "there" | ` hello world` |
| 11 | `hello there` | after "hello " | `hello world` |

Browser editors come from `tools/paste-context-testbed.html`.

## Coverage

What has been tested, which rule handles it, and what it should cover by extension. The
last column is an inference from the shared engine or editor, **not tested**.

| Kind of field | Tested in | Rule → method | Fixtures | Should also cover (untested) |
|---|---|---|---|---|
| Native Cocoa text view | TextEdit, Xcode | Default → AXValue | `textedit-*`, `xcode-*` | Most AppKit apps with standard text views (Notes, Messages input, native app forms) |
| Native document editor | Pages, Microsoft Word | Default → AXValue | `pages-*`, `word-*` | Keynote and Numbers text boxes; other Office for Mac apps |
| WebKit input / textarea | Safari testbed | Default → AXValue | `safari-input-*`, `safari-textarea-*` | Plain form fields on any site in Safari, apps embedding WKWebView |
| WebKit rich editors: contenteditable, Quill, Tiptap/ProseMirror, Lexical, CodeMirror | Safari testbed | Default → AXValue | `safari-*` | Rich editors on sites in Safari: Gmail, Notion, Linear, Substack, Facebook… WebKit counts paragraph breaks correctly, so no special rule |
| WebKit web area without a character cursor | Mail compose body | No character cursor → TextMarker paragraphs (the fixtures predate it and replay TextMarker selection) | `mail-*` | Other WebKit-based composers that only expose text markers |
| Chromium input / textarea | Dia testbed, Arc (by hand) | Default → AXValue | `dia-input-*`, `dia-textarea-*` | Plain fields in Chrome, Arc, Edge, Brave, and Electron apps |
| Chromium rich editors: contenteditable, Quill, Tiptap/ProseMirror, Lexical, CodeMirror | Dia testbed, Cursor AI chat | Chromium rich text editor → TextMarker paragraphs | `dia-*`, `cursor-chat-*` | Rich editors in Chromium browsers (Gmail, Outlook web, LinkedIn, Notion web, Slack web…) and Electron apps (Slack, Notion, Discord) |
| Empty Quill editor in Chromium | Dia testbed | Empty Quill editor → empty field | `dia-quill-case1` | Any site using Quill, in Chromium browsers |

Also checked by hand, without fixtures:

- **Outlook on the web (Dia)**, with long reply threads up to 1,100 elements and 300k
  characters: TextMarker paragraphs reads the context in ~0.2 ms; the tree walk it replaced
  took ~330 ms and misread tables and signatures.
- **LinkedIn messaging (Dia)**: the multi-paragraph case that showed Chromium's offset bug.
- **Arc textarea**: L'Alfred sees the focused field, routed to Default as expected.

## Adding one

1. In the inspector, click into the field, put the cursor where you'd paste, and type the
   **expected result**.
2. Save. Snapshots go to `~/Library/Application Support/fr.lalfred.dictate/PasteContextSnapshots/`
   (Save menu → Reveal snapshots folder).
3. Copy the JSON here. **Check it first**: it contains the text around your cursor and
   raw accessibility attributes, so strip anything private.

If it fails, add or adjust a rule in `CursorContextRules.ordered`. The snapshot has
every method's reading, the attributes and the children tree, so the pattern can usually
be worked out from the JSON alone, without the app at hand.

## Known gaps (no fixtures yet)

- **Monaco** (Cursor / VS Code code editor, DOM class `inputarea`): exposes only a fragment
  of the text, and no method reads it reliably.
- **Zed**: exposes no text to accessibility at all.
- **Arc**: no fixtures because the test harness couldn't drive it (asking Arc's app element
  for its focused element returns the window). L'Alfred's system-wide focus query does
  get the field, so smart paste itself works there.
