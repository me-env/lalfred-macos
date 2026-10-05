# axlab

Drives real apps to test smart paste: opens each app in `targets.json`, finds the field,
types the paste-context matrix cases (see
`dictateTests/PasteContextFixtures/README.md`), and reads the field with L'Alfred's own
code, compiled from `dictate/`, so it can't drift from the app.

```bash
tools/axlab/axlab list                 # targets and their status
tools/axlab/axlab run                  # everything that isn't skipped
tools/axlab/axlab run testbed xcode    # some groups / targets
tools/axlab/axlab run --update-fixtures testbed
```

It sends real keystrokes and clicks: **don't touch the keyboard or mouse during a run.**
Before each key it checks that the target app is in front with focus on its field, and
stops otherwise, so clicking anywhere is also how you stop it.

## First time

The wrapper builds the tool when a source changed and signs it with the Developer ID
matching the project's team (override with `AXLAB_SIGN_IDENTITY`), so macOS keeps one
Accessibility permission across rebuilds. Grant it once:

1. Run `tools/axlab/axlab list` to build it.
2. System Settings → Privacy & Security → Accessibility → **+**, press ⌘⇧G and paste the
   path to `tools/axlab/.build/axlab`. Turn it on.

## Output

Each run writes its captures and a `summary.md` to `results/<date>/`. The terminal shows
one line per target, then details for cases that fail, never showed the typed text, or
read differently from the committed fixture.

`--update-fixtures` copies the captures into `dictateTests/PasteContextFixtures/`.
Targets marked `private` (real accounts) are left out unless `--include-private` is
given: their snapshots can hold text from around the field (page titles, other messages).
Check `git diff` either way.

## Targets

One entry per field in `targets.json`:

| Key | |
|---|---|
| `id` | Also the fixture prefix: `<id>-case<N>.json` |
| `group` | For running several at once: `native`, `documents`, `code`, `testbed`, `chat`, `web` |
| `app` | Bundle identifier |
| `open` | `file` (created empty in `scratch/`), `url`, or `testbed: true`; `shortcut` pressed when the field isn't there (e.g. `cmd+l`), every time with `shortcutFirst` |
| `field` | What the field is, all given criteria must match: `role`, `domId`, `domClass`, `description` (aria-label), `identifier` (AXIdentifier), `roleDescription`, `windowTitle` (contains), `windowHas` (an element of the window with this `role` / `identifier` / `text`, e.g. a chat header), `within` (the closest ancestor with this `domClass` contains `text`, e.g. a page title) |
| `multiline` | `false` for single-line fields: runs only the cases without new lines |
| `newline` | Key for a new line, e.g. `shift+return` |
| `sends` | ↩ sends a message: plain ↩ is refused |
| `private` | Runs on a real account |
| `pasteText` | Put the cases' text in with ⌘V instead of typing it, when typing triggers autocomplete or Vim commands. The clipboard is restored after the target |
| `escapePopups` | When focus moves to a popup of the same app (autocomplete), press Escape once instead of stopping |
| `settleMs` | How long the field must stay unchanged before it's read (default 80) |
| `setup` | Manual steps, shown when the field can't be reached |
| `skip` | Listed but not run, with the reason |

`axlab editables <bundleId>` lists an app's text fields with their role, DOM id, classes,
description and window, which is what `field` matches on. `axlab focused` shows the field
that has focus.

Vim modes (Xcode, kindaVim…) are handled: after focusing a field the harness types `i`.
If it shows up, it's deleted again; if not, the field was in normal mode and is now in
insert mode. This needs a field that exposes its text.

The harness never clears a field holding anything but the matrix's own words (hey, there,
done, hello, world), so a wrong match on a real note or draft is never wiped. A field that
hides its text (Mail's compose body) must be pinned with `windowTitle` or `windowHas` instead.
