-- Shared AutoTiazinha builder. Loading this file does not modify REAPER.
-- Keep this file beside the media/ directory.
-- Usage: local builder = dofile(path_to_builder)
--        local found, settings = builder.load_song_settings()
--        builder.build(settings)
-- build accepts the same settings table as the original dialog, including
-- song_structure_text. It retains project creation, regeneration, loop setup,
-- and saving behavior. It returns the song ending position in seconds.
local builder = {}
local script_path = debug.getinfo(1, "S").source:sub(2)
local script_dir = script_path:match("^(.*)[/\\]") or "."
local clear_track, create_section

-- Keep region colors aligned with the editor palette. Numbered cues inherit
-- their base section's color, and every uncategorized section uses one slate.
local SECTION_COLORS = {
  Intro = {41, 79, 125},
  Verse = {133, 56, 46},
  ["Pre Chorus"] = {26, 99, 92},
  Chorus = {133, 92, 20},
  Bridge = {92, 59, 125},
  Ending = {56, 61, 71},
}
local OTHER_SECTION_COLOR = {64, 79, 97}

local function section_region_color(name)
  local base = name:match("^(.-)%s+%d+$") or name
  local rgb = SECTION_COLORS[base] or OTHER_SECTION_COLOR
  return reaper.ColorToNative(rgb[1], rgb[2], rgb[3]) | 0x1000000
end

local function parse_song_structure(text)
  local structure = {}

  for part in text:gmatch("([^|]+)") do
    local name, measures = part:match("^%s*(.-)%s*:%s*(.-)%s*$")
    --reaper.ShowConsoleMsg("name: "..name.."\n\tmeasures: "..measures.."\n")
    if name and measures then
      table.insert(structure, {
        name = name,
        measures = measures
      })
    else
      error("Invalid song structure part: " .. part)
    end
  end

  for i,section in ipairs(structure) do
    if section.measures:match('^0+$') and i~=#structure then
      error('Only the final section can have zero bars.')
    end
  end
  return structure
end

local EXTNAME = "AutoTiazinha"

local function save_song_settings(settings)
  reaper.SetProjExtState(0, EXTNAME, "song_name", settings.song_name)
  reaper.SetProjExtState(0, EXTNAME, "bpm", tostring(settings.bpm))
  reaper.SetProjExtState(0, EXTNAME, "time_signature_numerator", tostring(settings.time_signature_numerator))
  reaper.SetProjExtState(0, EXTNAME, "time_signature_denominator", tostring(settings.time_signature_denominator))
  reaper.SetProjExtState(0, EXTNAME, "cue_lang", settings.cue_lang)
  reaper.SetProjExtState(0, EXTNAME, "is_double_click", tostring(settings.is_double_click))
  reaper.SetProjExtState(0, EXTNAME, "song_structure_text", settings.song_structure_text)
  reaper.SetProjExtState(0, EXTNAME, "click_accent", settings.click_accent)
  reaper.SetProjExtState(0, EXTNAME, "click_beat", settings.click_beat)
end

-------------------------
local function get_proj_ext_value(key)
  local retval, value = reaper.GetProjExtState(0, EXTNAME, key)

  if retval == 1 and value ~= "" then
    return value
  end

  return false
end

local function load_song_settings()
  if get_proj_ext_value("song_name") then
    return true, {
      song_name = get_proj_ext_value("song_name"),
      bpm = tonumber(get_proj_ext_value("bpm")),
      time_signature_numerator = tonumber(get_proj_ext_value("time_signature_numerator")),
      time_signature_denominator = tonumber(get_proj_ext_value("time_signature_denominator")),
      cue_lang = get_proj_ext_value("cue_lang"),
      is_double_click = get_proj_ext_value("is_double_click"),
      song_structure_text = get_proj_ext_value("song_structure_text"),
      click_accent = get_proj_ext_value("click_accent"),
      click_beat = get_proj_ext_value("click_beat")
    }
  else
    return false, {nil, nil, nil, nil, nil, nil, nil, nil, nil}
  end
end


