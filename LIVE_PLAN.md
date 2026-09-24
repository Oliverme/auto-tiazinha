# AutoTiazinha Live: implementation plan

This plan records the requirements agreed in the Live interview. It is an implementation brief for an AI coding agent, not a claim that the Live player already exists.

**Repository state checked 2026-09-24:** implementation steps 2–5 are now in the checkout: songs use a fixed two-measure count-in, the Native Editor stores a song's default root note, and Live edits named setlists with song occurrences, root overrides, transitions, one pad project, drag reordering, and confirmed removal. The builder's SWS action marker remains pending removal in step 10.

## Confirmed decisions

### Entry point, setlists, and editing

- `Live` becomes the main AutoTiazinha entry point. It provides the setlist creator and performance player.
- A setlist is named and saved separately from song `.RPP` projects. Its displayed name matches its filename. Different setlists may reference the same song project, and the same `.RPP` may appear more than once in one setlist.
- Setlists are user-chosen `.json` files. Song and pad paths are saved relative to the setlist when possible. New Setlist chooses a distinct file, with no Save As button in Live; the Live screen will offer relinking for missing projects. Each occurrence of a repeated song has its own Live root-note override.
- Live remembers the last successfully opened or saved setlist path on this computer and starts the New/Open file pickers there on later launches.
- The Live screen adds an existing `.RPP` to the list and then shows another empty slot for the next song. It supports New Song and Edit Song through the existing Native Editor. A newly created song is added to the current setlist.
- Setlist edits require an explicit **Save** action. The screen shows unsaved changes.
- Opening a setlist closes the REAPER project tabs already open, allowing REAPER to prompt for unsaved project changes, then opens the setlist's song projects as tabs. A single user-prepared pad `.RPP` is selected for the setlist and opened as a separate project tab.
- Song tempo, sections, click settings, and default root note belong to the song `.RPP`. Transition mode, eventual gap, pad project selection, and per-song root-note overrides belong to the setlist. A Live root-note override leaves the song's default unchanged.
- There is no requirement to preserve older pre-song settings or their interface. Prefer the clean fixed-count-in design.

### Song preparation

- Every song uses a fixed **two-measure count-in**. Remove the editor's variable pre-song measure and pre-song loop controls and their builder settings. The current two-measure pattern is a half-time `1, 2` measure followed by the first section cue and full count; the song begins at measure 3.
- Pad playback before count-in provides the waiting state that the old pre-song loop was intended to support.
- Song key means **root note only**, with no major/minor quality. Store a default root note in the song `.RPP`; Live can save a separate override for each occurrence in the setlist.
- New songs default to **C**. Use these twelve root-note spellings: `C`, `Db`, `D`, `Eb`, `E`, `F`, `Gb`, `G`, `Ab`, `A`, `Bb`, and `B`. A saved song with no root note requires an explicit choice before it can be built.

### Transport and transitions

- The Live screen has top-level Play/Pause, Full Stop, Next, and Previous controls.
- Full Stop stops every playing project tab, turns pads off, and resets the selected song to the start of its count-in.
- When Play resumes a paused song, it starts one full measure before the paused position and fades the song tracks in for band practice. The duration and exact gain method for this practice fade remain open.
- When nothing is playing, selecting a song or pressing Next/Previous activates its tab and waits for Play. After a natural Stop at End, Play replays the same song from its count-in.
- While a song is playing, the first Next or Previous press queues the target. A second press schedules the switch at the end of the current measure. Clicking a song in the list follows the same two-confirmation behavior. If the current song ends after only the first press, its configured end mode takes precedence.
- During Hold, one click on any song or one Next press schedules a switch at the end of the current hold measure; no second confirmation is required.
- The outgoing click stays at full level through its final measure. The next song's count-in begins at the transition boundary. Song backing tracks stop with the outgoing song; **only pads receive the transition fades**.
- The first Live version uses a **zero gap**: the next count-in begins at the outgoing song's end. A later gap control may use beats or seconds and accept negative, zero, or positive values. A negative gap starts the next count-in before the outgoing song ends.
- Greenfield song builds must not add the SWS `!` end-of-song action marker, and SWS is not required for Live. Live checks loaded songs for existing `!` markers and warns that they may conflict with Live transport. Live leaves SWS's global marker-action setting unchanged.

