# AutoTiazinha

AutoTiazinha is a set of Lua ReaScripts for preparing songs in REAPER. It builds
a click track, spoken section cues, count cues, regions, tempo information, and
an optional end-of-song action that advances to the next project tab.

The Native Editor is the recommended way to use the scripts. It provides a
graphical song-arrangement editor using REAPER's built-in `gfx` interface and
rebuilds the project automatically as settings are changed.

## Requirements

- [REAPER 7.72](https://www.reaper.fm/download.php) or newer is required.
  The scripts use `reaper.AddRegionOrMarker()`, which was introduced in REAPER
  7.72.
- [SWS/S&M Extension 2.14.0 #7](https://www.sws-extension.org/) or newer is
  required only for the end-of-song marker automation that stops playback,
  returns to the beginning, and selects the next project tab. Song generation
  itself works without SWS.
- No separate Lua installation is needed for normal use because REAPER runs the
  scripts. Lua 5.4 is needed only to run the command-line test suite.

The Native Editor uses REAPER's built-in `gfx` API. ReaImGui, JS_ReaScriptAPI,
and ReaPack are not required.

The project includes English and Portuguese cue recordings and works on the
Windows, macOS, and Linux versions of REAPER.

## Installation

1. Download or clone this repository, keeping the Lua files and `media/`
   directory together. Do not move individual scripts away from the media
   folder.
2. Open REAPER and choose **Actions > Show action list**.
3. Select **New action > Load ReaScript**.
4. Load `autoTiazinhaNativeEditor.lua`.
5. Assign it a keyboard shortcut or toolbar button if desired.

The Native Editor also loads these files from the same directory:

- `autoTiazinhaBuilder.lua` — generates and saves the REAPER project.
- `autoTiazinhaEditorModel.lua` — stores and validates editor state.
- `media/EN/` and `media/PT/` — section and count cue recordings.
- `media/click/` — optional click sounds.

Do not load the builder or editor model directly into the Action List.

## Quick start

1. Open or create a REAPER project and save it in the directory where the song
   projects should live.
2. Run **autoTiazinhaNativeEditor.lua** from the Action List.
3. Enter the song name, tempo, time signature, cue language, and click options.
4. Add sections from the palette. After adding a section, type its length and
   press Enter. The new section is not built until its length is provided.
5. Drag section titles to reorder them. Use `-`, `+`, or the length field to
   change their sizes. Use **Custom** for half-bar sequences.
6. Inspect the generated Click and Cues tracks and the named regions in REAPER.

All committed UI changes rebuild and save the song automatically. Playback is
allowed to continue during a rebuild. Changes made while recording remain
pending and are built when recording stops. If a build fails, correct the
reported problem and use **Retry automatic build**.

Changing the song name can create a new project tab and save a new `.RPP` file
in the current project directory. The editor follows that new project after the
build.

## What a build changes

The builder:

- stores the song settings inside the REAPER project;
- sets the project tempo and time signature;
- creates or regenerates the AutoTiazinha-owned `Click` and `Cues` tracks;
- inserts spoken section cues and beat-count cues;
- creates one named region for each positive-length section;
- recreates the project's markers and tempo/time-signature markers;
- configures the loop range and repeat state;
- adds the end-of-song action marker; and
- saves the project.

Because markers and tempo markers are rebuilt, first use AutoTiazinha on a copy
or disposable project if the project already contains manually created markers
or a custom tempo map.

## Song sections and lengths

The editor discovers available section names from the selected language's media
folder. Common choices include Intro, Verse, Pre Chorus, Chorus, Bridge, and
Ending. Numbered recordings such as `Chorus 1` and `Chorus 2` appear as variants
of their base section.

Normal lengths are whole bars, such as `4`, `8`, or `17`. Custom notation uses
a dot for each half-length bar:

- `8` means eight full bars.
- `4.` means four full bars followed by one half bar.
- `4.2` means four full bars, one half bar, then two full bars.

Half bars require an even time-signature numerator. A final section may have a
length of `0`; this creates its spoken cue and end action without creating an
empty region. Only the last section can have zero bars.

To add custom section cues, place matching `.wav` files in both language folders
as needed. The file name, without `.wav`, becomes the section name. Avoid `|`,
`:`, commas, slashes, and backslashes in section names.

## Advancing to the next song with SWS

AutoTiazinha places an action marker at the end of the song. When SWS marker
actions are enabled and playback crosses that marker, REAPER stops, returns to
the beginning, and selects the next project tab. This lets multiple open project
tabs act as an ordered set list.

To enable it:

1. Install SWS/S&M 2.14.0 #7 or newer for the same architecture as REAPER.
2. Restart REAPER after installing the extension.
3. Open the Action List and run **SWS: Enable marker actions**, or enable
   **Options > Enable SWS marker actions**.
4. Open the song projects in project tabs in performance order.
5. Build each song with AutoTiazinha and confirm that its final `!` action marker
   is present.

Without SWS, or with marker actions disabled, the Click/Cues tracks and song
regions still work, but crossing the final marker will not advance to the next
song. See the official [SWS marker-actions documentation](https://www.sws-extension.org/markeractions.php)
for more information.

Test this automation with disposable projects before using it live. Marker
actions execute REAPER commands during playback, and the next-tab behavior
depends on the order of the currently open project tabs.

## Troubleshooting

- **No sections appear:** confirm that `media/EN/` and `media/PT/` are beside
  the scripts and contain `.wav` files.
- **A cue is marked unavailable:** select a variant available in the current cue
  language or add the matching recording.
- **A change says it is waiting to build:** finish the active length/value edit,
  return to the project tab where the editor was opened, or stop recording.
- **The next song is not selected:** install SWS and enable SWS marker actions,
  then confirm another project tab exists after the current song.
- **A build error occurred:** playback may continue, but the project may be
  partially updated. Fix the reported input or missing media and choose
  **Retry automatic build**.
