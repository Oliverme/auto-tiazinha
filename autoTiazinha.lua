--reaper.ShowConsoleMsg("")

---------------INPUT FUNCTIONS-----------------------
local function prompt_song_settings(currentSettings)
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
  
  local defaultValues = table.concat({
    (currentSettings.songName or ""),
    tostring(currentSettings.bpm or 120),
    tostring(currentSettings.timeSigNum or 4),
    tostring(currentSettings.timeSigDenom or 4),
    currentSettings.cueLang or "EN",
    tostring(currentSettings.doubleClick or false),
    currentSettings.structureText or "Intro:8|Verse:8|Chorus:8|End:4"
  }, ",")

  local ok, retvals = reaper.GetUserInputs(title, 7, captions..",extrawidth=1500", defaultValues)

  if not ok then return nil end

  local values = {}
  for value in retvals:gmatch("([^,]*)") do
    table.insert(values, value)
  end
  return {
    songName = values[1],
    bpm = tonumber(values[2]),
    timeSigNum = tonumber(values[3]),
    timeSigDenom = tonumber(values[4]),
    cueLang = values[5],
    doubleClick = values[6] == "true",
    structureText = values[7]
  }
end

local function parse_song_structure(text)
  local structure = {}

  for part in text:gmatch("([^|]+)") do
    --local name, measures = part:match("^%s*(.-)%s*:%s*(%d+)%s*$")
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
  reaper.SetProjExtState(0, EXTNAME, "songName", settings.songName or "blank")
  reaper.SetProjExtState(0, EXTNAME, "bpm", tostring(settings.bpm or 120))
  reaper.SetProjExtState(0, EXTNAME, "timeSigNum", tostring(settings.timeSigNum or 4))
  reaper.SetProjExtState(0, EXTNAME, "timeSigDenom", tostring(settings.timeSigDenom or 4))
  reaper.SetProjExtState(0, EXTNAME, "cueLang", settings.cueLang or "EN")
  reaper.SetProjExtState(0, EXTNAME, "doubleClick", tostring(settings.doubleClick or false))
  reaper.SetProjExtState(0, EXTNAME, "structureText", settings.structureText or "Intro:4")
end

-------------------------
local function get_proj_ext_value(key, fallback)
  local retval, value = reaper.GetProjExtState(0, EXTNAME, key)
  
  if retval == 1 and value ~= "" then
    return value
  end

  return fallback
end

local function load_song_settings()
  return {
    songName = get_proj_ext_value("songName", "semNome"),
    bpm = tonumber(get_proj_ext_value("bpm", "120")),
    timeSigNum = tonumber(get_proj_ext_value("timeSigNum", "4")),
    timeSigDenom = tonumber(get_proj_ext_value("timeSigDenom", "4")),
    cueLang = get_proj_ext_value("cueLang", "EN"),
    doubleClick = get_proj_ext_value("doubleClick", "false"),
    structureText = get_proj_ext_value("structureText", "Intro:8|Verse:8|Chorus:8|End:4")
  }
end
---------------INPUT FUNCTIONS END-----------------------


function openTemplate(songName)
  --check if the project has the same name as the song. 
  --recreate the project if it does and create a new project if it doesnt
  songName = songName:gsub('[<>:"/\\|?*]', "_")
  local _, filename = reaper.EnumProjects(-1, "")
  if filename ~= "" then
    projectDir = filename:match("(.*[/\\])")--project directory
    local projectName = filename:match("[^/\\]+$"):gsub("%.RPP$", "")--match removes path, gsub removes .rpp
    if projectName == songName then
      --reaper.ShowConsoleMsg("same project name, deleting current tab and recreating it\n")
      reaper.Main_OnCommand(40860, 0)--closes current tab
    end
  end
  
  reaper.Main_OnCommand(40859, 0)--new project tab command
  --reaper.ShowConsoleMsg(reaper.GetToggleCommandState(40390).."\n")
  if reaper.GetToggleCommandState(40390)==0  then
    reaper.Main_OnCommand(40390, 0) --toggle smooth seek
  end
  autoCrossState = reaper.GetToggleCommandState(40041)
  if autoCrossState == 1  then --toggle auto crossfade when editing
    reaper.Main_OnCommand(40041, 0) --toggle auto crossfade when editing
  end
  --reaper.ShowConsoleMsg(projectDir..songName..".RPP".."\n")
  reaper.Main_SaveProjectEx(0, projectDir..songName..".RPP", 8) --save new version