| End mode | Confirmed behavior |
| --- | --- |
| Stop at End | Default for a new transition. Stop the song at its end, fade its pad out, keep that song selected, and wait. Play replays it. |
| Start Next Automatically | Start the next song's count-in at the outgoing song's end. |
| Load Next and Wait | Activate the next song project when the outgoing song ends, fade the outgoing pad out, and wait for a user cue. |
| Hold | Loop only the outgoing song's click and pad at its tempo and root note indefinitely. Other song tracks do not loop. |

### Pads and gain

- The user prepares **one shared pad `.RPP` per setlist**. It contains one sustained-drone track per root note, named by key/root note. Per-song pad project or sound selection is deferred. The setlist selects the pad project.
- **Start Pads** is a control for a selected song only when no song is playing. It is unavailable during automatic playback and Hold. Pads started while stopped continue through that song's count-in and song; Full Stop turns them off.
- Pad fade-out is always **six seconds**, beginning at the outgoing song's end. Pad fade-in is always **three seconds**, beginning with the incoming song's count-in. These are fixed durations, not the earlier proposed per-transition three-second crossfade setting.
- Song tracks, including manually added backing tracks, are not faded at end-of-song or song-to-song transitions. The earlier bus/VCA proposal for transition fades is superseded. The separate practice-resume fade is still required.

### Outputs and performance display

- Output choices persist **per computer** across setlists. Click and spoken Cues always share a destination. Music can be assigned to one mono output or a stereo pair. With a 3.5 mm stereo jack, Click/Cues use the left channel and all other song audio is mixed to mono on the right. With a multi-output interface, the user chooses destinations.
- Live replaces each loaded song's saved hardware routing with the computer's output profile **temporarily**. It must not bake that computer's routing into a song `.RPP`, including when the Native Editor saves that song.
- The setlist shows each transition mode as a text menu on the separator between songs. The final song ends the setlist without a transition control. The lower part of Live shows a compact sequence of the previous section, current section, and next two sections of the active song, plus song time remaining and total song time. These times measure the musical song only; they exclude the two-measure count-in and six-second pad tail.

## Assumptions requiring review

These are planning aids, **not product decisions**:

- REAPER's persistent script state could hold the computer's output profile. The storage mechanism and migration policy have not been chosen.
- A queued song should be visibly highlighted so the two-press action is understandable. Its exact display and cancellation behavior have not been chosen.
- The pad project will need a repeatable convention for track names, item looping, and output routing. Only "one sustained-drone track per root note, named by key" is confirmed.

## Open questions to resolve before dependent steps

1. **Pad project contract:** Track names use the same natural/flat spellings as the editor and setlist: `C`, `Db`, `D`, `Eb`, `E`, `F`, `Gb`, `G`, `Ab`, `A`, `Bb`, and `B`; use flats rather than sharps. Still open: are there exactly twelve pitch classes? Does the prepared pad `.RPP` already loop its drones, or should Live configure looping? How should Live handle a missing root-note track?
2. **Pad transition inside one tab:** Must the outgoing and incoming drone tracks overlap for six seconds, with the incoming track reaching full level after three? What should happen when consecutive songs use the same root note/track? Should a pad start automatically for the next song in automatic transitions, given that the manual Start Pads control is unavailable then?
3. **Pad output:** Does the pad project's audio use the same mono/stereo music destination in the computer's output profile? Must Live temporarily override the pad project's saved hardware routing too?
4. **Pad selection:** Is a pad `.RPP` required before a setlist can play, or can a setlist run without pads? What should happen if its pad file is missing?
5. **Resolved — song root-note default:** New songs start at C; the editor and setlist use the twelve natural/flat spellings listed above. A saved song without a root note requires an explicit choice.
6. **Practice resume:** How long is the fade-in after resuming a paused song, which song tracks should it affect, and does the pad continue uninterrupted? What happens if a paused position is less than one full measure from the beginning?
7. **Queue details:** How is a queued target canceled or replaced? What do Next/Previous and list selection do while playback is paused? After one press followed by a natural ending, does the queued target remain selected or clear?
8. **Setlist edge cases:** The final song ends the setlist without an outgoing transition. What is the intended behavior if a song project appears twice and one occurrence is edited while both tabs are open? Resolved: duplicate occurrences can have different Live root-note overrides.
9. **Fade tail and pad control:** Is Start Pads available during the six-second outgoing pad fade, or only once all audio is silent? For Load Next and Wait, can Play start the new count-in during that tail?
10. **Resolved — setlist persistence:** Save named setlists as user-chosen `.json` files, use relative song and pad paths when possible, and create a distinct file through New Setlist. The Live screen will offer relinking for missing projects.
11. **Test delivery:** The current `.gitignore` excludes `/tests/`. Decide whether implementation tests should become tracked project files or remain local-only checks.
12. **Resolved — setlist list editing:** Drag a song row to reorder occurrences and use its separate Remove control to remove one occurrence immediately. Key overrides and outgoing transitions move with their song occurrence.