local function open_template(song_name)
  song_name = song_name:gsub('[<>:"/\\|?*]', "_")
  local project_name = reaper.GetProjectName(0):gsub("%.RPP$", "")
  local project_directory = reaper.GetProjectPath().."/"
  if song_name ~= project_name then
    reaper.Main_OnCommand(40859, 0) -- new project tab command
    reaper.Main_SaveProjectEx(0, project_directory..song_name..".RPP", 8) -- save
  end
  if reaper.GetToggleCommandState(40390)==0  then
    reaper.Main_OnCommand(40390, 0) -- toggle smooth seek on
  end
end

local function has_click_line(chunk, key)
  return chunk:find("[\r\n][ \t]*" .. key .. "[ \t]+[^\r\n]*") ~= nil
      or chunk:find("^[ \t]*" .. key .. "[ \t]+[^\r\n]*") ~= nil
end

local function is_suitable_click_chunk(chunk)
  -- A generated click item is a looping CLICK source with the source fields
  -- needed for safe in-place updates. Reusing any other item would silently
  -- turn it into a click item and could leave an item that cannot follow a
  -- longer song.
  if type(chunk) ~= "string" or chunk:find("<SOURCE[ \t]+CLICK") == nil then
    return false
  end
  for _, key in ipairs({"LOOP", "BPM", "BPI", "VOL", "SAMPLES", "PATTERN", "PATTERNSTR", "MULT"}) do
    if not has_click_line(chunk, key) then return false end
  end
  return true
end

local function inspect_click_item(click)
  if reaper.CountTrackMediaItems(click) ~= 1 then return nil end

  local media_item = reaper.GetTrackMediaItem(click, 0)
  if not media_item then return nil end

  local call_ok, chunk_ok, chunk = pcall(reaper.GetItemStateChunk, media_item, "", true)
  if not call_ok or not chunk_ok or not is_suitable_click_chunk(chunk) then
    return nil
  end
  return media_item, chunk
end

local function replace_click_line(chunk, key, value)
  local pattern = "([ \t]*)" .. key .. "[ \t]+[^\r\n]*"
  local replaced, count = chunk:gsub(pattern, function(indent)
    return indent .. key .. " " .. value
  end, 1)
  if count ~= 1 then return nil end
  return replaced
end

local function encode_click_pattern(pattern)
  -- REAPER stores each click as a two-bit value. The values observed in its
  -- project chunks are A=01 and B=10.
  -- Building from the least-significant pair avoids depending on a bitwise
  -- library that is not available in all Lua versions supported by REAPER.
  local encoded = 1
  local place = 4
  for _ = 2, #pattern do
    encoded = encoded + 2 * place
    place = place * 4
  end
  return encoded
end

local function configure_click_item(media_item, chunk, settings, end_time)
  local click_dir = script_dir .. "/media/click/"
  local click_accent_sample = settings.click_accent == ""
      and "\"\""
      or "\"" .. click_dir .. settings.click_accent .. ".wav\""
  local click_beat_sample = settings.click_beat == ""
      and "\"\""
      or "\"" .. click_dir .. settings.click_beat .. ".wav\""
  local samples = click_accent_sample .. " " .. click_beat_sample .. " \"\" \"\""
  local double_click = settings.is_double_click and settings.time_signature_numerator == 4
  local pattern = double_click
      and "ABBBBBBB"
      or "A" .. string.rep("B", settings.time_signature_numerator - 1)
  -- REAPER serializes a CLICK source in quarter-note units even when the
  -- project denominator is not 4. Match the native source created by command
  -- 40013: convert the project BPM to quarter-note BPM and keep BPI's
  -- denominator at 4 (for example, 92 BPM in 6/8 becomes BPM 184, BPI 6 4).
  local click_bpm = settings.bpm * settings.time_signature_denominator / 4

  local updated_chunk = chunk
  local replacements = {
    {"BPM", tostring(click_bpm)},
    {"BPI", tostring(settings.time_signature_numerator) .. " 4"},
    {"VOL", "0.5 0.354"},
    {"SAMPLES", samples},
    {"PATTERN", "0 " .. tostring(encode_click_pattern(pattern))},
    {"PATTERNSTR", pattern},
    {"MULT", double_click and "2" or "1"}
  }
  for _, replacement in ipairs(replacements) do
    updated_chunk = replace_click_line(updated_chunk, replacement[1], replacement[2])
    if not updated_chunk then
      return false
    end
  end

  if updated_chunk ~= chunk then
    reaper.SetItemStateChunk(media_item, updated_chunk, true)
  end
  -- Set these after the chunk so its serialized POSITION/LENGTH fields cannot
  -- overwrite the geometry required by the current build.
  reaper.SetMediaItemInfo_Value(media_item, "D_POSITION", 0)
  reaper.SetMediaItemInfo_Value(media_item, "D_LENGTH", end_time)
  reaper.UpdateItemInProject(media_item)
  return true
