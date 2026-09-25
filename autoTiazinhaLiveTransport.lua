-- Project-scoped Live transport. Practice gain uses the temporary Music output.
local M={}
local END_MARKER='AutoTiazinha End'

local function open_projects(api)
  local projects={}
  local index=0
  while true do
    local project=api.EnumProjects(index,'')
    if not project then return projects end
    projects[project]=true
    index=index+1
  end
end

local function rewind_position(api,project,paused_at)
  local beat,measure=api.TimeMap2_timeToBeats(project,paused_at)
  if measure==0 then return 0,api.TimeMap2_beatsToTime(project,0,1) end
  local previous_start=api.TimeMap2_beatsToTime(project,0,measure-1)
  local _,_,previous_length=api.TimeMap2_timeToBeats(project,previous_start)
  local start=api.TimeMap2_beatsToTime(project,
    math.min(beat,previous_length-0.001),measure-1)
  return math.max(0,start),paused_at
end

local function song_markers(api,project)
  local ending,action_marker
  for index=0,api.GetNumRegionsOrMarkers(project)-1 do
    local found,is_region,position,_,name=api.EnumProjectMarkers3(project,index)
    if found>0 and not is_region then
      if name==END_MARKER then ending=position end
      if name:sub(1,1)=='!' then action_marker=true end
    end
  end
  return ending,action_marker
end

