---------------INPUT FUNCTIONS-----------------------
local function prompt_song_settings(CurrentSettings)
  local title = "Song Settings"

  local captions = table.concat({
    "Song name",
    "BPM",
    "Time sig numerator",
    "Time sig denominator",
    "Cue language",
    "Double click? true/false",
    "Song structure"
  }, ",")

  local default_values = table.concat({
    (CurrentSettings.song_name or "Song Name"),
    tostring(CurrentSettings.bpm or "120"),
    tostring(CurrentSettings.time_signature_numerator or "4"),
    tostring(CurrentSettings.time_signature_denominator or "4"),
    CurrentSettings.cue_lang or "EN",
    tostring(CurrentSettings.is_double_click or "false"),
    CurrentSettings.song_structure_text or "Intro:4|Verse:8|Chorus:8|End:4"
  }, ",")

  local ok, retvals = reaper.GetUserInputs(title, 7, captions..",extrawidth=1000", default_values)

  if not ok then return nil end

  local selected_values = {}
  for value in retvals:gmatch("([^,]*)") do
    table.insert(selected_values, value)
  end
  return {
    song_name = selected_values[1],
    bpm = tonumber(selected_values[2]),
    time_signature_numerator = tonumber(selected_values[3]),
    time_signature_denominator = tonumber(selected_values[4]),
    cue_lang = selected_values[5],
    is_double_click = selected_values[6] == "true", -- converting string to bool
    song_structure_text = selected_values[7]
  }
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

  return structure
end

EXTNAME = "AutoTiazinha"

local function save_song_settings(settings)
  reaper.SetProjExtState(0, EXTNAME, "song_name", settings.song_name)
  reaper.SetProjExtState(0, EXTNAME, "bpm", tostring(settings.bpm))
  reaper.SetProjExtState(0, EXTNAME, "time_signature_numerator", tostring(settings.time_signature_numerator))
  reaper.SetProjExtState(0, EXTNAME, "time_signature_denominator", tostring(settings.time_signature_denominator))
  reaper.SetProjExtState(0, EXTNAME, "cue_lang", settings.cue_lang)
  reaper.SetProjExtState(0, EXTNAME, "is_double_click", tostring(settings.is_double_click))
  reaper.SetProjExtState(0, EXTNAME, "song_structure_text", settings.song_structure_text)
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
      song_structure_text = get_proj_ext_value("song_structure_text")
    }
  else
    return false, {nil, nil, nil, nil, nil, nil, nil}
  end
end
---------------INPUT FUNCTIONS END-----------------------


local function open_template(song_name)
  song_name = song_name:gsub('[<>:"/\\|?*]', "_")
  project_name = reaper.GetProjectName(0):gsub("%.RPP$", "")
  project_directory = reaper.GetProjectPath().."/"
  if song_name ~= project_name then
    reaper.Main_OnCommand(40859, 0) -- new project tab command
    reaper.Main_SaveProjectEx(0, project_directory..song_name..".RPP", 8) -- save
  end
  if reaper.GetToggleCommandState(40390)==0  then
    reaper.Main_OnCommand(40390, 0) -- toggle smooth seek on
  end
end

local function insert_click(click, endTime)
  reaper.GetSet_LoopTimeRange(true, false, 0, endTime, false)
  reaper.SetOnlyTrackSelected(click)

  --insert click source command
  reaper.defer(reaper.Main_OnCommand(40013, 0))
end

local function set_double_click(settings)
  if settings.is_double_click and settings.time_signature_numerator == 4 then
    reaper.Main_OnCommand(42457, 0) -- set click pattern to 2x
    reaper.TimeMap_GetMetronomePattern(0, 0.0, "SET:ABBBBBBB")
  else
    reaper.Main_OnCommand(42456, 0) -- set click pattern to 1x
  end
end

local function get_or_create_track(track_name)
  local track_count = reaper.CountTracks(0)
  local click_track, cues_track
  for i=0, track_count-1 do
    local track = reaper.GetTrack(0, i)
    local _, extension_value = reaper.GetSetMediaTrackInfo_String(track,"P_EXT:xyz", "", false)
    if extension_value == EXTNAME then
      local _, p_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
      if p_name == track_name then
        clear_track(track)
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

