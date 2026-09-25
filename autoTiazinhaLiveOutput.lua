-- Per-computer output choices and reversible project hardware routing.
local M={}
local SECTION='AutoTiazinhaLiveOutput'

function M.load(api)
  api=api or reaper
  local click=tonumber(api.GetExtState(SECTION,'click'))
  local music=tonumber(api.GetExtState(SECTION,'music'))
  return {
    click=click and click>=0 and click%1==0 and click or 0,
    music=music and music>=0 and music%1==0 and music or 1,
    stereo=api.GetExtState(SECTION,'stereo')=='1',
  }
end

function M.save(profile,api)
  api=api or reaper
  api.SetExtState(SECTION,'click',tostring(profile.click),true)
  api.SetExtState(SECTION,'music',tostring(profile.music),true)
  api.SetExtState(SECTION,'stereo',profile.stereo and '1' or '0',true)
end

function M.effective(profile)
  return {click=profile.click,music=profile.music,stereo=profile.stereo}
end

function M.validate(profile,api)
  api=api or reaper
  local outputs=api.GetNumAudioOutputs()
  if outputs<2 then return false,'Configure an audio device with at least two outputs in REAPER.' end
  local route=M.effective(profile)
  if type(route.click)~='number' or route.click%1~=0 or route.click<0 or route.click>=outputs then
    return false,'Choose an available Click/Cues output.'
  end
  if type(route.music)~='number' or route.music%1~=0 or route.music<0 or
      route.music+(route.stereo and 1 or 0)>=outputs then
    return false,'Choose an available Music output.'
  end
  if route.stereo and route.music%2~=0 then
    return false,'Choose a stereo pair starting on an odd-numbered output.'
  end
  if route.click==route.music or route.stereo and route.click==route.music+1 then
    return false,'Click/Cues and Music must use separate outputs.'
  end
  return true
end

function M.channel_label(index,api)
  api=api or reaper
  local name=api.GetOutputChannelName(index)
  local out='Out '..string.format('%d',index+1)
  return name and name~='' and name..' ('..out..')' or out
end

function M.pair_label(index,api)
  api=api or reaper
  local first=api.GetOutputChannelName(index)
  local second=api.GetOutputChannelName(index+1)
  local pair='Outs '..string.format('%d/%d',index+1,index+2)
  if first and first~='' and second and second~='' then
    return first..' / '..second..' ('..pair..')'
  end
  return pair
end

local function project_is_open(project,api)
  local index=0
  while true do
    local current=api.EnumProjects(index,'')
    if not current then return false end
    if current==project then return true end
    index=index+1
  end
end

