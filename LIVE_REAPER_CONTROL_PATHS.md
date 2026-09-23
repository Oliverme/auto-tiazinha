# Live: REAPER control-path verification

Checked on 2026-09-23 with REAPER 7.80/linux-x86_64 and SWS/S&M 2.14.0 Build 7. The disposable prototype used synthetic audio and projects under `/tmp`; it did not open or change production song projects. Its run log is `/tmp/auto-tiazinha-live-prototype.KndE9d/results.txt`.

## Findings

| Area | Finding |
| --- | --- |
| Concurrent tabs | REAPER can keep a song tab and the shared pad tab playing together. Enable **Run background projects**. Leave **Play stopped background projects with active project** off, then explicitly start the selected song and pad with `OnPlayButtonEx(project)`. This avoids starting every stopped song tab when Play is pressed. |
| Measure scheduling | A ReaScript can read a tab's play position and tempo map, then stop or switch that project with project-scoped transport calls. The prototype requested a switch at the 2.000-second bar line and issued it when the outgoing project's reported position reached 2.020 seconds. A `defer`-driven controller therefore has a small polling delay; the observed delay was 20 ms. |
| Pad overlap | Two drone tracks in the same pad project played at once while both song tabs' track volumes stayed at 0.650 and both pad track volumes stayed at 0.350. The two synthetic pad items overlapped from 0 to 36 seconds. This checks overlap and transport ownership; it does not verify the final pad fade curves. |
| Existing SWS marker | With marker actions enabled, the builder's `! 40044 40042 40861` marker stopped Song A, returned it to the start, and selected Song B at the marker. The pad tab kept playing. If Live also handles the song end, the marker may make a second transport/tab change. |
| Project loading prompts | REAPER's ordinary project-open path prompts to save unless the path is prefixed with `noprompt:`. A scripted tab loader can use the normal close action, wait for the prompt, and compare the enumerated project tabs before continuing; a tab left open means the user canceled and Live must abort. This path is supported by the API, but the prototype did not open a save dialog. |
| Temporary output routing | ReaScript can inspect, add, edit, and remove project hardware-output sends, separately from track volume. A Live controller can snapshot the saved routing, apply the computer's output map in memory, and restore it before any editor save and when leaving Live. The prototype did not exercise physical output channels. |

## Recommended control path

1. Do not change SWS's global marker-action setting. Greenfield song builds must stop writing the `!` end-of-song action marker, and SWS must no longer be a requirement. When loading a setlist, scan each song for markers whose names begin with `!`; warn that an existing action marker may conflict with Live if SWS marker actions are enabled. Leave the marker and SWS setting unchanged.
2. Require **Run background projects**. Keep **Play stopped background projects with active project** off; Live starts only the selected song and the shared pad project with project-scoped play calls. Use `GetPlayStateEx` and `GetPlayPositionEx` to track each tab independently.
3. Find the next bar line from the outgoing project's time map (`TimeMap2_timeToBeats` / `TimeMap2_beatsToTime`), rather than estimating it from a fixed number of seconds. At the boundary, stop that song with `OnStopButtonEx(song)`, select and start the next song, and leave the pad project running. The prototype used a constant 4/4 map; tempo-map and meter-change cases still need coverage during transport implementation.
4. Use the existing named pad tracks as independent playback/fade lanes. Pad gain automation can live on those tracks; song track faders do not need to change. Same-root transitions, pad auto-start policy, and whether pads share the music output remain product choices from plan questions 2 and 3.
5. For output profiles, snapshot each affected track's master-send and hardware-output state before applying the profile. Restore that snapshot before the Native Editor saves a song and before leaving Live. The audio device and available hardware channels must already be configured in REAPER.
6. Close tabs one at a time through REAPER's normal close action. After each prompt returns, compare the open-project list with the pre-close list. Abort setlist loading if a project remains open; do not use `noprompt:` for this flow.

## Prototype results

- With **Run background projects** enabled and **Play stopped background projects with active project** disabled, explicit Play calls produced `songA_state=1` and `pads_state=1`; both pad lanes contained overlapping audio.
- At the first bar boundary, the controller observed Song A at 2.020 seconds, stopped it, selected Song B, and started Song B. The result was Song A stopped, Song B playing, and pads still playing.
- With SWS marker actions enabled, the legacy marker stopped and rewound Song A and selected the next tab, while the pad project remained playing. This confirms why new builds must omit the marker and why Live should warn when a loaded song still contains one; Live does not need to suppress SWS globally.
- Hardware routing and save-prompt cancellation are API-supported paths, not live-device/UI test results from this pass.

## References

- [REAPER User Guide, multiple project tabs](https://dlcf.reaper.fm/userguide/ReaperUserGuide729d.pdf)
- [REAPER ReaScript API](https://www.reaper.fm/sdk/reascript/reascripthelp.html)
- [SWS marker actions](https://www.sws-extension.org/markeractions.php)