function clear_track(track)
  local item_count = reaper.CountTrackMediaItems(track)
  for i=item_count-1, 0, -1 do
    media_item = reaper.GetMediaItem(0, i)
    reaper.DeleteTrackMediaItem(track, media_item)
  end
end

local function set_song_bpm_signature(settings)
  reaper.SetTempoTimeSigMarker(0, -1, 0, -1, -1, settings.bpm, settings.time_signature_numerator, settings.time_signature_denominator, false)
end

--function to calculate time positions since AddRegionOrMarker works based on time and not measure/beats
local function calculate_position(measure, beat)
  if beat then
    local measure_beat = measure.."."..beat..".00"
    local time = reaper.parse_timestr_pos(measure_beat, 1) -- verify if there are that many beats in the measure
    if measure_beat == reaper.format_timestr_pos(time, "", 1) then
      return true, time
    else
      return false, -1
    end
  else
    return reaper.parse_timestr_pos(measure..".1.00", 1)
  end
end

-- looping through song structure and creating regions
local function generate_song(settings, start, cues_track)
  local idx = 1
  local next_section_start = start
  local structure = settings.song_structure

  --adding marker to jump to on song start
  reaper.AddRegionOrMarker(0, false, calculate_position(start-1), 0, "Start", idx, 0)

  reaper.SetOnlyTrackSelected(cues_track)
  for _, section in ipairs(structure) do
    next_section_start = create_section(idx, section.name, next_section_start, section.measures, settings)
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
  for i=0, idx do
    reaper.DeleteProjectMarkerByIndex(0, 0)
  end
  idx = reaper.CountTempoTimeSigMarkers(0)
  for i=0, idx do
    reaper.DeleteTempoTimeSigMarker(0, 0)
    reaper.UpdateTimeline()
  end
end

function parse_measures(measures_string)
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

function create_section(idx, section_name, section_start, section_measures, settings)
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
      measure_count = measure_count + 1
      reaper.SetTempoTimeSigMarker(0, -1, -1, section_start+measure_count-1, 0, settings.bpm, settings.time_signature_numerator, settings.time_signature_denominator, false)
    else
      measure_count = measure_count + value
    end
  end
  local section_end_time = calculate_position(section_start+measure_count)
  reaper.AddRegionOrMarker(0, true, section_start_time, section_end_time, section_name, idx, 0)

  local script_path = ({reaper.get_action_context()})[2]
  local script_dir = script_path:match("^(.*)[/\\]")
  local cue_dir = script_dir  .. "/media/" .. cue_lang .. "/"

  local cue_position
  _, cue_position = calculate_position(section_start-1, 1)
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

local function clean_vars()
  if autoCrossState ~= reaper.GetToggleCommandState(40041) then
    reaper.Main_OnCommand(40041, 0) --toggle auto crossfade to original when editing
  end
end
-- START OF SCRIPT
autoCrossState = reaper.GetToggleCommandState(40041)
if autoCrossState == 1  then -- toggle auto crossfade when editing
  reaper.Main_OnCommand(40041, 0) -- toggle auto crossfade when editing
end
local song_start = 5

local retval, loaded_settings = load_song_settings()
local settings = prompt_song_settings(loaded_settings)

if not settings then -- this deals with cancels on the prompt
  return
end

settings.song_structure = parse_song_structure(settings.song_structure_text)

open_template(settings.song_name)
save_song_settings(settings)

clear_previous_structure()
set_song_bpm_signature(settings)
set_double_click(settings)

local click_track = get_or_create_track("Click")
local cues_track = get_or_create_track("Cues")

local song_ending = generate_song(settings, song_start, cues_track)

insert_click(click_track, song_ending+1)

reaper.GetSet_LoopTimeRange(true, true, 0, calculate_position(song_start-2), false) -- set loop to stop two measures before songstart
reaper.GetSetRepeat(1)

reaper.SetEditCurPos(0, true, false)

reaper.UpdateTimeline()
reaper.atexit(clean_vars())
reaper.Main_SaveProject(0, false) -- save once done
