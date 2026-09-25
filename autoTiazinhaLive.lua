-- Live setlist and transport window. Pad controls arrive in later Live steps.
local dir = debug.getinfo(1, 'S').source:sub(2):match('^(.*)[/\\]') or '.'
local Setlist = dofile(dir .. '/autoTiazinhaSetlist.lua')
local Tabs = dofile(dir .. '/autoTiazinhaLiveTabs.lua')
local EditorBridge = dofile(dir .. '/autoTiazinhaLiveEditorBridge.lua')
local Output = dofile(dir .. '/autoTiazinhaLiveOutput.lua')
local Transport = dofile(dir .. '/autoTiazinhaLiveTransport.lua')

local setlist, status = nil, 'Create or open a setlist to begin.'
local tabs, tabs_stale = nil, false
local output_profile, routing = Output.load(reaper), Output.new(reaper)
local transport = Transport.new(reaper,routing)
local editor_session, editor_command = nil, nil
local buttons, mouse_was_down, closing, scroll = {}, false, false, 0
local drag_starts, drag = {}, nil
local song_keys = {}
local widest_note_key = 0
local ROW_TOP, ROW_HEIGHT = 280, 60
local C = {
  bg={0.075,0.09,0.115}, panel={0.11,0.13,0.165}, button={0.16,0.19,0.23},
  hover={0.22,0.27,0.32}, drop={0.15,0.25,0.27},
  text={0.91,0.93,0.95}, muted={0.57,0.63,0.69}, accent={0.37,0.79,0.68},
  warning={0.94,0.70,0.37},
  play={0.13,0.29,0.22}, play_hover={0.17,0.39,0.28}, play_ink={0.48,0.94,0.59},
  stop={0.30,0.17,0.18}, stop_hover={0.40,0.21,0.22}, stop_ink={1.00,0.51,0.47},
}
local transition_info = {
  stop='Stop at End', auto='Start Next',
  load_wait='Load & Wait', hold='Hold',
}
local transition_menu='Stop at End|Start Next Automatically|Load Next and Wait|Hold'
local file_filter = 'AutoTiazinha setlists|*.json|JSON files|*.json'
local song_filter = 'REAPER projects|*.RPP;*.rpp'
local state_section, state_key = 'AutoTiazinhaLive', 'last_setlist_path'
-- Persistent REAPER ext state is line-based, so escape path newlines and %.
local function decode_path(value)
  return (value or ''):gsub('%%(%x%x)',function(hex) return string.char(tonumber(hex,16)) end)
end
local last_setlist_path=decode_path(reaper.GetExtState(state_section,state_key))
local function remember_path(path)
  last_setlist_path=path
  local encoded=path:gsub('%%','%%25'):gsub('\r','%%0D'):gsub('\n','%%0A')
  reaper.SetExtState(state_section,state_key,encoded,true)
end

local function color(value) gfx.set(value[1], value[2], value[3], 1) end
local function rect(x,y,w,h,value)
  color(value); gfx.rect(x,y,w,h,1)
end
local function label(value,x,y,value_color,width,font)
  gfx.setfont(font or 1); color(value_color or C.text); gfx.x,gfx.y=x,y
  if width then gfx.drawstr(tostring(value),0,x+width,y+24)
  else gfx.drawstr(tostring(value)) end