## Ordered implementation steps

Each step should be a reviewable change. A dependency on an open question means the agent must get that answer before implementing the affected behavior.

### 1. Verify REAPER control paths

- **Goal:** Establish a reliable design for concurrent song and pad tabs, measure-boundary scheduling, tab closure prompts, and temporary routing.
- **Dependencies:** None; investigate pad-transition and pad-output feasibility (open questions 2 and 3) and the existing SWS marker interaction.
- **Expected changes:** A short technical note and, if needed, a disposable REAPER prototype outside production song files. Record how the existing SWS marker and background project options interact with Live.
- **Acceptance criteria:** Demonstrate a song tab and shared pad tab playing together, stopping or switching a song at a measure boundary, and overlapping two pad drones in the shared tab without changing song track faders. Record any REAPER limitations that require a product decision.

### 2. Make the two-measure count-in fixed

- **Goal:** Give every song the same count-in and remove the old pre-song loop setup.
- **Dependencies:** None.
- **Expected changes:** Update `autoTiazinhaEditorModel.lua`, `autoTiazinhaNativeEditor.lua`, `autoTiazinhaBuilder.lua`, and song documentation. Remove the variable measure and loop controls/settings; place the song at measure 3; disable repeat and clear old loop points during a build.
- **Acceptance criteria:** A newly built song and a rebuilt song both have the two count measures and start at measure 3. The editor has no pre-song length or loop control. Builder output does not depend on old pre-song settings. Verify in REAPER as well as with local checks.

### 3. Store and edit a song's default root note

- **Goal:** Make the song `.RPP` the source of its default drone root note.
- **Dependencies:** Step 2; root-note policy confirmed above.
- **Expected changes:** Add a root-note field to the Native Editor model/UI and project settings; validate its value when building and loading a song.
- **Acceptance criteria:** Saving and reopening a song restores its root note. Changing it in the editor updates that song only. A saved song without a root note cannot build until one is selected. The value has no major/minor component.

### 4. Build the setlist model and manual persistence

- **Goal:** Represent multiple named setlists independently of song `.RPP` files.
- **Dependencies:** Answer open question 10; Step 3 for default versus override semantics.
- **Expected changes:** Add a Live setlist model and file reader/writer for ordered song occurrences, one pad project path, setlist key overrides, and transition modes. Add explicit Save and dirty-state tracking. Do not autosave edits.
- **Acceptance criteria:** A setlist round-trips through save and load without changing song files; duplicate paths remain separate occurrences; transition modes and root-note overrides remain attached according to the resolved duplicate-song policy; unsaved edits remain visible until saved or discarded.

### 5. Build the Live setlist editing screen