function M.new(api,routing)
  local controller={tabs=nil,selected=1,fade=nil,hold=nil,song_info={},pending_measure=nil,
    marker_warning=''}

  function controller:clear_fade()
    if self.fade then
      routing:set_music_gain(self.fade.project,1)
      self.fade=nil
    end
  end

  function controller:clear_hold()
    local hold=self.hold
    if not hold then return end
    self.hold=nil
    if not open_projects(api)[hold.project] then return end
    routing:set_hold_audio(hold.project,false)
    api.GetSetRepeatEx(hold.project,hold.repeat_state)
    api.GetSet_LoopTimeRange2(hold.project,true,true,
      hold.loop_start,hold.loop_end,false)
  end

  function controller:suspend_hold_loop(project)
    local hold=self.hold
    if hold and hold.project==project then
      api.GetSetRepeatEx(project,hold.repeat_state)
      api.GetSet_LoopTimeRange2(project,true,true,
        hold.loop_start,hold.loop_end,false)
    end
  end

  function controller:resume_hold_loop(project)
    local hold=self.hold
    if hold and hold.project==project then
      api.GetSet_LoopTimeRange2(project,true,true,
        hold.start,hold.ending,false)
      api.GetSetRepeatEx(project,1)
    end
  end

  function controller:refresh_markers()
    self.song_info={}
    local action,missing={},{}
    for index,entry in ipairs(self.tabs and self.tabs.entries or {}) do
      local ending,has_action=song_markers(api,entry.project)
      self.song_info[index]={project=entry.project,ending=ending,fired=false}
      if has_action then action[#action+1]=index end
      if not ending then missing[#missing+1]=index end
    end
    local warnings={}
    if #action>0 then
      warnings[#warnings+1]='SWS ! markers in songs '..table.concat(action,', ')..
        ' may change tabs or stop playback if SWS marker actions are enabled.'..
        ' Rebuild those songs in the Song Editor.'
    end
    if #missing>0 then
      warnings[#warnings+1]='No AutoTiazinha End marker in songs '..table.concat(missing,', ')..
        '; rebuild them to enable Live end detection.'
    end
    self.marker_warning=table.concat(warnings,' ')
    return self.marker_warning
  end

  function controller:set_tabs(tabs)
    self:clear_hold()
    self:clear_fade()
    self.tabs=tabs
    self.selected=1
    self.pending_measure=nil
    return self:refresh_markers()
  end

  function controller:state()
    local entry=self.tabs and self.tabs.entries[self.selected]
    return entry and open_projects(api)[entry.project] and
      api.GetPlayStateEx(entry.project) or 0
  end

  function controller:has_active_song()
    if not self.tabs then return false end
    local projects=open_projects(api)
    for _,entry in ipairs(self.tabs.entries) do
      if projects[entry.project] and api.GetPlayStateEx(entry.project)&3~=0 then
        return true
      end
    end
    return false
  end

  function controller:has_active_tab()
    if self:has_active_song() then return true end
    local pad=self.tabs and self.tabs.pad_project
    return pad and open_projects(api)[pad] and api.GetPlayStateEx(pad)&3~=0 or false
  end

  function controller:sync_selected()
    if not self.tabs or self:has_active_song() then return end
    local active=api.EnumProjects(-1,'')
    for index,entry in ipairs(self.tabs.entries) do
      if entry.project==active then self.selected=index; return end
    end
  end

  function controller:select(index)
    if not self.tabs or not self.tabs.entries[index] then
      return false,'No song tab is loaded at that position.'
    end
    if self:has_active_song() then
      return false,'Full Stop before selecting another song.'
    end
    local project=self.tabs.entries[index].project
    if not open_projects(api)[project] then
      return false,'Song tab is no longer open. Reload tabs.'
    end
    api.SelectProjectInstance(project)
    self.selected=index
    return true
  end

  function controller:next_measure_boundary()
    local entry=self.tabs and self.tabs.entries[self.selected]
    if not entry or not open_projects(api)[entry.project] or
        api.GetPlayStateEx(entry.project)&1==0 then
      return nil,'Play a song before scheduling a measure boundary.'
    end
    local project=entry.project
    local position=api.GetPlayPositionEx(project)
    local _,measure=api.TimeMap2_timeToBeats(project,position)
    local boundary=api.TimeMap2_beatsToTime(project,0,measure+1)
    if boundary<=position+0.000001 then
      boundary=api.TimeMap2_beatsToTime(project,0,measure+2)
    end
    return boundary
  end

  function controller:schedule_next_measure(action)
    assert(type(action)=='function','A measure-boundary action is required.')
    local boundary,err=self:next_measure_boundary()
    if not boundary then return false,err end
    local entry=self.tabs.entries[self.selected]
    self.pending_measure={project=entry.project,index=self.selected,
      boundary=boundary,action=action}
    return true,boundary
  end

  function controller:cancel_scheduled_measure()
    self.pending_measure=nil
  end

  function controller:play_pause()
    local entry=self.tabs and self.tabs.entries[self.selected]
    if not entry then return false,'Load a song tab before playing.' end
    local project=entry.project
    if not open_projects(api)[project] then
      return false,'Song tab is no longer open. Reload tabs.'
    end
    local state=api.GetPlayStateEx(project)
    if state&4~=0 then return false,'Stop recording before using Live transport.' end
    if self.hold and self.hold.project==project then
      api.OnPauseButtonEx(project)
      return true,state&1~=0 and 'Paused Hold on song '..self.selected..'.' or
        'Resumed Hold on song '..self.selected..'.'
    end
    if state&1~=0 then
      self:clear_fade()
      api.OnPauseButtonEx(project)
      return true,'Paused song '..self.selected..'.'
    end
    if self:has_active_song() and state&2==0 then
      return false,'Full Stop before playing another song.'
    end
    api.SelectProjectInstance(project)
    if state&2~=0 then
      local paused_at=api.GetPlayPositionEx(project)
      local start,finish=rewind_position(api,project,paused_at)
      local gained,err=routing:set_music_gain(project,0)
      if not gained then return false,'Practice resume unavailable: '..err end
      api.OnStopButtonEx(project)
      api.SetEditCurPos2(project,start,false,false)
      self.fade={project=project,start=start,finish=finish}
      api.OnPlayButtonEx(project)
      return true,'Resumed song '..self.selected..' with a one-measure lead-in.'
    end
    self:clear_fade()
    self.pending_measure=nil
    local info=self.song_info[self.selected]
    if info then info.fired=false; info.last_position=nil end
    api.SetEditCurPos2(project,0,false,false)
    api.OnPlayButtonEx(project)
    return true,'Playing song '..self.selected..'.'
  end

  function controller:full_stop()
    self:clear_fade()
    self.pending_measure=nil
    if self.hold and open_projects(api)[self.hold.project] and
        api.GetPlayStateEx(self.hold.project)&3~=0 then
      api.OnStopButtonEx(self.hold.project)
    end
    self:clear_hold()
    for _,info in ipairs(self.song_info) do
      info.fired=false
      info.last_position=nil
    end
    local projects=open_projects(api)
    for project in pairs(projects) do
      if api.GetPlayStateEx(project)&3~=0 then api.OnStopButtonEx(project) end
    end
    local entry=self.tabs and self.tabs.entries[self.selected]
    if entry and projects[entry.project] then
      api.SelectProjectInstance(entry.project)
      api.SetEditCurPos2(entry.project,0,false,false)
    end
    return true,'Stopped all tabs. Selected song reset to count-in.'
  end

  function controller:handle_song_end(event)
    if event.kind~='song_end' or not self.tabs or
        not self.tabs.entries[event.index] or
        self.tabs.entries[event.index].project~=event.project then
      return false,'The song-end event no longer matches a loaded tab.',{}
    end
    local index,project=event.index,event.project
    local next_entry=self.tabs.entries[index+1]
    local mode=next_entry and self.tabs.entries[index].occurrence.transition or 'stop'
    self:clear_fade()
    self.pending_measure=nil
    self.selected=index
    local requests={}
    local function request(action,extra)
      local item={kind='pad_request',action=action,song_index=index,
        at_song_time=event.position}
      if extra then for key,value in pairs(extra) do item[key]=value end end
      requests[#requests+1]=item
    end
    if mode=='hold' then
      local _,measure=api.TimeMap2_timeToBeats(project,math.max(0,event.position-0.000001))
      local start=api.TimeMap2_beatsToTime(project,0,measure)
      local held,err
      if start<event.position then held,err=routing:set_hold_audio(project,true) end
      if held then
        local loop_start,loop_end=api.GetSet_LoopTimeRange2(project,false,true,0,0,false)
        self.hold={project=project,start=start,ending=event.position,
          loop_start=loop_start,loop_end=loop_end,
          repeat_state=api.GetSetRepeatEx(project,-1)}
        api.OnStopButtonEx(project)
        api.GetSet_LoopTimeRange2(project,true,true,start,event.position,false)
        api.GetSetRepeatEx(project,1)
        api.SetEditCurPos2(project,start,false,false)
        api.SelectProjectInstance(project)
        api.OnPlayButtonEx(project)
        request('hold')
        return true,'Holding song '..index..' on its final Click measure.',requests
      end
      mode='stop'
      request('fade_out',{duration=6})
      api.OnStopButtonEx(project)
      api.SetEditCurPos2(project,0,false,false)
      return false,'Hold unavailable: '..(err or 'the final measure is empty')..' Song stopped.',requests
    end
    request('fade_out',{duration=6})
    api.OnStopButtonEx(project)
    api.SetEditCurPos2(project,0,false,false)
    if mode=='auto' or mode=='load_wait' then
      local next_project=next_entry.project
      if not open_projects(api)[next_project] then
        return false,'Next song tab is no longer open. Reload tabs.',requests
      end
      self.selected=index+1
      api.SelectProjectInstance(next_project)
      api.SetEditCurPos2(next_project,0,false,false)
      if mode=='auto' then
        local info=self.song_info[self.selected]
        if info then info.fired=false; info.last_position=nil end
        api.OnPlayButtonEx(next_project)
        request('start',{song_index=self.selected,duration=3,at_song_time=0})
        return true,'Started song '..self.selected..' automatically.',requests
      end
      return true,'Loaded song '..self.selected..' and waiting for Play.',requests
    end
    api.SelectProjectInstance(project)
    return true,'Song '..index..' stopped at its end. Play replays it.',requests
  end

  function controller:update()
    if self.hold and (not open_projects(api)[self.hold.project] or
        api.GetPlayStateEx(self.hold.project)&3==0) then
      self:clear_hold()
    end
    local fade=self.fade
    local projects=open_projects(api)
    if fade then
      if not projects[fade.project] or api.GetPlayStateEx(fade.project)&1==0 then
        self:clear_fade()
      else
        local position=api.GetPlayPositionEx(fade.project)
        local span=fade.finish-fade.start
        local gain=span>0 and math.min(1,math.max(0,(position-fade.start)/span)) or 1
        local applied=routing:set_music_gain(fade.project,gain)
        if not applied or gain>=1 then self:clear_fade() end
      end
    end
    local events={}
    local pending=self.pending_measure
    if pending then
      if not projects[pending.project] or api.GetPlayStateEx(pending.project)&3==0 then
        self.pending_measure=nil
      elseif api.GetPlayStateEx(pending.project)&1~=0 then
        local position=api.GetPlayPositionEx(pending.project)
        local info=self.song_info[pending.index]
        if info and info.ending and info.ending<pending.boundary-0.000001 and
            position>=info.ending then
          self.pending_measure=nil
        elseif position>=pending.boundary then
          self.pending_measure=nil
          local event={kind='measure_boundary',index=pending.index,
            project=pending.project,position=pending.boundary}
          pending.action(event)
          events[#events+1]=event
        end
      end
    end
    for index,info in ipairs(self.song_info) do
      local project=info.project
      if projects[project] then
        local state=api.GetPlayStateEx(project)
        if state&1~=0 then
          local position=api.GetPlayPositionEx(project)
          if info.last_position and position<info.last_position-0.01 then
            info.fired=false
          end
          if info.ending and not info.fired and position>=info.ending and
              not (self.hold and self.hold.project==project) then
            info.fired=true
            if self.pending_measure and self.pending_measure.project==project then
              self.pending_measure=nil
            end
            events[#events+1]={kind='song_end',index=index,project=project,
              position=info.ending,observed_position=position}
          end
          info.last_position=position
        elseif state&3==0 then
          info.fired=false
          info.last_position=nil
        end
      end
    end
    return events
  end

  return controller
end

return M