end
local function button(title,x,y,w,action,enabled,dropdown)
  local hover=enabled and gfx.mouse_x>=x and gfx.mouse_x<x+w and
    gfx.mouse_y>=y and gfx.mouse_y<y+34
  rect(x,y,w,34,enabled and (hover and C.hover or C.button) or C.panel)
  label(title,x+11,y+8,enabled and C.text or C.muted,w-(dropdown and 40 or 22))
  if dropdown then
    color(enabled and C.text or C.muted)
    gfx.line(x+w-21,y+14,x+w-17,y+18)
    gfx.line(x+w-17,y+18,x+w-13,y+14)
  end
  if enabled then buttons[#buttons+1]={x=x,y=y,w=w,h=34,action=action} end
end

local function transport_button(title,icon,x,y,w,action,enabled,large)
  local h=large and 52 or 40
  local hover=enabled and gfx.mouse_x>=x and gfx.mouse_x<x+w and
    gfx.mouse_y>=y and gfx.mouse_y<y+h
  local fill=icon=='stop' and (hover and C.stop_hover or C.stop) or
    icon=='play' and (hover and C.play_hover or C.play) or
    (hover and C.hover or C.button)
  rect(x,y,w,h,enabled and fill or C.button)
  local ink=enabled and (icon=='stop' and C.stop_ink or
    icon=='play' and C.play_ink or icon=='pause' and C.warning or C.text) or C.muted
  local cx,cy=title and x+22 or x+w/2,y+h/2
  color(ink)
  if icon=='play' then
    local size=large and 1.5 or 1
    gfx.triangle(cx-6*size,cy-9*size,cx-6*size,cy+9*size,cx+9*size,cy)
  elseif icon=='pause' then
    local size=large and 1.5 or 1
    gfx.rect(cx-7*size,cy-8*size,5*size,16*size,1)
    gfx.rect(cx+2*size,cy-8*size,5*size,16*size,1)
  elseif icon=='stop' then
    gfx.rect(cx-8,cy-8,16,16,1)
  elseif icon=='previous' then
    gfx.rect(cx-9,cy-8,3,16,1)
    gfx.triangle(cx+7,cy-8,cx+7,cy+8,cx-5,cy)
  elseif icon=='next' then
    gfx.triangle(cx-7,cy-8,cx-7,cy+8,cx+5,cy)
    gfx.rect(cx+7,cy-8,3,16,1)
  end
  if title then label(title,x+43,y+11,enabled and C.text or C.muted,w-49) end
  if enabled then buttons[#buttons+1]={x=x,y=y,w=w,h=h,action=action} end
end

local function visible_capacity()
  return math.max(1,math.floor((gfx.h-332)/ROW_HEIGHT))
end

local function report_error(err)
  status = tostring(err)
  reaper.ShowMessageBox(status,'AutoTiazinha Live',0)
end

local function file_name(path)
  local name=path:match('[^/\\]+$') or path
  if name:lower():sub(-5)=='.json' then return name:sub(1,-6) end
  return name
end

local function song_key(path)
  if song_keys[path] ~= nil then return song_keys[path] or nil end
  local file=io.open(path,'rb')
  if not file then song_keys[path]=false; return nil end
  local depth,app_depth=0,nil
  local key
  for line in file:lines() do
    local section=line:match('^%s*<([^%s>]+)')
    if section then
      if depth==0 and section=='EXTSTATE' then depth=1
      elseif depth>0 then
        depth=depth+1
        if depth==2 and section=='AUTOTIAZINHA' then app_depth=depth end
      end
    elseif line:match('^%s*>%s*$') then
      if depth==app_depth then app_depth=nil end
      if depth>0 then depth=depth-1 end
    elseif app_depth and depth==app_depth then
      key=line:match('^%s*ROOT_NOTE%s+(%S+)%s*$') or key
    end
  end
  file:close()
  for _,note in ipairs(Setlist.root_notes) do
    if key==note then song_keys[path]=key; return key end
  end
  song_keys[path]=false
end

local function current_directory()
  local path=setlist and setlist.file_path or last_setlist_path
  if not path or path=='' then return nil end
  local folder=path:match('^(.*)[/\\]')
  return folder=='' and '/' or folder
end

local function save()
  if not setlist then return false end
  local path = setlist.file_path
  local ok, result, err = pcall(Setlist.save,setlist,path)
  if not ok or not result then report_error(ok and err or result); return false end
  remember_path(path)
  status='Saved setlist.'
  return true
end

local function can_leave()
  if editor_session then status='Close the Song Editor before leaving this setlist.'; return false end
  if not setlist or not setlist.dirty then return true end
  local answer = reaper.ShowMessageBox(
    'Save changes to "'..setlist.name..'" before leaving?',
    'AutoTiazinha Live',3)
  if answer == 6 then return save() end
  return answer == 7
end

local function open_routed_tabs(target)
  if transport:has_active_tab() then
    return nil,'Full Stop before changing project tabs.'
  end
  transport:clear_hold()
  transport:clear_fade()
  local restored, restore_error=routing:restore_all()
  if not restored then return nil,restore_error end
  local loaded,err,code=Tabs.load(target)
  if not loaded then
    if code~='missing_song' and tabs and Tabs.is_open(tabs) then
      routing:apply_tabs(tabs,output_profile)
    end
    return nil,err,code
  end
  local applied,route_warning=routing:apply_tabs(loaded,output_profile)
  return loaded,nil,nil,not applied and 'Output profile inactive: '..route_warning or nil
end

local function load_tabs(target)
  local loaded, err, code, route_warning = open_routed_tabs(target)
  if not loaded then return false, err, code end
  tabs, tabs_stale = loaded, false
  local marker_warning=transport:set_tabs(loaded)
  status = (loaded.pad_warning or 'Song project tabs loaded.')..
    (route_warning and ' '..route_warning or '')..
    (marker_warning~='' and ' '..marker_warning or '')
  return true
end

local function reload_tabs()
  if editor_session then status='Close the Song Editor before reloading tabs.'; return end
  local ok, err = load_tabs(setlist)
  if not ok then status=err end
end

local function edit_and_load(edit, message, retain_on_load_failure)
  if editor_session then status='Close the Song Editor before changing projects.'; return false end
  local candidate={}
  for key,value in pairs(setlist) do candidate[key]=value end
  candidate.songs={}
  for i,song in ipairs(setlist.songs) do
    local copied={}
    for key,value in pairs(song) do copied[key]=value end
    candidate.songs[i]=copied
  end
  local ok, changed=pcall(edit,candidate)
  if not ok then report_error(changed); return false end
  if changed==false then return false end
  local loaded, err, code, route_warning=open_routed_tabs(candidate)
  if not loaded and code~='missing_song' then
    if not retain_on_load_failure then status=err; return false end
    setlist=candidate
    tabs_stale=true
    transport:set_tabs(nil)
    status=message..' Tabs need reloading: '..err
    return true
  end
  setlist=candidate
  tabs, tabs_stale=loaded, false
  local marker_warning=transport:set_tabs(loaded)
  status=loaded and (message..(loaded.pad_warning and ' '..loaded.pad_warning or '')..
    (route_warning and ' '..route_warning or '')..
    (marker_warning~='' and ' '..marker_warning or '')) or err
  return true
end

local function project_path(project)
  local index=0
  while true do
    local current,path=reaper.EnumProjects(index,'')
    if not current then return nil end
    if current==project then return path end
    index=index+1
  end
end

local function close_unused_tab(project)
  if project_path(project)=='' and reaper.IsProjectDirty(project)==0 then
    reaper.SelectProjectInstance(project)
    reaper.Main_OnCommand(40860,0)
    if tabs and tabs.entries[1] then Tabs.select(tabs,1) end
  end
end

local function song_is_playing()
  if not tabs then return false end
  for _,entry in ipairs(tabs.entries) do
    if project_path(entry.project) and reaper.GetPlayStateEx(entry.project)&3~=0 then return true end
  end
  if tabs.pad_project and project_path(tabs.pad_project) and
      reaper.GetPlayStateEx(tabs.pad_project)&3~=0 then return true end
  return false
end

local function launch_editor(mode,index)
  if editor_session then status='The Song Editor is already open.'; return end
  if song_is_playing() then status='Stop song playback before opening the editor.'; return end
  transport:clear_hold()
  local output_directory=mode=='new' and current_directory() or nil
  if mode=='new' and not output_directory then
    status='Choose a setlist file before creating a song.'
    return
  end
  if not editor_command then
    editor_command=reaper.AddRemoveReaScript(true,0,dir..'/autoTiazinhaNativeEditor.lua',true)
    if editor_command==0 then report_error('Could not register the Song Editor action.'); return end
  end
  local temporary
  if mode=='edit' then
    if not tabs or tabs_stale or not Tabs.select(tabs,index) then
      local ok,err=load_tabs(setlist)
      if not ok then status=err; return end
      Tabs.select(tabs,index)
    end
    local restored,restore_error=routing:restore(tabs.entries[index].project)
    if not restored then status=restore_error; return end
  else
    reaper.Main_OnCommand(41929,0) -- New project tab, ignoring the default template
    temporary=reaper.EnumProjects(-1,'')
  end
  local token=EditorBridge.begin(mode,output_directory or '',reaper)
  editor_session={token=token,mode=mode,index=index,
    original_path=mode=='edit' and setlist.songs[index].path or nil,
    project=mode=='edit' and tabs.entries[index].project or nil,
    temporary=temporary,started=reaper.time_precise()}
  reaper.Main_OnCommand(editor_command,0)
  status=mode=='new' and 'Create and build the new song in the Song Editor.' or
    'Editing song '..index..' in the Song Editor.'
end

local function finish_editor(result)
  local session=editor_session
  editor_session=nil
  if session.mode=='new' then
    if not result.built or result.path=='' or not reaper.file_exists(result.path) then
      close_unused_tab(session.temporary)
      status='No new song was built.'
      return
    end
    song_keys[result.path]=nil
    edit_and_load(function(candidate) Setlist.add(candidate,result.path) end,
      'New song added to the setlist.',true)
  else
    song_keys[session.original_path]=nil
    if result.path~='' and result.path~=session.original_path then
      if not reaper.file_exists(result.path) then
        status='Edited song project was not found: '..result.path
        return
      end
      song_keys[result.path]=nil
      edit_and_load(function(candidate)
        return Setlist.set_song_path(candidate,session.index,result.path)
      end,'Song '..session.index..' updated.',true)
    else
      status=result.built and 'Song '..session.index..' updated.' or 'Song Editor closed.'
      if session.project and project_path(session.project) then
        local applied,err=routing:apply(session.project,'song',output_profile)
        if not applied then status=status..' Output profile inactive: '..err end
      end
      if tabs and Tabs.is_open(tabs) then
        local marker_warning=transport:refresh_markers()
        if marker_warning~='' then status=status..' '..marker_warning end
      end
    end
  end
end

local function poll_editor()
  if not editor_session then return end
  local result=EditorBridge.poll(editor_session.token,reaper)
  if result then finish_editor(result); return end
  if reaper.time_precise()-editor_session.started>5 and
      EditorBridge.pending(editor_session.token,reaper) then
    EditorBridge.cancel(editor_session.token,reaper)
    close_unused_tab(editor_session.temporary)
    if editor_session.project and project_path(editor_session.project) then
      routing:apply(editor_session.project,'song',output_profile)
    end
    editor_session=nil
    status='The Song Editor did not start.'
  end
end

local function new_setlist()
  if song_is_playing() then status='Full Stop before creating a setlist.'; return end
  transport:clear_hold()
  local folder=current_directory()
  local initial=folder and folder..'/New Setlist.json' or 'New Setlist.json'
  local chosen, path = reaper.GetUserFileName(0,'New AutoTiazinha setlist',initial,file_filter)
  if not chosen then return end
  if not path:lower():match('%.json$') then path=path..'.json' end
  local existing=io.open(path,'rb')
  if existing then existing:close(); report_error('A setlist with that filename already exists.'); return end
  local ok, created = pcall(Setlist.new,file_name(path))
  if not ok then report_error(created); return end
  if not can_leave() then return end
  local restored,restore_error=routing:restore_all()
  if not restored then status=restore_error; return end
  created.file_path=path
  setlist, status = created, 'New setlist. Save when ready.'
  tabs, tabs_stale = nil, false
  transport:set_tabs(nil)
  song_keys={}
  scroll=0
end

local function open_setlist()
  local chosen, path = reaper.GetUserFileName(1,'Open AutoTiazinha setlist',
    setlist and setlist.file_path or last_setlist_path,file_filter)
  if not chosen then return end
  local ok, loaded, err = pcall(Setlist.load,path)
  if not ok or not loaded then report_error(ok and err or loaded); return end
  if not can_leave() then return end
  if loaded.name~=file_name(path) then Setlist.set_name(loaded,file_name(path)) end
  local opened, load_err, code = load_tabs(loaded)
  if not opened and code~='missing_song' then status=load_err; return end
  setlist=loaded
  if not opened then
    tabs=nil; tabs_stale=false; transport:set_tabs(nil); status=load_err
  end
  song_keys={}
  remember_path(path)
  scroll=0
end

local function setlist_menu()
  gfx.x,gfx.y=gfx.mouse_x,gfx.mouse_y
  local choice=gfx.showmenu('New setlist|Open setlist')
  if choice==1 then new_setlist()
  elseif choice==2 then open_setlist() end
end

local function choose_project(title,initial)
  local chosen,path=reaper.GetUserFileName(1,title,initial,song_filter)
  if not chosen then return nil end
  if not reaper.file_exists(path) then report_error('Project file not found: '..path); return nil end
  return path
end

local function add_song()
  local last=setlist.songs[#setlist.songs]
  local folder=current_directory()
  local initial=last and reaper.file_exists(last.path) and last.path or
    (folder and folder..'/Song.RPP' or 'Song.RPP')
  local path=choose_project('Add song project',initial)
  if not path then return end
  local number=#setlist.songs+1
  if not edit_and_load(function(candidate) Setlist.add(candidate,path) end,
      'Added song '..number..'.') then return end
  song_keys[path]=nil
  local capacity=visible_capacity()
  scroll=math.max(0,#setlist.songs+1-capacity)
end

local function relink_song(index)
  local song=setlist.songs[index]
  local folder=current_directory()
  local name=song.path:match('[^/\\]+$') or 'Song.RPP'
  local initial=folder and folder..'/'..name or name
  local path=choose_project('Relink song project',initial)
  if not path then return end
  if not edit_and_load(function(candidate)
      return Setlist.set_song_path(candidate,index,path)
    end,'Relinked song '..index..'.') then return end
  song_keys[path]=nil
end

local function remove_song(index)
  if not edit_and_load(function(candidate) Setlist.remove(candidate,index) end,
      'Removed song '..index..' from the setlist.') then return end
  scroll=math.min(scroll,math.max(0,#setlist.songs+1-visible_capacity()))
end

local function select_song_tab(index)
  if editor_session then status='Close the Song Editor before selecting another tab.'; return end
  if not tabs or tabs_stale then return end
  if not Tabs.is_open(tabs) then
    status='A project tab is no longer open. Reload tabs.'
    tabs_stale=true
    return
  end
  local selected,err=transport:select(index)
  if selected then status='Selected song '..index..' tab.'
  else status=err; if err:find('no longer open') then tabs_stale=true end end
end

local function navigate(direction)
  select_song_tab(transport.selected+direction)
end

local function play_pause()
  if editor_session then status='Close the Song Editor before playing.'; return end
  if tabs_stale then status='Reload song tabs before playing.'; return end
  local ok,message=transport:play_pause()
  status=message
  if not ok and message:find('no longer open') then tabs_stale=true end
end

local function full_stop()
  local _,message=transport:full_stop()
  status=message
end

local function choose_pad()
  local folder=current_directory()
  local name=setlist.pad_project and (setlist.pad_project:match('[^/\\]+$') or 'Pad.RPP') or 'Pad.RPP'
  local initial=setlist.pad_project and reaper.file_exists(setlist.pad_project) and setlist.pad_project or
    (folder and folder..'/'..name or name)
  local path=choose_project('Choose pad project',initial)
  if not path then return end
  edit_and_load(function(candidate) return Setlist.set_pad_project(candidate,path) end,
    'Pad project selected.')
end

local function clear_pad()
  edit_and_load(function(candidate) return Setlist.set_pad_project(candidate,nil) end,
    'Pad project cleared.')
end

local function change_output_profile(change)
  if editor_session then status='Close the Song Editor before changing outputs.'; return end
  if song_is_playing() then status='Stop playback before changing outputs.'; return end
  local candidate={}
  for key,value in pairs(output_profile) do candidate[key]=value end
  change(candidate)
  local restored,restore_error=routing:restore_all()
  if not restored then status=restore_error; return end
  output_profile=candidate
  Output.save(candidate,reaper)
  local valid,warning=Output.validate(candidate,reaper)
  if not valid then status='Output profile inactive: '..warning; return end
  if tabs and Tabs.is_open(tabs) then
    local applied,apply_error=routing:apply_tabs(tabs,candidate)
    if not applied then status='Output profile inactive: '..apply_error; return end
  end
  status='Output profile updated for this computer.'
end

local function output_menu(items)
  gfx.x,gfx.y=gfx.mouse_x,gfx.mouse_y
  return gfx.showmenu(table.concat(items,'|'))
end

local function output_label(route,kind)
  if kind=='click' then return 'Out '..string.format('%d',route.click+1) end
  if route.stereo then
    return 'Outs '..string.format('%d/%d',route.music+1,route.music+2)
  end
  return 'Out '..string.format('%d',route.music+1)
end

local function choose_output_settings()
  local route=Output.effective(output_profile)
  local count=reaper.GetNumAudioOutputs()
  local items,choices={},{}
  local function add_submenu(title,options)
    if #options==0 then items[#items+1]='#'..title; return end
    items[#items+1]='>'..title
    -- Submenu headings do not get a selection number from gfx.showmenu.
    for index,option in ipairs(options) do
      items[#items+1]=(index==#options and '<' or '')..option.label
      choices[#choices+1]=option.choice
    end
  end
  local click_options,music_options={},{}
  for index=0,count-1 do
    local name=Output.channel_label(index,reaper):gsub('[|!#<>]',' ')
    click_options[#click_options+1]={label=name,choice={click=index}}
    music_options[#music_options+1]={label='Mono: '..name,
      choice={music=index,stereo=false}}
  end
  for index=0,count-2,2 do
    music_options[#music_options+1]={
      label='Stereo: '..Output.pair_label(index,reaper):gsub('[|!#<>]',' '),
      choice={music=index,stereo=true},
    }
  end
  add_submenu('Click/Cues: '..output_label(route,'click'),click_options)
  add_submenu('Music: '..output_label(route,'music'),music_options)
  items[#items+1]='#Device selected in REAPER preferences'
  local choice=choices[output_menu(items)]
  if choice then
    change_output_profile(function(profile)
      for key,value in pairs(choice) do profile[key]=value end
    end)
  end
end

local function choose_key(index)
  gfx.x,gfx.y=gfx.mouse_x,gfx.mouse_y
  local choice=gfx.showmenu('Song key|'..table.concat(Setlist.root_notes,'|'))
  if choice<1 then return end
  Setlist.set_root_override(setlist,index,Setlist.root_notes[choice-1])
  status='Key updated for song '..index..'.'
end

local function choose_transition(index)
  gfx.x,gfx.y=gfx.mouse_x,gfx.mouse_y
  local choice=gfx.showmenu(transition_menu)
  local mode=Setlist.transitions[choice]
  if not mode then return end
  Setlist.set_transition(setlist,index,mode)
  status='Transition updated after song '..index..'.'
end

local function transition_button(index,y,setlist_right)
  local mode=setlist.songs[index].transition
  local title=transition_info[mode]
  gfx.setfont(1)
  local title_width=gfx.measurestr(title)
  local w=title_width+20
  local x=(42+setlist_right-18-w)/2
  local hover=gfx.mouse_x>=x and gfx.mouse_x<x+w and gfx.mouse_y>=y and gfx.mouse_y<y+20
  color(C.button)
  gfx.line(48,y+10,x-8,y+10)
  gfx.line(x+w+8,y+10,setlist_right-24,y+10)
  label(title,x,y+2,hover and C.accent or C.text)
  color(hover and C.accent or C.muted)
  gfx.line(x+title_width+8,y+7,x+title_width+12,y+11)
  gfx.line(x+title_width+12,y+11,x+title_width+16,y+7)
  if hover then gfx.line(x,y+19,x+title_width,y+19) end
  buttons[#buttons+1]={x=x,y=y,w=w,h=20,action=function() choose_transition(index) end}
end

local function remove_button(index,x,y,w)
  local hover=gfx.mouse_x>=x and gfx.mouse_x<x+w and
    gfx.mouse_y>=y and gfx.mouse_y<y+34
  label('Remove',x+2,y+8,hover and C.warning or C.muted)
  if hover then
    color(C.warning); gfx.line(x+2,y+28,x+w-2,y+28)
  end
  buttons[#buttons+1]={x=x,y=y,w=w,h=34,action=function() remove_song(index) end}
end

local function draw()
  buttons,drag_starts={},{}
  rect(0,0,gfx.w,gfx.h,C.bg)
  label('AutoTiazinha Live',24,22,C.text,nil,2)
  button('Outputs',gfx.w-140,20,108,choose_output_settings,true,true)
  rect(24,76,gfx.w-48,62,C.panel)
  local ready=tabs and not tabs_stale and #tabs.entries>0 and not editor_session
  local stopped=ready and not transport:has_active_song()
  transport_button('Prev','previous',40,87,94,function() navigate(-1) end,
    stopped and transport.selected>1)
  transport_button('Next','next',142,87,88,function() navigate(1) end,
    stopped and transport.selected<#tabs.entries)
  local playing=transport:state()&1~=0
  transport_button(nil,playing and 'pause' or 'play',254,81,100,play_pause,ready,true)
  transport_button(nil,'stop',380,87,60,full_stop,true)
  if ready then
    label('Song '..transport.selected..' of '..#tabs.entries,462,99,C.muted,gfx.w-502)
  else
    label('Load a setlist to play',462,99,C.muted,gfx.w-502)
  end
  local pad_x,pad_width=gfx.w-264,240
  local setlist_right=pad_x-12
  rect(24,150,setlist_right-24,gfx.h-197,C.panel)
  rect(pad_x,150,pad_width,gfx.h-197,C.panel)
  button('New / Open',setlist_right-334,166,134,setlist_menu,true,true)
  button(tabs_stale and 'Reload Tabs' or 'Load Tabs',setlist_right-192,166,98,
    reload_tabs,setlist~=nil)
  button('Save',setlist_right-86,166,74,save,setlist~=nil)
  if setlist then
    label(setlist.name,40,167,C.text,setlist_right-382,2)
    label(setlist.dirty and 'Unsaved changes' or 'Saved',40,200,
      setlist.dirty and C.warning or C.accent)
    if tabs_stale then label('Project tabs need reloading',170,200,C.warning)
    elseif transport.marker_warning~='' then
      label(transport.marker_warning,170,200,C.warning,setlist_right-190)
    end
  else
    label('No setlist open',40,169,C.text,setlist_right-276,2)
  end
  color(C.button); gfx.line(40,233,setlist_right-16,233)

  label('Pad Project',pad_x+16,169,C.text,nil,2)
  color(C.button); gfx.line(pad_x+16,217,pad_x+pad_width-16,217)
  if setlist and setlist.pad_project then
    local pad=setlist.pad_project
    local exists=reaper.file_exists(pad)
    local shown=exists and (pad:match('[^/\\]+$') or pad) or 'Missing: '..pad
    label(shown,pad_x+16,238,exists and C.text or C.warning,pad_width-32)
  else
    label('No pad project selected',pad_x+16,238,C.muted)
  end
  button('Choose Pad',pad_x+16,284,pad_width-32,choose_pad,setlist~=nil)
  button('Clear',pad_x+16,326,pad_width-32,clear_pad,setlist~=nil and setlist.pad_project~=nil)

  local count=setlist and #setlist.songs or 0
  local total=setlist and count+1 or 0
  local capacity=visible_capacity()
  scroll=math.min(scroll,math.max(0,total-capacity))
  label('Songs'..(count>0 and ' ('..count..')' or ''),40,248,C.text,nil,2)
  button('Up',setlist_right-127,243,48,function() scroll=math.max(0,scroll-1) end,scroll>0)
  button('Down',setlist_right-71,243,55,function() scroll=math.min(total-capacity,scroll+1) end,
    total>capacity and scroll<total-capacity)
  if setlist then
    local preview=drag and drag.dragging and drag.target~=drag.source
    local visible=math.min(total-scroll,capacity)
    for i=1,visible do
      local index=scroll+i
      local y=ROW_TOP+(i-1)*ROW_HEIGHT
      if index>count then
        local slot_width=setlist_right-60
        local half=(slot_width-8)/2
        local slot_y=y+(count==0 and 4 or -12)
        button('+ Add .RPP',42,slot_y,half,add_song,not editor_session)
        button('+ New Song',50+half,slot_y,half,
          function() launch_editor('new') end,not editor_session)
      elseif preview and index==drag.target then
        local song=setlist.songs[drag.source]
        rect(42,y+2,setlist_right-60,30,C.drop)
        rect(42,y+2,3,30,C.accent)
        label(index..'.  '..(song.path:match('[^/\\]+$') or song.path),54,y+7,
          C.text,setlist_right-170)
        label('Drop here',setlist_right-106,y+7,C.accent)
        if index<count then transition_button(drag.source,y+34,setlist_right) end
      else
        local song_index=index
        if preview then
          if drag.source<drag.target and index>=drag.source and index<drag.target then
            song_index=index+1
          elseif drag.source>drag.target and index>drag.target and index<=drag.source then
            song_index=index-1
          end
        end
        local song=setlist.songs[song_index]
        local key_title='Key: '..(song.root_override or song_key(song.path) or 'Choose')
        gfx.setfont(1)
        local key_width=math.max(gfx.measurestr(key_title),widest_note_key)+24
        local remove_width=gfx.measurestr('Remove')+4
        local remove_x=setlist_right-18-remove_width
        local edit_width=gfx.measurestr('Edit')+28
        local edit_x=remove_x-edit_width-8
        local key_x=edit_x-key_width-8
        local exists=reaper.file_exists(song.path)
        local relink_x=key_x-96
        local name_right=exists and key_x-8 or relink_x-8
        drag_starts[#drag_starts+1]={index=song_index,x=42,y=y,w=name_right-42,h=34}
        if drag and drag.dragging and drag.source==song_index then
          rect(42,y,name_right-42,34,C.hover)
        end
        for dot_y=y+11,y+23,6 do
          rect(45,dot_y,2,2,C.muted)
          rect(50,dot_y,2,2,C.muted)
        end
        if exists then
          label(index..'.  '..(song.path:match('[^/\\]+$') or song.path),64,y+8,C.text,name_right-64)
        else
          label(index..'.  Missing: '..song.path,64,y+8,C.warning,name_right-64)
          button('Relink',relink_x,y,88,function() relink_song(song_index) end,true)
        end
        button('Edit',edit_x,y,edit_width,
          function() launch_editor('edit',song_index) end,exists and not editor_session)
        remove_button(song_index,remove_x,y,remove_width)
        button(key_title,key_x,y,key_width,
          function() choose_key(song_index) end,true)
        if index<count then transition_button(song_index,y+34,setlist_right) end
      end
    end
  else
    label('Create or open a setlist to add songs.',42,293,C.muted)
  end
  local shown_status=status
  if drag and drag.dragging and drag.target~=drag.source then
    shown_status='Moving song '..drag.source..' to position '..drag.target..'.'
  end
  label(shown_status,24,gfx.h-31,C.muted,gfx.w-48)
end

local function open_window()
  gfx.init('AutoTiazinha Live',800,640,0)
  gfx.setfont(1,'Arial',15)
  gfx.setfont(2,'Arial',23,string.byte('b'))
  gfx.setfont(1)
  for _,note in ipairs(Setlist.root_notes) do
    widest_note_key=math.max(widest_note_key,gfx.measurestr('Key: '..note))
  end
end

local function update_drag()
  if not drag.dragging then
    if math.abs(gfx.mouse_x-drag.start_x)<4 and math.abs(gfx.mouse_y-drag.start_y)<4 then
      return
    end
    drag.dragging=true
  end
  local capacity=visible_capacity()
  local max_scroll=math.max(0,#setlist.songs+1-capacity)
  scroll=math.min(scroll,max_scroll)
  if gfx.mouse_y<ROW_TOP then scroll=0
  elseif gfx.mouse_y>=ROW_TOP+capacity*ROW_HEIGHT then scroll=max_scroll end
  local direction=0
  if gfx.mouse_y<ROW_TOP+16 and scroll>0 then direction=-1
  elseif gfx.mouse_y>=ROW_TOP+capacity*ROW_HEIGHT-16 and scroll<max_scroll then direction=1 end
  if direction~=0 then
    drag.scroll_frames=(drag.scroll_frames or 0)+1
    if drag.scroll_frames>=10 then
      scroll=scroll+direction
      drag.scroll_frames=0
    end
  else
    drag.scroll_frames=0
  end
  if gfx.mouse_y<ROW_TOP then
    drag.target=1
  elseif gfx.mouse_y>=ROW_TOP+capacity*ROW_HEIGHT then
    drag.target=#setlist.songs
  else
    local target=scroll+math.floor((gfx.mouse_y-ROW_TOP)/ROW_HEIGHT)+1
    drag.target=math.max(1,math.min(#setlist.songs,target))
  end
end

local function frame()
  local repaired,repair_error=routing:watch_saves(
    function(project) transport:suspend_hold_loop(project) end,
    function(project) transport:resume_hold_loop(project) end)
  if not repaired then status='Output routing error: '..repair_error end
  local events=transport:update()
  for _,event in ipairs(events) do
    if event.kind=='song_end' then
      local _,message,pad_requests=transport:handle_song_end(event)
      status=message
      event.pad_requests=pad_requests -- Step 14 will consume these.
    end
  end
  transport:sync_selected()
  poll_editor()
  local char=gfx.getchar()
  if char<0 or char==27 then
    if can_leave() then closing=true
    elseif char<0 then open_window() end
    drag=nil
    mouse_was_down=false
  end
  if closing then gfx.quit(); return end
  if gfx.mouse_wheel>0 then scroll=math.max(0,scroll-1)
  elseif gfx.mouse_wheel<0 then scroll=scroll+1 end
  gfx.mouse_wheel=0
  local down=(gfx.mouse_cap&1)==1
  if drag then
    if down then update_drag()
    else
      update_drag()
      if drag.dragging and drag.target~=drag.source then
        edit_and_load(function(candidate)
          return Setlist.move(candidate,drag.source,drag.target)
        end,'Moved song to position '..drag.target..'.')
      elseif not drag.dragging then
        select_song_tab(drag.source)
      end
      drag=nil
    end
  end
  draw()
  if down and not mouse_was_down then
    local activated=false
    for _,control in ipairs(buttons) do
      if gfx.mouse_x>=control.x and gfx.mouse_x<control.x+control.w and
          gfx.mouse_y>=control.y and gfx.mouse_y<control.y+control.h then
        control.action()
        activated=true
        break
      end
    end
    if not activated then
      for _,row in ipairs(drag_starts) do
        if gfx.mouse_x>=row.x and gfx.mouse_x<row.x+row.w and
            gfx.mouse_y>=row.y and gfx.mouse_y<row.y+row.h then
          drag={source=row.index,target=row.index,start_x=gfx.mouse_x,start_y=gfx.mouse_y}
          break
        end
      end
    end
  end
  mouse_was_down=down
  gfx.update()
  reaper.defer(frame)
end

open_window()
reaper.atexit(function()
  if song_is_playing() then transport:full_stop() end
  transport:clear_hold()
  routing:restore_all()
end)
frame()