local function tracks_for(project,api)
  local tracks={api.GetMasterTrack(project)}
  for i=0,api.CountTracks(project)-1 do
    tracks[#tracks+1]=api.GetTrack(project,i)
  end
  return tracks
end

local function snapshot_track(track,is_master,api)
  local saved={track=track,is_master=is_master,hardware={}}
  if not is_master then saved.main=api.GetMediaTrackInfo_Value(track,'B_MAINSEND') end
  for i=0,api.GetTrackNumSends(track,1)-1 do
    saved.hardware[#saved.hardware+1]={
      mute=api.GetTrackSendInfo_Value(track,1,i,'B_MUTE'),
      automode=api.GetTrackSendInfo_Value(track,1,i,'I_AUTOMODE'),
    }
  end
  return saved
end

local function set_send(track,index,key,value,api)
  assert(api.SetTrackSendInfo_Value(track,1,index,key,value),
    'Could not set project hardware output '..key..'.')
end

local function set_main(track,value,api)
  assert(api.SetMediaTrackInfo_Value(track,'B_MAINSEND',value),
    'Could not set a track master send.')
end

local function create_output(saved,channel,mono,api)
  local index=api.CreateTrackSend(saved.track,nil)
  assert(index and index>=0,'Could not create a hardware output.')
  saved.created=index
  set_send(saved.track,index,'I_SRCCHAN',0,api)
  set_send(saved.track,index,'I_DSTCHAN',channel+(mono and 1024 or 0),api)
  set_send(saved.track,index,'I_SENDMODE',0,api)
  set_send(saved.track,index,'D_VOL',1,api)
  set_send(saved.track,index,'B_MUTE',0,api)
end

local function apply_track(saved,kind,route,api)
  local track=saved.track
  for i=0,#saved.hardware-1 do
    set_send(track,i,'I_AUTOMODE',0,api)
    set_send(track,i,'B_MUTE',1,api)
  end
  if saved.is_master then
    create_output(saved,route.music,not route.stereo,api)
    return
  end
  local _,name=api.GetSetMediaTrackInfo_String(track,'P_NAME','',false)
  if kind=='song' and (name=='Click' or name=='Cues') then
    set_main(track,0,api)
    create_output(saved,route.click,true,api)
  elseif saved.main==0 and #saved.hardware>0 and api.GetTrackNumSends(track,0)==0 then
    -- A track that only reached hardware directly must join the Music mix.
    set_main(track,1,api)
  end
end

local function restore_track(saved,api)
  local track=saved.track
  if saved.created then
    assert(api.RemoveTrackSend(track,1,saved.created),'Could not remove a temporary hardware output.')
  end
  for i,hardware in ipairs(saved.hardware) do
    set_send(track,i-1,'B_MUTE',hardware.mute,api)
    set_send(track,i-1,'I_AUTOMODE',hardware.automode,api)
  end
  if not saved.is_master then set_main(track,saved.main,api) end
end

function M.new(api)
  api=api or reaper
  local manager={snapshots={},hold_projects={}}

  function manager:restore(project,force_save)
    local saved=self.snapshots[project]
    if not saved then return true end
    if not project_is_open(project,api) then self.snapshots[project]=nil; return true end
    local saved_while_routed=force_save or
      saved.seen_dirty~=0 and api.IsProjectDirty(project)==0
    local unchanged=saved.dirty==0 and
      api.GetProjectStateChangeCount(project)==saved.applied_state
    local present={}
    for _,track in ipairs(tracks_for(project,api)) do present[track]=true end
    local ok,err=pcall(function()
      for i=#saved.tracks,1,-1 do
        if present[saved.tracks[i].track] then restore_track(saved.tracks[i],api) end
      end
    end)
    if not ok then return false,err end
    self.snapshots[project]=nil
    if saved_while_routed or unchanged and api.IsProjectDirty(project)~=0 then
      -- Routing alone made a previously clean project dirty. Save only after
      -- its original routing is back. A direct REAPER save of a routed tab is
      -- repaired here as well, preserving any other edits in that save.
      api.Main_SaveProject(project,false)
    end
    return true
  end

  function manager:restore_all()
    local projects={}
    for project in pairs(self.snapshots) do projects[#projects+1]=project end
    for _,project in ipairs(projects) do
      local ok,err=self:restore(project)
      if not ok then return false,err end
    end
    self.hold_projects={}
    return true
  end

  function manager:apply(project,kind,profile)
    local valid,warning=M.validate(profile,api)
    if not valid then return false,warning end
    local restored,restore_error=self:restore(project)
    if not restored then return false,restore_error end
    if not project_is_open(project,api) then return false,'Project tab is no longer open.' end
    local saved={dirty=api.IsProjectDirty(project),tracks={},kind=kind,profile=profile}
    for i,track in ipairs(tracks_for(project,api)) do
      saved.tracks[i]=snapshot_track(track,i==1,api)
    end
    self.snapshots[project]=saved
    local route=M.effective(profile)
    local ok,err=pcall(function()
      for _,track in ipairs(saved.tracks) do apply_track(track,kind,route,api) end
    end)
    if not ok then self:restore(project); return false,err end
    api.MarkProjectDirty(project)
    saved.applied_state=api.GetProjectStateChangeCount(project)
    saved.seen_dirty=api.IsProjectDirty(project)
    if self.hold_projects[project] then
      local held,hold_error=self:set_hold_audio(project,true)
      if not held then return false,hold_error end
    end
    return true
  end

  function manager:watch_saves(before_repair,after_repair)
    local projects={}
    for project in pairs(self.snapshots) do projects[#projects+1]=project end
    for _,project in ipairs(projects) do
      local saved=self.snapshots[project]
      if project_is_open(project,api) and saved.seen_dirty~=0 and
          api.IsProjectDirty(project)==0 then
        if before_repair then before_repair(project) end
        local ok,err=self:restore(project,true)
        if not ok then return false,err end
        ok,err=self:apply(project,saved.kind,saved.profile)
        if not ok then return false,err end
        if after_repair then after_repair(project) end
      end
    end
    return true
  end

  function manager:set_music_gain(project,gain)
    local saved=self.snapshots[project]
    local master=saved and saved.tracks[1]
    if not master or master.created==nil then
      return false,'The temporary Music output is unavailable.'
    end
    return api.SetTrackSendInfo_Value(master.track,1,master.created,'D_VOL',gain),
      'Could not change the temporary Music output gain.'
  end

  function manager:set_hold_audio(project,holding)
    local saved=self.snapshots[project]
    local master=saved and saved.tracks[1]
    local click,cues
    for _,entry in ipairs(saved and saved.tracks or {}) do
      if not entry.is_master then
        local _,name=api.GetSetMediaTrackInfo_String(entry.track,'P_NAME','',false)
        if name=='Click' then click=entry end
        if name=='Cues' then cues=entry end
      end
    end
    if not master or master.created==nil or not click or click.created==nil or
        not cues or cues.created==nil then
      return false,'Hold needs an active output profile and Click/Cues tracks.'
    end
    local gain=holding and 0 or 1
    if not api.SetTrackSendInfo_Value(cues.track,1,cues.created,'D_VOL',gain) then
      return false,'Could not set click-only Hold output.'
    end
    if not api.SetTrackSendInfo_Value(master.track,1,master.created,'D_VOL',gain) then
      api.SetTrackSendInfo_Value(cues.track,1,cues.created,'D_VOL',1)
      return false,'Could not set click-only Hold output.'
    end
    self.hold_projects[project]=holding or nil
    return true
  end

  function manager:apply_tabs(tabs,profile)
    local valid,warning=M.validate(profile,api)
    if not valid then return false,warning end
    if not tabs then return true end
    for _,entry in ipairs(tabs.entries) do
      local ok,err=self:apply(entry.project,'song',profile)
      if not ok then self:restore_all(); return false,err end
    end
    if tabs.pad_project then
      local ok,err=self:apply(tabs.pad_project,'pad',profile)
      if not ok then self:restore_all(); return false,err end
    end
    return true
  end

  return manager
end

return M
