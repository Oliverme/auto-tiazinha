-- Mocked REAPER builder regression test (4/4 timing in test units).
local root = (arg[1] or '.') .. '/'
local function encode(value)
  if type(value) ~= 'table' then return tostring(value) end
  if value.id then return 'track:' .. value.id end
  local keys, out = {}, {}
  for key in pairs(value) do keys[#keys+1] = key end
  table.sort(keys, function(a,b) return tostring(a)<tostring(b) end)
  for _,key in ipairs(keys) do out[#out+1] = tostring(key)..'='..encode(value[key]) end
  return '{'..table.concat(out, ',')..'}'
end
local function run(file, opts)
  opts = opts or {}
  local state = {cross=opts.cross or 0, tracks={}, events={}, callbacks={}, selected=nil, saves=0, markers={}, media={}, cursor=0}
  local api = {}
  local function event(name,...)
    state.events[#state.events+1] = name..encode({...})
  end
  api.GetToggleCommandState = function(id) return id == 40041 and state.cross or 0 end
  api.Main_OnCommand = function(id, flag)
    if id == 40041 then state.cross = 1-state.cross; return end
    event('command', id, flag)
    if id == 40013 then table.insert(state.selected.items, {chunk='SAMPLES "" "" "" ""\nVOL 1 1\n'}) end
  end
  api.atexit = function(fn) state.callbacks[#state.callbacks+1]=fn end
  api.GetProjExtState = function(_, _, key)
    local value = opts.saved and opts.saved[key]
    return value and 1 or 0, value or ''
  end
  api.GetUserInputs = function(...)
    event('dialog',...)
    return not opts.cancel, opts.input or 'Song Name,120,4,4,EN,false,Intro:4|Verse:8|Chorus:8|Ending:4,,'
  end
  api.GetProjectName = function() return opts.project or 'Song Name.RPP' end
  api.GetProjectPath = function() return '/tmp/projects' end
  api.Main_SaveProjectEx = function(...) event('saveas', ...) end
  api.Main_SaveProject = function(...) state.saves=state.saves+1; event('save',...) end
  api.SetProjExtState = function(...) event('settings',...) end
  api.GetNumRegionsOrMarkers = function() return 2 end
  api.DeleteProjectMarkerByIndex = function(...) event('delete_marker',...) end
  api.CountTempoTimeSigMarkers = function() return 1 end
  api.DeleteTempoTimeSigMarker = function(...) event('delete_tempo',...) end
  api.UpdateTimeline = function() event('timeline') end
  api.SetTempoTimeSigMarker = function(...) event('tempo',...) end
  api.TimeMap_GetMetronomePattern = function(...) event('pattern',...) end
  api.CountTracks = function() return #state.tracks end
  api.GetTrack = function(_,i) return state.tracks[i+1] end
  api.InsertTrackInProject = function(_,i)
    local t={id=i+1, items={}}
    table.insert(state.tracks,i+1,t); event('track',t)
  end
  api.GetSetMediaTrackInfo_String = function(track,key,value,set)
    if set then track[key]=value; event('track_property',track,key,value) end
    return true,track[key] or ''
  end
  api.CountTrackMediaItems = function(track) return #track.items end
  api.GetTrackMediaItem = function(track,i) return track.items[i+1] end
  api.DeleteTrackMediaItem = function(track,item)
    for i,v in ipairs(track.items) do if v==item then table.remove(track.items,i); event('delete_item',track,i); return true end end
    error('wrong-track item')
  end
  api.SetOnlyTrackSelected = function(track) state.selected=track; event('select',track) end
  api.parse_timestr_pos = function(str)
    local m,b=str:match('^(%d+)%.(%d+)%.00$'); assert(m,str)
    return (tonumber(m)-1)*4+tonumber(b)-1
  end
  api.format_timestr_pos = function(t) return string.format('%d.%d.00',math.floor(t/4)+1,t%4+1) end
  api.AddRegionOrMarker = function(_,region,start,finish,name) state.markers[#state.markers+1]={region=region,start=start,finish=finish,name=name} end
  api.SetEditCurPos = function(position) state.cursor=position end
  api.InsertMedia = function(path,flag)
    if opts.fail then error('simulated media failure') end
    table.insert(state.selected.items,{path=path})
    state.media[#state.media+1]={path=path,position=state.cursor}
  end
  api.GetSet_LoopTimeRange = function(...) event('range',...) end
  api.GetItemStateChunk = function(item) return true,item.chunk end
  api.SetItemStateChunk = function(item,chunk) item.chunk=chunk; event('chunk',chunk) end
  api.GetSetRepeat = function(...) event('repeat',...) end
  api.get_action_context = function() return 0,root..file end
  if opts.existing then
    for _,name in ipairs({'Click','Cues'}) do
      state.tracks[#state.tracks+1] = {id=#state.tracks+1,P_NAME=name,['P_EXT:xyz']='AutoTiazinha',items={{},{},{}}}
    end
  end
  local env = setmetatable({reaper=api}, {__index=_G})
  env.dofile = function(path)
    local chunk=assert(loadfile(path,'t',env))
    if setfenv then setfenv(chunk,env) end
    return chunk()
  end
  local ok,result = pcall(env.dofile,root..file)
  for _,fn in ipairs(state.callbacks) do fn() end
  assert(state.cross == (opts.cross or 0), 'crossfade not restored')
  return state,ok,result,env
end
local function build(structure)
  local state,ok,result=run('autoTiazinhaCaller.lua',{cross=1,input='Song Name,120,4,4,EN,false,'..structure..',,'})
  return state,ok,result
end
local state,ok,err=build('Intro:4|Ending:0')
assert(ok,err)
assert(#state.markers==3) -- Start, Intro region, end action marker
assert(state.markers[2].region and state.markers[2].start==16 and state.markers[2].finish==32)
local ending=state.markers[3]
assert(not ending.region and ending.start==32 and ending.name=='! 40044 40042 40861')
assert(#state.media==8)
assert(state.media[5].path:match('/EN/Ending.wav$') and state.media[5].position==28)
for i=6,8 do assert(state.media[i].position==28+i-5) end
assert(state.saves==1)
state,ok,err=build('Intro:4|Ending:4')
assert(ok,err)
assert(#state.markers==4 and state.markers[4].start==48)
state,ok=build('Intro:0|Ending:4')
assert(not ok and #state.tracks==0 and state.saves==0 and #state.markers==0)
print('PASS: builder — zero-bar ending cue timing, immediate end marker, no empty region, positive-length regression, invalid zero rejected before generation.')