- **Goal:** Make Live the entry point for composing a show.
- **Dependencies:** Step 4; resolved question 12 for ordering and removal behavior.
- **Expected changes:** Add the Live ReaScript UI with named setlist creation/opening, add `.RPP`, an empty next-song slot, transition menus between songs, pad `.RPP` selection, root-note override controls, Save, and unsaved-changes display. Add ordering and removal controls after their behavior is resolved.
- **Reviewable slices:**
  1. **Done:** Add the Live window with one New / Open menu, Save, a read-only view of loaded entries, an unsaved-changes indicator, and a save/discard/cancel guard when leaving a dirty setlist. The chosen filename supplies the setlist name.
  2. **Done:** Add existing `.RPP` projects to ordered occurrences, including duplicate paths, with an empty next-song slot and per-occurrence missing-project relinking.
  3. **Done:** Add per-occurrence transition menus between songs, root-note overrides, and shared pad `.RPP` selection.
  4. **Done:** Drag song rows to reorder occurrences and use a separate Remove control without confirmation. Verified the insertion preview, drag outside the setlist, direct removal, save, and reopen in an isolated REAPER 7.80 instance.
- **Acceptance criteria:** A user can assemble and save a named setlist, reopen it with all entries and choices intact, and see the default Stop at End mode on a new transition. The screen supports the same song more than once, including reordering and removing individual occurrences.

### 6. Open and own the project tabs

- **Goal:** Match REAPER tabs to the setlist without losing unsaved song work.
- **Dependencies:** Steps 1, 4, and 5; answer open questions 4 and 8.
- **Expected changes:** Close existing project tabs through REAPER's normal save prompts; abort loading if the user cancels. Open each song occurrence as a tab and the selected pad `.RPP` as the one shared pad tab. Track the tab associated with every occurrence, including duplicates.
- **Acceptance criteria:** Loading a setlist produces the intended tabs in a predictable order. A canceled save prompt leaves the prior work available and does not start the new show. Duplicates remain separately selectable.

### 7. Integrate New Song and Edit Song

- **Goal:** Keep song creation inside the Live workflow.
- **Dependencies:** Steps 3, 5, and 6.
- **Expected changes:** Launch the existing Native Editor for a new or selected song, add a newly created `.RPP` to the current setlist, and refresh song metadata after an edit.
- **Acceptance criteria:** New Song creates a song through the editor and adds it once to the current setlist. Edit Song opens the intended occurrence's `.RPP`; changes to song settings are reflected in Live without changing setlist-specific root overrides.

### 8. Apply the computer's output profile temporarily

- **Goal:** Route Click/Cues and music for the attached audio device while preserving the saved song mix/routing.
- **Dependencies:** Steps 1 and 6; answer open question 3.
- **Expected changes:** Add a persistent per-computer output profile and controls for the 3.5 mm split and configurable multi-output assignments. Apply it at setlist load to song tabs, and to the pad tab if confirmed. Restore original project routing when leaving Live or before any editor save that would otherwise capture temporary routing.
- **Acceptance criteria:** The headphone profile sends Click/Cues left and mono music right; an interface profile supports a separate Click/Cues destination and mono or stereo music destination. Reopening the same song outside Live shows its original saved routing. No individual song track fader positions change.

### 9. Add transport and stopped-state navigation

- **Goal:** Give Live ownership of Play/Pause, Full Stop, tab selection, and practice resume.
- **Dependencies:** Steps 1, 2, 6, and 8; answer open question 6.
- **Expected changes:** Implement the top-level controls, playback state tracking, one-measure rewind and fade-in on pause resume, all-tab Full Stop, reset to count-in, and single-action selection while stopped.
- **Acceptance criteria:** Full Stop silences all tabs and pads and resets the selected song. While stopped, Next/Previous or a song click activates a tab without playing it. Resume starts one measure before the paused point and fades the specified tracks in without altering stored mix values.

### 10. Give Live sole ownership of song-end events

- **Goal:** Detect song ends and measure boundaries without a competing SWS tab advance.
- **Dependencies:** Steps 1, 2, 6, and 9.
- **Expected changes:** Remove the builder's SWS `!` marker generation and SWS requirement. Expose the end of each song and the next measure boundary to the Live transport controller. Warn when a loaded song contains an existing `!` action marker without changing SWS's global setting.
- **Acceptance criteria:** Live receives one end event for a newly built song and can schedule an action on the next measure boundary. With SWS marker actions enabled, new songs do not cause a second tab change or stop. Loading a song that already contains an action marker displays the warning.

### 11. Implement natural end modes

