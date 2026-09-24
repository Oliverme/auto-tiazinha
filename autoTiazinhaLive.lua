-- Live setlist window. Transport and pad controls arrive in later Live steps.
local dir = debug.getinfo(1, 'S').source:sub(2):match('^(.*)[/\\]') or '.'
local Setlist = dofile(dir .. '/autoTiazinhaSetlist.lua')

local setlist, status = nil, 'Create or open a setlist to begin.'
local buttons, mouse_was_down, closing, scroll = {}, false, false, 0
local drag_starts, drag = {}, nil
local song_keys = {}
local widest_note_key = 0
local ROW_TOP, ROW_HEIGHT = 206, 60
local C = {
  bg={0.075,0.09,0.115}, panel={0.11,0.13,0.165}, button={0.16,0.19,0.23},
  hover={0.22,0.27,0.32}, drop={0.15,0.25,0.27},
  text={0.91,0.93,0.95}, muted={0.57,0.63,0.69}, accent={0.37,0.79,0.68},
  warning={0.94,0.70,0.37},
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

local function visible_capacity()
  return math.max(1,math.floor((gfx.h-258)/ROW_HEIGHT))
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
  if not setlist or not setlist.dirty then return true end
  local answer = reaper.ShowMessageBox(
    'Save changes to "'..setlist.name..'" before leaving?',
    'AutoTiazinha Live',3)
  if answer == 6 then return save() end
  return answer == 7
end

local function new_setlist()
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
  created.file_path=path
  setlist, status = created, 'New setlist. Save when ready.'
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
  setlist, status = loaded, 'Setlist opened. Song project tabs are not opened yet.'
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
  local ok,err=pcall(Setlist.add,setlist,path)
  if not ok then report_error(err); return end
  song_keys[path]=nil
  local capacity=visible_capacity()
  scroll=math.max(0,#setlist.songs+1-capacity)
  status='Added song '..#setlist.songs..'.'
end

local function relink_song(index)
  local song=setlist.songs[index]
  local folder=current_directory()
  local name=song.path:match('[^/\\]+$') or 'Song.RPP'
  local initial=folder and folder..'/'..name or name
  local path=choose_project('Relink song project',initial)
  if not path then return end
  local ok,err=pcall(Setlist.set_song_path,setlist,index,path)
  if not ok then report_error(err); return end
  song_keys[path]=nil
  status='Relinked song '..index..'.'
end

local function remove_song(index)
  Setlist.remove(setlist,index)
  scroll=math.min(scroll,math.max(0,#setlist.songs+1-visible_capacity()))
  status='Removed song '..index..' from the setlist.'
end

local function choose_pad()
  local folder=current_directory()
  local name=setlist.pad_project and (setlist.pad_project:match('[^/\\]+$') or 'Pad.RPP') or 'Pad.RPP'
  local initial=setlist.pad_project and reaper.file_exists(setlist.pad_project) and setlist.pad_project or
    (folder and folder..'/'..name or name)
  local path=choose_project('Choose pad project',initial)
  if not path then return end
  local ok,err=pcall(Setlist.set_pad_project,setlist,path)
  if not ok then report_error(err); return end
  status='Pad project selected.'
end

local function clear_pad()
  Setlist.set_pad_project(setlist,nil)
  status='Pad project cleared.'
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
  local pad_x,pad_width=gfx.w-264,240
  local setlist_right=pad_x-12
  rect(24,76,setlist_right-24,gfx.h-123,C.panel)
  rect(pad_x,76,pad_width,gfx.h-123,C.panel)
  button('New / Open',setlist_right-228,92,134,setlist_menu,true,true)
  button('Save',setlist_right-86,92,74,save,setlist~=nil)
  if setlist then
    label(setlist.name,40,93,C.text,setlist_right-276,2)
    label(setlist.dirty and 'Unsaved changes' or 'Saved',40,126,
      setlist.dirty and C.warning or C.accent)
  else
    label('No setlist open',40,95,C.text,setlist_right-276,2)
  end
  color(C.button); gfx.line(40,159,setlist_right-16,159)

  label('Pad Project',pad_x+16,95,C.text,nil,2)
  color(C.button); gfx.line(pad_x+16,143,pad_x+pad_width-16,143)
  if setlist and setlist.pad_project then
    local pad=setlist.pad_project
    local exists=reaper.file_exists(pad)
    local shown=exists and (pad:match('[^/\\]+$') or pad) or 'Missing: '..pad
    label(shown,pad_x+16,164,exists and C.text or C.warning,pad_width-32)
  else
    label('No pad project selected',pad_x+16,164,C.muted)
  end
  button('Choose Pad',pad_x+16,210,pad_width-32,choose_pad,setlist~=nil)
  button('Clear',pad_x+16,252,pad_width-32,clear_pad,setlist~=nil and setlist.pad_project~=nil)

  local count=setlist and #setlist.songs or 0
  local total=setlist and count+1 or 0
  local capacity=visible_capacity()
  scroll=math.min(scroll,math.max(0,total-capacity))
  label('Songs'..(count>0 and ' ('..count..')' or ''),40,174,C.text,nil,2)
  button('Up',setlist_right-127,169,48,function() scroll=math.max(0,scroll-1) end,scroll>0)
  button('Down',setlist_right-71,169,55,function() scroll=math.min(total-capacity,scroll+1) end,
    total>capacity and scroll<total-capacity)
  if setlist then
    local preview=drag and drag.dragging and drag.target~=drag.source
    local visible=math.min(total-scroll,capacity)
    for i=1,visible do
      local index=scroll+i
      local y=ROW_TOP+(i-1)*ROW_HEIGHT
      if index>count then
        button('+ Add song...',42,y+(count==0 and 4 or -12),setlist_right-60,add_song,true)
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
        local key_x=setlist_right-18-key_width
        local remove_width=gfx.measurestr('Remove')+4
        local remove_x=key_x-remove_width-8
        local exists=reaper.file_exists(song.path)
        local relink_x=remove_x-96
        local name_right=exists and remove_x-8 or relink_x-8
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
        remove_button(song_index,remove_x,y,remove_width)
        button(key_title,key_x,y,key_width,
          function() choose_key(song_index) end,true)
        if index<count then transition_button(song_index,y+34,setlist_right) end
      end
    end
  else
    label('Create or open a setlist to add songs.',42,219,C.muted)
  end
  local shown_status=status
  if drag and drag.dragging and drag.target~=drag.source then
    shown_status='Moving song '..drag.source..' to position '..drag.target..'.'
  end
  label(shown_status,24,gfx.h-31,C.muted,gfx.w-48)
end

local function open_window()
  gfx.init('AutoTiazinha Live',800,520,0)
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
        Setlist.move(setlist,drag.source,drag.target)
        status='Moved song to position '..drag.target..'.'
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
frame()
