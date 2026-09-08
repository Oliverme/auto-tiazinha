# AutoTiazinha Native editor

Load **autoTiazinhaNativeEditor.lua** through the REAPER Actions list's
ReaScript Load action. The horizontal editor uses REAPER's built-in `gfx` API
and requires no additional GUI extension.

Keep these files together with `media/`:

- `autoTiazinhaNativeEditor.lua` — the graphical action.
- `autoTiazinhaEditorModel.lua` — draft data, ordering, and validation.
- `autoTiazinhaBuilder.lua` — the shared song generator.

The original `autoTiazinha.lua` and dialog entry `autoTiazinhaCaller.lua`
remain available.

## Editing

The editor opens the active project's stored settings, or the original default
arrangement.

- The palette contains available unnumbered section cues; count recordings and
  names such as `Chorus 1` and `Verse 2` are excluded. Previously saved numbered
  sections are retained when loading an existing song.
- **Common sections** follow this order: Intro, Verse, Pre Chorus, Chorus,
  Bridge, Ending. **Other sections**
  are sorted alphabetically. Both groups use the selected language's available cues.
- Click a palette section to append it, or drag it into the horizontal song
  strip. New sections start at four bars with the count selected for editing.
- Click a card title with a drawn chevron to select an available numbered cue
  (for example Chorus 2). The menu lists the unnumbered cue first, then variants
  numerically, and marks the current choice. Canceling leaves it unchanged.
  Length and position are preserved. Choices follow the selected cue language;
  unavailable choices after a language change are highlighted and block building
  until replaced. The palette still shows only the unnumbered base sections.
- Drag a card's title to reorder it, or use the small `x` to remove it.
- Click a bar count and type a positive whole number (including odd counts).
  Enter commits; Escape cancels without closing the editor. Clicking elsewhere
  also commits valid input; invalid input keeps focus until corrected or canceled.
  Ctrl+A selects the value; Backspace removes digits. The `-` and `+` buttons
  adjust the count by one, with a minimum of one bar except for the final
  section, which may be zero.
- **Custom** opens the native input dialog for half-bar sequences such as `4.2`.
  Plus/minus are inactive for custom sequences, preserving their internal order.
  To replace one with whole bars, click the value and type a whole number.
- Use the wheel over the strip, the arrows, or the scrollbar to navigate long
  arrangements. While dragging, hold near either strip edge to scroll.
- **Song settings** is an embedded panel. Click the song name or tempo to
  type a replacement; Enter applies, Escape cancels, and clicking elsewhere
  commits valid input. Tempo accepts positive decimal values and has minus/plus
  buttons for one-BPM adjustments.
- Tempo, time signature, the Double click checkbox, and both click sounds are
  grouped in **Rhythm & Click**. They occupy one row in wide windows; the sound
  selectors move to a second row in narrower windows. Song name and cue
  language remain above the group. Click either the checkbox square or its
  label to toggle Double click.
- Select the time-signature numerator (2, 3, 4, 6) and denominator (2, 4, 8, 16)
  from menus. Existing saved meter values remain displayed until changed.
  **Double click** toggles on/off when the numerator is 4; selecting another
  numerator clears and disables it, matching the shared builder's behavior.
- Select **EN** or **PT** for cue language. The section palette and numbered
  cue choices refresh immediately.
- **Click accent** and **Click secondary** list WAV samples found in
  `media/click/`. Select **Built-in** to use the default sound.
- Smaller windows replace the palette with **Common sections +** and **Other sections +** menus.
  The horizontal order stays visible. Enlarge windows below 620 × 760 to edit.
- **Build / Update song** applies and saves through the shared builder.
  Project-tab and playback guards, draft-discard confirmation, and in-memory
  draft limitations are described below.

Length notation matches the builder: `8` means eight bars; `4.` means four
bars followed by a half bar; `4.2` means four bars, a half bar, then two bars.
A half bar still occupies a numbered bar in the generated project. Half bars
in odd-numerator meters are rejected.

## Building and drafts

**Build / Update song** calls the shared builder and saves the result. It
retains the builder's project creation, marker replacement, loop and cursor
behavior. Editing cards alone does not modify the project. Stop playback before
building. If you switch project tabs, switch back or use **Load project**,
which asks before discarding unapplied edits.

Drafts are held in memory until built. Closing with unapplied changes asks
whether to discard them. Forced script termination or quitting REAPER can still
lose drafts. Automatic updates, draft persistence, and editor undo are not
implemented.

## Zero-bar final section

Set the last section (for example Ending) to `0` to cue the end without adding
another bar. Its spoken section cue and count-in are placed in the preceding
bar. The end action marker is placed exactly at that final section's start;
no empty region is created. This retains the existing SWS marker-action behavior
(stop, return to the beginning, select the next project tab); marker actions
must be enabled for that sequence to execute during playback.

Only the last section may have zero bars. Moving it earlier or adding another
section afterward requires fixing the length or moving it back to the end.
This is supported by the Native editor and the shared builder; the original
`autoTiazinha.lua` remains unchanged.

## Verification

From the project directory, with Lua 5.4:

```sh
lua5.4 tests/editor_model_test.lua .
lua5.4 tests/native_editor_test.lua .
lua5.4 tests/builder_ending_test.lua .
```

The interaction and builder tests mock REAPER/gfx; they do not verify native
rendering or actual playback. For manual testing in a disposable REAPER project:

1. Add and reorder sections, including first-to-last and last-to-first.
2. Edit lengths by typing and using plus/minus; check Enter and Escape.
3. Select numbered cues, change language, remove sections, and try invalid lengths.
4. Build, inspect regions and cues, edit a length, then rebuild.
5. Set the final section to zero and verify the end cue and tab switch with SWS marker actions enabled.
6. Switch tabs or start playback and verify Build is disabled.
7. Close with unapplied changes and test both keeping and discarding the draft.
