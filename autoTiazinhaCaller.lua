-- REAPER action entry point. Keep beside autoTiazinhaBuilder.lua.
local script_path = debug.getinfo(1, "S").source:sub(2)
local script_dir = script_path:match("^(.*)[/\\]") or "."
local builder = dofile(script_dir .. "/autoTiazinhaBuilder.lua")

local function prompt_song_settings(CurrentSettings)
  local title = "Song Settings"

  local captions = table.concat({
    "Song name",
    "BPM",
    "Time sig numerator",
    "Time sig denominator",
    "Cue language",
    "Double click? true/false",
    "Song structure",
    "Click Accent",
    "Click Secondary"
  }, ",")

  local default_values = table.concat({
    (CurrentSettings.song_name or "Song Name"),
    tostring(CurrentSettings.bpm or "120"),
    tostring(CurrentSettings.time_signature_numerator or "4"),
    tostring(CurrentSettings.time_signature_denominator or "4"),
    CurrentSettings.cue_lang or "EN",
    tostring(CurrentSettings.is_double_click or "false"),
    CurrentSettings.song_structure_text or "Intro:4|Verse:8|Chorus:8|Ending:4",
    CurrentSettings.click_accent or "",
    CurrentSettings.click_beat or ""
  }, ",")

  local ok, retvals = reaper.GetUserInputs(title, 9, captions..",extrawidth=1000", default_values)

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
    song_structure_text = selected_values[7],
    click_accent = selected_values[8],
    click_beat = selected_values[9]
  }
end

local _, loaded_settings = builder.load_song_settings()
local settings = prompt_song_settings(loaded_settings)
if not settings then return end

builder.build(settings)