end

local function insert_click(click, settings, end_time)
  reaper.GetSet_LoopTimeRange(true, false, 0, end_time, false)
  reaper.SetOnlyTrackSelected(click)

  local media_item, chunk = inspect_click_item(click)
  if not media_item then
    -- A missing, malformed, or duplicated item is not safe to update in place.
    -- Rebuild it with REAPER's native command so its CLICK source semantics and
    -- project import preferences stay identical to the original Builder.
    clear_track(click)
    reaper.Main_OnCommand(40013, 0)
    media_item, chunk = inspect_click_item(click)
    if not media_item then
      error("REAPER did not create a suitable Click media item")
    end
  end

  if not configure_click_item(media_item, chunk, settings, end_time) then
    error("Click media item has an incomplete CLICK source")
  end
end

local function set_double_click(settings)
  if settings.is_double_click and settings.time_signature_numerator == 4 then
    reaper.Main_OnCommand(42457, 0) -- set click pattern to 2x
    reaper.TimeMap_GetMetronomePattern(0, 0.0, "SET:ABBBBBBB")
  else
    reaper.Main_OnCommand(42456, 0) -- set click pattern to 1x
  end
end

local function get_or_create_track(track_name, clear_existing_items)
  local track_count = reaper.CountTracks(0)
  for i=0, track_count-1 do
    local track = reaper.GetTrack(0, i)
    local _, extension_value = reaper.GetSetMediaTrackInfo_String(track,"P_EXT:xyz", "", false)
    if extension_value == EXTNAME then
      local _, p_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
      if p_name == track_name then
        if clear_existing_items then
          clear_track(track)
        end
        return track
      end
    end
  end
  reaper.InsertTrackInProject(0, track_count, 0)
  local new_track = reaper.GetTrack(0, track_count)
  reaper.GetSetMediaTrackInfo_String(new_track, "P_NAME", track_name, true)
  reaper.GetSetMediaTrackInfo_String(new_track, "P_EXT:xyz", EXTNAME, true)
  return new_track
end

clear_track = function(track)
  local item_count = reaper.CountTrackMediaItems(track)
  for i=item_count-1, 0, -1 do
    local media_item = reaper.GetTrackMediaItem(track, i)
    reaper.DeleteTrackMediaItem(track, media_item)
  end
end

local function set_song_bpm_signature(settings)
  reaper.SetTempoTimeSigMarker(0, -1, 0, -1, -1, settings.bpm, settings.time_signature_numerator, settings.time_signature_denominator, false)
end

-- Calculate positions without going through REAPER's formatted position strings.
-- `TimeMap2_beatsToTime` accepts a zero-based measure count and a zero-based beat
-- offset. The Builder's measure numbers are one-based, so the conversion is
-- measure-1 / beat-1. TimeMap_GetMeasureInfo gives us both the measure start and
-- its actual numerator, which preserves the old invalid-beat check for 4/4,
-- 6/8, and partial measures.
--
-- REAPER's time map changes while partial sections are being installed. The
-- cache is therefore invalidated after each time-signature marker is inserted;
-- stable boundaries are shared for the rest of the build.
local function new_position_calculator()
  local measure_cache = {}
  local beat_cache = {}

  local function invalidate()
    measure_cache = {}
    beat_cache = {}
  end

  local function measure_info(measure)
    local cached = measure_cache[measure]
    if cached then return cached end

    local start_time, _, _, beats = reaper.TimeMap_GetMeasureInfo(0, measure - 1)
    if type(start_time) ~= "number" or type(beats) ~= "number" then
      error("REAPER could not resolve measure " .. tostring(measure))
    end

    cached = {start_time = start_time, beats = beats}
    measure_cache[measure] = cached
    return cached
  end

  local function calculate_position(measure, beat)
    local info = measure_info(measure)
    if not beat then
      return info.start_time
    end

    local key = measure .. ":" .. beat
    local cached = beat_cache[key]
    if cached then return cached[1], cached[2] end

    -- A direct conversion of an out-of-range beat would silently land at the
    -- next measure. Reject it before conversion, matching the former
    -- parse/format round-trip validation.
    if beat < 1 or beat > info.beats then
      cached = {false, -1}
    else
      cached = {true, reaper.TimeMap2_beatsToTime(0, beat - 1, measure - 1)}
    end
    beat_cache[key] = cached
    return cached[1], cached[2]
  end

  return calculate_position, invalidate
