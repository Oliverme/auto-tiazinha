-- Live setlist data. This module does not access REAPER or song projects.
local M = {}

M.root_notes = {'C','Db','D','Eb','E','F','Gb','G','Ab','A','Bb','B'}
local roots = {}
for _,note in ipairs(M.root_notes) do roots[note]=true end
local transitions = {stop=true, auto=true, load_wait=true, hold=true}
M.transitions = {'stop', 'auto', 'load_wait', 'hold'}

local function absolute(path)
  return path:match('^/') or path:match('^%a:[/\\]') or path:match('^[/\\][/\\]')
end

local function check_name(name)
  assert(type(name) == 'string' and name:match('%S'), 'Enter a setlist name.')
end

local function check_project(path)
  assert(type(path) == 'string' and absolute(path) and path:lower():match('%.rpp$'),
    'Choose an absolute .RPP project path.')
end

local function check_index(setlist, index)
  assert(type(index) == 'number' and index % 1 == 0 and setlist.songs[index],
    'Choose a song occurrence.')
  return setlist.songs[index]
end

local function changed(setlist, object, key, value)
  if object[key] == value then return false end
  object[key] = value
  setlist.dirty = true
  return true
end

function M.new(name)
  check_name(name)
  return {name=name, pad_project=nil, songs={}, file_path=nil, dirty=true}
end

function M.set_name(setlist, name)
  check_name(name)
  return changed(setlist, setlist, 'name', name)
end

function M.set_pad_project(setlist, path)
  if path ~= nil then check_project(path) end
  return changed(setlist, setlist, 'pad_project', path)
end

