-- Open one REAPER project tab per setlist occurrence, plus one shared pad tab.
local M = {}

local function projects(api)
  local result, index = {}, 0
  while true do
    local project, path = api.EnumProjects(index, '')
    if not project then return result end
    result[#result+1] = {project=project, path=path}
    index = index+1
  end
end

local function contains(api, project)
  for _, entry in ipairs(projects(api)) do
    if entry.project == project then return true end
  end
  return false
end

local function open_tab(api, path)
  local current, current_path = api.EnumProjects(-1, '')
  if not current or current_path ~= '' or api.IsProjectDirty(current) ~= 0 then
    api.Main_OnCommand(40859, 0) -- File: New project tab
  end
  local blank = api.EnumProjects(-1, '')
  local before = projects(api)
  api.Main_openProject(path)
  local opened, opened_path = api.EnumProjects(-1, '')
  local reused
  for _, entry in ipairs(before) do
    if entry.project == opened and opened ~= blank then reused = true end
  end
  if not opened or opened_path ~= path or reused then
    return nil, 'Could not open project: '..path
  end
  return opened
end

function M.load(setlist, api)
  api = api or reaper
  for i, song in ipairs(setlist.songs) do
    if not api.file_exists(song.path) then
      return nil, 'Song '..i..' is missing. Relink it before loading tabs.', 'missing_song'
    end
  end
  local pad_path = setlist.pad_project
  local pad_warning
  if not pad_path then pad_warning = 'No pad project selected.'
  elseif not api.file_exists(pad_path) then
    pad_warning = 'Pad project is missing: '..pad_path
    pad_path = nil
  end

  local previous = projects(api)
  local dirty_paths = {}
  for _, entry in ipairs(previous) do
    if entry.path ~= '' and api.IsProjectDirty(entry.project) ~= 0 then
      local key = entry.path:gsub('\\', '/'):lower()
      if dirty_paths[key] then
        return nil, 'Two unsaved tabs use the same song file. Save one under a different filename before loading.'
      end
      dirty_paths[key] = true
    end
  end
  -- Resolve every unsaved project before closing any tab. Cancel keeps the
  -- entire prior session open, including edits in other project tabs.
  for _, entry in ipairs(previous) do
    if api.IsProjectDirty(entry.project) ~= 0 then
      local answer = api.ShowMessageBox(
        'Save changes to '..(entry.path ~= '' and entry.path or 'Untitled project')..
        ' before loading this setlist?', 'AutoTiazinha Live', 1)
      if answer ~= 1 then return nil, 'Setlist load canceled.' end
      api.Main_SaveProject(entry.project, false)
      if api.IsProjectDirty(entry.project) ~= 0 then
        return nil, 'Setlist load canceled; a project was not saved.'
      end
    end
  end

  for i = #previous, 1, -1 do
    local entry = previous[i]
    if not (#previous == 1 and entry.path == '' and api.IsProjectDirty(entry.project) == 0) then
      api.SelectProjectInstance(entry.project)
      api.Main_OnCommand(40860, 0) -- File: Close project tab (normal REAPER path)
      local after = projects(api)
      local still_open
      for _, candidate in ipairs(after) do
        if candidate.project == entry.project and
            not (#after == 1 and candidate.path == '' and entry.path ~= '') then
          still_open = true
        end
      end
      if still_open then return nil, 'Setlist load canceled while closing a project tab.' end
    end
  end

  local tabs = {entries={}, pad_project=nil, pad_warning=pad_warning}
  for i, song in ipairs(setlist.songs) do
    local project, err = open_tab(api, song.path)
    if not project then return nil, err end
    tabs.entries[i] = {occurrence=song, project=project}
  end
  if pad_path then
    local project, err = open_tab(api, pad_path)
    if not project then return nil, err end
    tabs.pad_project = project
  end
  if tabs.entries[1] then api.SelectProjectInstance(tabs.entries[1].project) end
  return tabs
end

function M.is_open(tabs, api)
  api = api or reaper
  for _, entry in ipairs(tabs.entries) do
    if not contains(api, entry.project) then return false end
  end
  return not tabs.pad_project or contains(api, tabs.pad_project)
end

function M.select(tabs, index, api)
  api = api or reaper
  local entry = tabs.entries[index]
  if not entry or not contains(api, entry.project) then return false end
  api.SelectProjectInstance(entry.project)
  return true
end

return M