- **Goal:** Apply the configured mode when a song reaches its end.
- **Dependencies:** Steps 4, 6, 9, and 10; answer open question 8.
- **Expected changes:** Implement default Stop at End, automatic start with zero gap, Load Next and Wait, and a click-only Hold loop. Emit pad start/fade/hold requests for Step 14 without changing song backing-track faders.
- **Acceptance criteria:** Stop at End keeps the song selected and Play replays its count-in; automatic mode begins the next count-in at the outgoing end; Load Next and Wait activates the next tab without starting it; Hold loops the click while other song tracks stop. Each mode follows the resolved final-song behavior.

### 12. Implement manual song selection during playback

- **Goal:** Make Next, Previous, and song clicks follow the confirmed queue rules.
- **Dependencies:** Steps 5, 10, and 11; answer open question 7.
- **Expected changes:** First action queues a target, second confirmation schedules its transition at the end of the current measure, and one action schedules a transition from Hold. Preserve the configured natural end mode if the song ends after only one queue action.
- **Acceptance criteria:** A single press while playing does not switch songs. A second confirmation switches at a measure boundary. Previous behaves like Next; a song click can target any list entry. During Hold, one action switches at the current hold measure end.

### 13. Select and start drones in the shared pad project

- **Goal:** Play the selected song's sustained drone from the user-prepared pad tab.
- **Dependencies:** Steps 3, 4, 6, 8, and 9; answer open questions 1, 3, 4, and 9.
- **Expected changes:** Resolve the effective root note from the song default and setlist override; map it to the named pad-project track. Add Start Pads while stopped, retain that pad through count-in and song, and turn it off on Full Stop.
- **Acceptance criteria:** The chosen shared pad `.RPP` serves each song's root note. Start Pads works only in the permitted stopped states. Starting the song does not interrupt its pad, and Full Stop silences it. Missing pad files or tracks follow the resolved policy.

### 14. Add pad fades and Hold pad behavior

- **Goal:** Complete pad-only audio transitions in the shared project tab.
- **Dependencies:** Steps 10–13; answer open questions 2 and 9.
- **Expected changes:** Fade outgoing pads for six seconds from the song end and incoming pads for three seconds from the next count-in. Keep the current pad going during Hold and transition from it at the hold measure boundary. Handle consecutive songs with the same root note according to the resolved rule.
- **Acceptance criteria:** No song backing track or click is faded by a song transition. Pad fades use the fixed durations and work across Stop at End, Load Next and Wait, automatic start, manual navigation, and Hold. The repeated-root case and Start Pads availability follow the resolved decisions.

### 15. Add performance status and end-to-end checks

- **Goal:** Make the player readable during a show and verify the full flow.
- **Dependencies:** Steps 5–14; answer the UI-relevant parts of open questions 7 and 9.
- **Expected changes:** Add the bottom previous/current/next-two section strip and song remaining/total times excluding count-in and fade tail. Add queued-song status if that display is agreed. Update the README to make Live the main entry point and document setlist, pad project, output profile, and transitions. Add reviewable automated checks and a REAPER smoke-test checklist.
- **Acceptance criteria:** A complete show can be created, saved, reopened, played, paused, stopped, and navigated through all four end modes. Section and time displays match song regions and ignore count-in/tail. REAPER smoke tests cover headphone and multi-output profiles, unsaved tab prompts, duplicate song occurrences, manual measure-boundary transitions, pad fades, and recovery after a canceled load.

## Deferred work

### A. Configurable transition gap

- **Goal:** Let a setlist choose a gap in beats or seconds, including negative overlap, zero, and positive delay.
- **Dependencies:** Step 12 and a separate decision on gap ownership and limits.
- **Expected changes:** Extend setlist persistence, transition UI, and scheduler.
- **Acceptance criteria:** Count-in timing matches the configured signed gap across tempo and meter changes without moving the song's stored arrangement.

### B. Per-song pad sound or project choice

- **Goal:** Override the setlist's standard pad sound for selected song occurrences.
- **Dependencies:** Step 14 and a decision on whether overrides select tracks, presets, or separate projects.
- **Expected changes:** Extend setlist data and Live controls, then pad switching behavior.
- **Acceptance criteria:** A song occurrence can choose a different pad sound while others retain the setlist default; the choice survives Save and reopen and respects the same pad fades.