end

-- looping through song structure and creating regions
local function generate_song(settings, start, cues_track, calculate_position, invalidate_positions)
  local idx = 1
  local next_section_start = start
  local structure = settings.song_structure

  --adding marker to jump to on song start
  reaper.AddRegionOrMarker(0, false, calculate_position(start-1), 0, "Start", idx, 0)

  reaper.SetOnlyTrackSelected(cues_track)
  for _, section in ipairs(structure) do
    next_section_start = create_section(idx, section.name, next_section_start, section.measures, settings, calculate_position, invalidate_positions)
    idx = idx + 1
  end
  local song_ending_time = calculate_position(next_section_start)
  local reset_cursor_command = 40042
  local stop_playing_command  = 40044
  local next_tab_command = 40861
  reaper.AddRegionOrMarker(0, false, song_ending_time, 0, "! " .. stop_playing_command ..  " " .. reset_cursor_command .. " " .. next_tab_command, idx, 0)
  return song_ending_time
end

local function clear_previous_structure()
  local idx = reaper.GetNumRegionsOrMarkers(0)
  for i=idx-1, 0, -1 do
    reaper.DeleteProjectMarkerByIndex(0, i)
  end
  idx = reaper.CountTempoTimeSigMarkers(0)
  for i=idx-1, 0, -1 do
    reaper.DeleteTempoTimeSigMarker(0, i)
  end
end

local function parse_measures(measures_string)
  local parsed = {}

  local i = 1

  while i <= #measures_string do
    local char = measures_string:sub(i, i)

    -- Dot means one half measure
    if char == "." then
      table.insert(parsed, 0.5)
      i = i + 1

    -- Number means full-measure count.
    elseif char:match("%d") then
      local number_text = measures_string:match("^%d+", i)
      local number = tonumber(number_text)

      if not number or number < 1 then
        error("Invalid measure value: " .. tostring(number_text))
      end

      table.insert(parsed, number)
      i = i + #number_text

    else
      error("Invalid character in measures string: " .. char)
    end
  end

  return parsed
end