end

function createTrack(name)
  -- Get the current number of tracks
  local track_count = reaper.CountTracks(0)
  
  -- Insert a new track at the end (index is 0-based)
  -- Use -1 or track_count to put it at the bottom
  reaper.InsertTrackAtIndex(track_count, true)
  
  -- Get the newly created track to modify it (optional)
  local new_track = reaper.GetTrack(0, track_count)
  reaper.GetSetMediaTrackInfo_String(new_track, "P_NAME", name, true)
  return new_track
end

function insertClick(click, endTime)
  reaper.GetSet_LoopTimeRange(true, false, 0, endTime, false)
  reaper.SetOnlyTrackSelected(click)
  
  --insert click source command
  reaper.defer(reaper.Main_OnCommand(40013, 0))
end

function setDoubleClick(doubleSpeed, timeSigNum)
  if doubleSpeed and timeSigNum==4 then
    reaper.Main_OnCommand(42457, 0) --set click pattern to 2x
    reaper.TimeMap_GetMetronomePattern(0, 0.0, "SET:ABBBBBBB")
  else
    reaper.Main_OnCommand(42456, 0) --set click pattern to 1x
  end
end

--function to calculate time positions since AddRegionOrMarker works based on time and not measure/beats
function calcTime(measure, beat)
  if beat ~= nil then
    measureBeatConcat = measure.."."..beat..".00"
    local timeCheck = reaper.parse_timestr_pos(measureBeatConcat, 1) -- verify if there are that many beats in the measure
    if measureBeatConcat == reaper.format_timestr_pos(timeCheck, "", 1) then
      return true, timeCheck
    else
      return false, -1
    end
  else
    return reaper.parse_timestr_pos(measure..".1.00", 1)
  end
end

-- looping through song structure and creating regions
function createSongStructure(structure, start, cuesTrack)
  local idx = 1
  local currentSection = start
  
  --adding marker to jump to on song start
  reaper.AddRegionOrMarker(0, false, calcTime(start-1), 0, "Start", idx, 0)
  
  reaper.SetOnlyTrackSelected(cuesTrack)
  for _, section in ipairs(structure) do
    currentSection = createSection(idx, section.name, currentSection, section.measures)
    idx = idx + 1
  end
  local songEndingTime = calcTime(currentSection)
  local setCursorStart = 40042
  local stopPlayingCommand  = 40044
  local nextTabCommand = 40861
  reaper.AddRegionOrMarker(0, false, songEndingTime, 0, "! " .. stopPlayingCommand ..  " " .. setCursorStart .. " " .. nextTabCommand, idx, 0)
  return songEndingTime
end

function parse_measures(measuresString)
  local parsed = {}

  local i = 1

  while i <= #measuresString do
    local char = measuresString:sub(i, i)

    -- Dot means one half measure
    if char == "." then
      table.insert(parsed, 0.5)
      i = i + 1

    -- Number means full-measure count.
    elseif char:match("%d") then
      local numberText = measuresString:match("^%d+", i)
      local number = tonumber(numberText)

      if not number or number < 1 then
        error("Invalid measure value: " .. tostring(numberText))
      end

      table.insert(parsed, number)
      i = i + #numberText

    else
      error("Invalid character in measures string: " .. char)
    end
  end

  return parsed
end