function M.add(setlist, path)
  check_project(path)
  -- Each occurrence owns its transition and override, even for repeated paths.
  -- A nil override uses the root note saved in that song's .RPP.
  local song = {path=path, transition='stop', root_override=nil}
  setlist.songs[#setlist.songs+1] = song
  setlist.dirty = true
  return song
end

function M.move(setlist, index, destination)
  check_index(setlist, index)
  check_index(setlist, destination)
  if index == destination then return false end
  table.insert(setlist.songs, destination, table.remove(setlist.songs, index))
  setlist.dirty = true
  return true
end

function M.remove(setlist, index)
  check_index(setlist, index)
  setlist.dirty = true
  return table.remove(setlist.songs, index)
end

function M.set_song_path(setlist, index, path)
  check_project(path)
  return changed(setlist, check_index(setlist, index), 'path', path)
end

function M.set_transition(setlist, index, mode)
  assert(transitions[mode], 'Choose a valid transition mode.')
  return changed(setlist, check_index(setlist, index), 'transition', mode)
end

function M.set_root_override(setlist, index, root)
  assert(root == nil or roots[root], 'Choose a valid root note.')
  return changed(setlist, check_index(setlist, index), 'root_override', root)
end

local function quote(value)
  return '"' .. value:gsub('[%z\1-\31\\"]', function(c)
    local escapes = {['"']='\\"', ['\\']='\\\\', ['\b']='\\b', ['\f']='\\f',
      ['\n']='\\n', ['\r']='\\r', ['\t']='\\t'}
    return escapes[c] or string.format('\\u%04x', c:byte())
  end) .. '"'
end

-- A small JSON reader keeps setlists usable in REAPER without an extension.
local json_null = {}
local function decode(source)
  local pos = 1
  local function fail() error('Invalid setlist JSON at byte ' .. pos, 0) end
  local function space()
    local _, finish = source:find('^[ \t\r\n]*', pos)
    pos = (finish or pos-1) + 1
  end
  local function string_value()
    if source:sub(pos,pos) ~= '"' then fail() end
    pos = pos + 1
    local parts = {}
    while pos <= #source do
      local c = source:sub(pos,pos)
      if c == '"' then pos = pos+1; return table.concat(parts) end
      if c == '\\' then
        local escape = source:sub(pos+1,pos+1)
        local simple = {['"']='"', ['\\']='\\', ['/']='/', b='\b', f='\f', n='\n', r='\r', t='\t'}
        if simple[escape] then
          parts[#parts+1] = simple[escape]; pos = pos+2
        elseif escape == 'u' then
          local hex = source:sub(pos+2,pos+5)
          if not hex:match('^%x%x%x%x$') then fail() end
          local code = tonumber(hex,16)
          pos = pos+6
          if code >= 0xD800 and code <= 0xDBFF then
            if source:sub(pos,pos+1) ~= '\\u' then fail() end
            local low = source:sub(pos+2,pos+5)
            if not low:match('^%x%x%x%x$') then fail() end
            low = tonumber(low,16)
            if low < 0xDC00 or low > 0xDFFF then fail() end
            code = 0x10000 + (code-0xD800)*1024 + low-0xDC00
            pos = pos+6
          elseif code >= 0xDC00 and code <= 0xDFFF then fail() end
          parts[#parts+1] = utf8.char(code)
        else fail() end
      else
        if c:byte() < 32 then fail() end
        parts[#parts+1] = c; pos = pos+1
      end
    end
    fail()
  end
  local parse
  parse = function()
    space()
    local c = source:sub(pos,pos)
    if c == '"' then return string_value() end
    if c == '{' then
      local object = {}; pos = pos+1; space()
      if source:sub(pos,pos) == '}' then pos = pos+1; return object end
      while true do
        space(); local key = string_value(); space()
        if source:sub(pos,pos) ~= ':' or object[key] ~= nil then fail() end
        pos = pos+1; object[key] = parse(); space()
        local separator = source:sub(pos,pos); pos = pos+1
        if separator == '}' then return object end
        if separator ~= ',' then fail() end
      end
    end
    if c == '[' then
      local array = setmetatable({}, {__json_array=true}); pos = pos+1; space()
      if source:sub(pos,pos) == ']' then pos = pos+1; return array end
      while true do
        array[#array+1] = parse(); space()
        local separator = source:sub(pos,pos); pos = pos+1
        if separator == ']' then return array end
        if separator ~= ',' then fail() end
      end
    end
    if source:sub(pos,pos+3) == 'null' then pos = pos+4; return json_null end
    if source:sub(pos,pos+3) == 'true' then pos = pos+4; return true end
    if source:sub(pos,pos+4) == 'false' then pos = pos+5; return false end
    local number = source:sub(pos):match('^-?%d+%.?%d*[eE]?[+-]?%d*')
    if number and tonumber(number) then pos = pos+#number; return tonumber(number) end
    fail()
  end
  local value = parse(); space()
  if pos <= #source then fail() end
  return value
end

local function slash(path) return path:gsub('\\', '/') end
local function parts(path)
  path = slash(path)
  local prefix, rest = path:match('^(%a:)(/.*)$')
  if not prefix then
    if path:sub(1,2) == '//' then
      local server, share, tail = path:match('^//([^/]+)/([^/]+)(.*)$')
      if not server then return nil end
      prefix, rest = '//'..server..'/'..share, tail
    elseif path:sub(1,1) == '/' then prefix, rest = '/', path
    else prefix, rest = '', path end
  end
  local items = {}
  for item in rest:gmatch('[^/]+') do
    if item == '..' and #items > 0 and items[#items] ~= '..' then
      items[#items] = nil
    elseif item == '..' and prefix == '' then items[#items+1] = item
    elseif item ~= '.' and item ~= '..' then items[#items+1] = item end
  end
  return prefix, items
end
local function join(prefix, items)
  if prefix == '/' then return '/' .. table.concat(items, '/') end
  if prefix == '' then return table.concat(items, '/') end
  return prefix .. '/' .. table.concat(items, '/')
end
local function directory(path)
  local prefix, items = parts(path)
  items[#items] = nil
  return prefix, items
end
local function stored_path(path, file_path)
  local base, folders = directory(file_path)
  local prefix, target = parts(path)
  if prefix == '' then return slash(path) end
  if prefix:lower() ~= base:lower() then return slash(path) end
  local common = 0
  while folders[common+1] and folders[common+1] == target[common+1] do common = common+1 end
  local relative = {}
  for _ = common+1, #folders do relative[#relative+1] = '..' end
  for i = common+1, #target do relative[#relative+1] = target[i] end
  return table.concat(relative, '/')
end
local function resolved_path(path, file_path)
  if absolute(path) then local prefix, items = parts(path); return join(prefix, items) end
  local prefix, items = directory(file_path)
  for item in slash(path):gmatch('[^/]+') do
    if item == '..' then items[#items] = nil
    elseif item ~= '.' then items[#items+1] = item end
  end
  return join(prefix, items)
end

local function validate(setlist)
  check_name(setlist.name)
  if setlist.pad_project ~= nil then check_project(setlist.pad_project) end
  assert(type(setlist.songs) == 'table', 'Invalid song list.')
  for _, song in ipairs(setlist.songs) do
    check_project(song.path)
    assert(transitions[song.transition], 'Invalid transition mode.')
    assert(song.root_override == nil or roots[song.root_override], 'Invalid root note override.')
  end
end

function M.save(setlist, file_path)
  file_path = file_path or setlist.file_path
  assert(type(file_path) == 'string' and absolute(file_path) and file_path:lower():match('%.json$'),
    'Choose an absolute .json setlist path.')
  validate(setlist)
  local lines = {'{', '  "version": 1,', '  "name": '..quote(setlist.name)..',',
    '  "pad_project": '..(setlist.pad_project and quote(stored_path(setlist.pad_project,file_path)) or 'null')..',',
    '  "songs": ['}
  for i, song in ipairs(setlist.songs) do
    lines[#lines+1] = '    {"path": '..quote(stored_path(song.path,file_path))..
      ', "transition": '..quote(song.transition)..
      ', "root_override": '..(song.root_override and quote(song.root_override) or 'null')..'}'..
      (i < #setlist.songs and ',' or '')
  end
  lines[#lines+1] = '  ]'
  lines[#lines+1] = '}'
  local file, err = io.open(file_path, 'wb')
  if not file then return nil, err end
  local ok, write_err = file:write(table.concat(lines, '\n')..'\n')
  local close_ok, close_err = file:close()
  if not ok or not close_ok then return nil, write_err or close_err end
  setlist.file_path, setlist.dirty = file_path, false
  return true
end

function M.load(file_path)
  assert(type(file_path) == 'string' and absolute(file_path), 'Choose an absolute setlist path.')
  local file, err = io.open(file_path, 'rb')
  if not file then return nil, err end
  local source = file:read('*a'); file:close()
  local ok, data = pcall(decode, source)
  if not ok then return nil, data end
  if type(data) ~= 'table' or data.version ~= 1 or type(data.songs) ~= 'table' or
      not getmetatable(data.songs) or not getmetatable(data.songs).__json_array then
    return nil, 'Unsupported or invalid setlist file.'
  end
  local valid, result = pcall(function()
    local setlist = M.new(data.name)
    if data.pad_project ~= json_null and data.pad_project ~= nil then
      assert(type(data.pad_project) == 'string', 'Invalid pad project path.')
      setlist.pad_project = resolved_path(data.pad_project, file_path)
      check_project(setlist.pad_project)
    end
    for _, song in ipairs(data.songs) do
      assert(type(song) == 'table', 'Invalid song occurrence.')
      assert(type(song.path) == 'string', 'Invalid song path.')
      local occurrence = M.add(setlist, resolved_path(song.path, file_path))
      assert(transitions[song.transition], 'Invalid transition mode.')
      occurrence.transition = song.transition
      if song.root_override ~= json_null and song.root_override ~= nil then
        assert(roots[song.root_override], 'Invalid root note override.')
        occurrence.root_override = song.root_override
      end
    end
    setlist.file_path, setlist.dirty = file_path, false
    return setlist
  end)
  if not valid then return nil, result end
  return result
end

function M.discard(setlist)
  assert(setlist.file_path, 'This setlist has not been saved.')
  return M.load(setlist.file_path)
end

return M