create_section = function(idx, section_name, section_start, section_measures, settings, calculate_position, invalidate_positions)
  local section_start_time = calculate_position(section_start)
  local measure_count = 0
  local parsedMeasureTable = {}
  local cue_lang = settings.cue_lang

  if section_measures:match("%.") then
    parsedMeasureTable = parse_measures(section_measures)
  else
    parsedMeasureTable = {tonumber(section_measures)}
  end

  for _, value in ipairs(parsedMeasureTable) do
    if value == 0.5 then
      --do half measure stuff
      reaper.SetTempoTimeSigMarker(0, -1, -1, section_start+measure_count-1, (settings.time_signature_numerator/2)-1, settings.bpm, settings.time_signature_numerator/2, settings.time_signature_denominator, false)
      invalidate_positions()
      measure_count = measure_count + 1
      reaper.SetTempoTimeSigMarker(0, -1, -1, section_start+measure_count-1, 0, settings.bpm, settings.time_signature_numerator, settings.time_signature_denominator, false)
      invalidate_positions()
    else
      measure_count = measure_count + value
    end
  end
  local section_end_time = calculate_position(section_start+measure_count)
  -- A zero-bar final section is a cue only. The end action marker below
  -- generation lands at its start; do not create an empty region.
  if measure_count>0 then
    reaper.AddRegionOrMarker(0, true, section_start_time, section_end_time, section_name, idx, section_region_color(section_name))
  end

  local cue_dir = script_dir  .. "/media/" .. cue_lang .. "/"

  local _, cue_position = calculate_position(section_start-1, 1)
  reaper.SetEditCurPos(cue_position, false, false)
  reaper.InsertMedia(cue_dir..section_name..".wav", 0)

  local beat_found, position = calculate_position(section_start-1, 2)
  if beat_found then
    reaper.SetEditCurPos(position, false, false)
    reaper.InsertMedia(cue_dir.."2.wav",0)
  end
  beat_found, position = calculate_position(section_start-1, 3)
  if beat_found then
    reaper.SetEditCurPos(position, false, false)
    reaper.InsertMedia(cue_dir.."3.wav",0)
  end
  beat_found, position = calculate_position(section_start-1, 4)
  if beat_found then
    reaper.SetEditCurPos(position, false, false)
    reaper.InsertMedia(cue_dir.."4.wav",0)
  end
  beat_found, position = calculate_position(section_start-1, 5)
  if beat_found then
    reaper.SetEditCurPos(position, false, false)
    reaper.InsertMedia(cue_dir.."5.wav",0)
    beat_found, position = calculate_position(section_start-1, 6)
    reaper.SetEditCurPos(position, false, false)
    reaper.InsertMedia(cue_dir.."6.wav",0)
  end
  return section_start+measure_count
end

-- Expose stored settings so each entry point can populate its own interface.
builder.load_song_settings = load_song_settings

function builder.build(settings)
  local autoCrossState = reaper.GetToggleCommandState(40041)
  local ui_refresh_prevented = false

  local function prevent_ui_refresh()
    reaper.PreventUIRefresh(1)
    ui_refresh_prevented = true
  end

  local function allow_ui_refresh()
    if ui_refresh_prevented then
      -- Mark the guard inactive before calling into REAPER so a release
      -- failure is not retried and cannot mask the build's original error.
      ui_refresh_prevented = false
      reaper.PreventUIRefresh(-1)
    end
  end

  local function restore_crossfade()
    if autoCrossState ~= reaper.GetToggleCommandState(40041) then
      reaper.Main_OnCommand(40041, 0)
    end
  end

  -- Restore after every build (including errors), even in a persistent GUI.
  local ok, result = xpcall(function()
    if autoCrossState == 1 then
      reaper.Main_OnCommand(40041, 0)
    end
    local song_start = 4

    settings.song_structure = parse_song_structure(settings.song_structure_text)

    open_template(settings.song_name)
    save_song_settings(settings)

    prevent_ui_refresh()

    clear_previous_structure()
    set_song_bpm_signature(settings)
    set_double_click(settings)

    -- Keep the Click item available for in-place regeneration. Cues are still
    -- intentionally cleared because their topology follows the song sections.
    local click_track = get_or_create_track("Click", false)
    local cues_track = get_or_create_track("Cues", true)

    -- The map is ready after the base tempo/signature has been installed.
    -- Keep one calculator for the complete build so section and cue boundaries
    -- are shared, while create_section invalidates it when a partial-measure
    -- signature changes the map.
    local calculate_position, invalidate_positions = new_position_calculator()
    local song_ending = generate_song(settings, song_start, cues_track, calculate_position, invalidate_positions)

    insert_click(click_track, settings, song_ending+1)

    reaper.GetSet_LoopTimeRange(true, true, 0, calculate_position(song_start-2), false) -- set loop to stop two measures before songstart
    reaper.GetSetRepeat(1)

    reaper.SetEditCurPos(0, true, false)

    allow_ui_refresh()
    reaper.UpdateTimeline()
    reaper.Main_SaveProject(0, false) -- save once done
    return song_ending
  end, debug.traceback)

  local ui_refresh_ok, ui_refresh_error = xpcall(allow_ui_refresh, debug.traceback)
  local crossfade_ok, crossfade_error = xpcall(restore_crossfade, debug.traceback)
  if not ok then error(result, 0) end
  if not ui_refresh_ok then error(ui_refresh_error, 0) end
  if not crossfade_ok then error(crossfade_error, 0) end
  return result
end

return builder