function createSection(idx, sectionName, sectionStart, sectionMeasures)
  local sectionStartTime = calcTime(sectionStart)
  local measureCount = 0
  local parsedMeasureTable = {}
  
  if sectionMeasures:match("%.") then
    parsedMeasureTable = parse_measures(sectionMeasures)
  else
    parsedMeasureTable = {tonumber(sectionMeasures)}
  end
  
  for _, value in ipairs(parsedMeasureTable) do
    if value == 0.5 then
      --do half measure stuff
      reaper.SetTempoTimeSigMarker(0, -1, -1, sectionStart+measureCount-1, (songTimeSigNum/2)-1, bpm, songTimeSigNum/2, songTimeSigDenom, false)
      measureCount = measureCount + 1
      reaper.SetTempoTimeSigMarker(0, -1, -1, sectionStart+measureCount-1, 0, bpm, songTimeSigNum, songTimeSigDenom, false)
    else
      measureCount = measureCount + value
    end
  end
  local sectionEndTime = calcTime(sectionStart+measureCount) 
  reaper.AddRegionOrMarker(0, true, sectionStartTime, sectionEndTime, sectionName, idx, 0)
  

  local scriptPath = ({reaper.get_action_context()})[2]
  local scriptDir = scriptPath:match("^(.*)[/\\]")
  local cueDir = scriptDir  .. "/media/" .. cueLang .. "/"
 
  --inserting cues
  if cueLang == "EN" then
    cueDir = cueDir.."English Female - "
  elseif cueLang == "PT" then
    cueDir = cueDir.."Portugese - "
  end
  
  _, cuePos = calcTime(sectionStart-1, 1)
  reaper.SetEditCurPos(cuePos, false, false)
  if sectionName == "Chorus" then
    reaper.InsertMedia(cueDir.."Chorus.wav",0)
  elseif sectionName == "Verse" then
    reaper.InsertMedia(cueDir.."Verse.wav",0)
  elseif sectionName == "Intro" then
    reaper.InsertMedia(cueDir.."Intro.wav",0)
  elseif sectionName == "Interlude" then
    reaper.InsertMedia(cueDir.."Interlude.wav",0)
  elseif sectionName == "Bridge" then
    reaper.InsertMedia(cueDir.."Bridge.wav",0)
  elseif sectionName == "End" then
    reaper.InsertMedia(cueDir.."Ending.wav",0)
  elseif sectionName == "Pre-Chorus" then
    reaper.InsertMedia(cueDir.."Pre Chorus.wav",0)
  elseif sectionName == "Instrumental" then
    reaper.InsertMedia(cueDir.."Instrumental.wav",0)
  elseif sectionName == "Solo" then
    reaper.InsertMedia(cueDir.."Solo.wav",0)
  elseif sectionName == "Breakdown" then
    reaper.InsertMedia(cueDir.."Breakdown.wav",0)
  end
  
  beatFound, position = calcTime(sectionStart-1, 2)
  if beatFound then 
    reaper.SetEditCurPos(position, false, false)
    reaper.InsertMedia(cueDir.."2.wav",0)
  end
  beatFound, position = calcTime(sectionStart-1, 3)
  if beatFound then 
    reaper.SetEditCurPos(position, false, false)
    reaper.InsertMedia(cueDir.."3.wav",0)
  end
  beatFound, position = calcTime(sectionStart-1, 4)
  if beatFound then 
    reaper.SetEditCurPos(position, false, false)
    reaper.InsertMedia(cueDir.."4.wav",0)
  end
  beatFound, position = calcTime(sectionStart-1, 5)
  if beatFound then
    reaper.SetEditCurPos(position, false, false)
    reaper.InsertMedia(cueDir.."5.wav",0)
    beatFound, position = calcTime(sectionStart-1, 61)
    reaper.SetEditCurPos(position, false, false)
    reaper.InsertMedia(cueDir.."6.wav",0)
  end
  return sectionStart+measureCount
end

-- START OF SCRIPT

local defaults = load_song_settings()
local settings = prompt_song_settings(defaults)
-- this deals with cancels on the prompt
if not settings then
  return
end
settings.songStructure = parse_song_structure(settings.structureText)
--set variables to be used in project
projectDir = reaper.GetProjectPath().."/"
cueLang = settings.cueLang
songTimeSigNum = settings.timeSigNum
songTimeSigDenom = settings.timeSigDenom
bpm = settings.bpm
local songStart = 5

openTemplate(settings.songName)
save_song_settings(settings)
--set tempo and time signature
reaper.SetTempoTimeSigMarker(0, -1, 0, -1, -1, settings.bpm, songTimeSigNum, songTimeSigDenom, false)

--need to set it before because strange things happen to the cues track if set at the end
setDoubleClick(settings.doubleClick, songTimeSigNum)

local clickTrack = createTrack("Click")
local cuesTrack = createTrack("Cues")

local songEnding = createSongStructure(settings.songStructure, songStart, cuesTrack)

insertClick(clickTrack, songEnding+1)

reaper.GetSet_LoopTimeRange(true, true, 0, calcTime(songStart-2), false) -- set loop to stop two measures before songstart
--problems can happen when you try to go to the first marker and it coincides with the end of the loop
reaper.GetSetRepeat(1)

reaper.SetEditCurPos(0, true, false)

reaper.UpdateTimeline()
if autoCrossState ~= reaper.GetToggleCommandState(40041) then
  reaper.Main_OnCommand(40041, 0) --toggle auto crossfade to original when editing
end
reaper.Main_SaveProject(0, false) -- save once done
