-- Native REAPER gfx editor: no additional GUI extension required.
-- Keep beside autoTiazinhaBuilder.lua, autoTiazinhaEditorModel.lua and media/.
local dir=debug.getinfo(1,'S').source:sub(2):match('^(.*)[/\\]') or '.'
local builder=dofile(dir..'/autoTiazinhaBuilder.lua')
local Model=dofile(dir..'/autoTiazinhaEditorModel.lua')
local draft,target,target_name,applied,attempted,status
local palette,language={},nil
local common_sections,other_sections={},{}
local variants={}
local cache={}
local click_sounds={''}
local scroll,pressed,drag,last_down=0,nil,nil,false
local hits,strip={},nil
local closing=false
local editing=nil
local CARD,GAP=154,12
local C={bg={0.075,0.09,0.115},panel={0.11,0.13,0.165},button={0.16,0.19,0.23},hover={0.22,0.27,0.32},text={0.91,0.93,0.95},muted={0.57,0.63,0.69},accent={0.37,0.79,0.68},warning={0.94,0.70,0.37}}
local function color(c) gfx.set(c[1],c[2],c[3],1) end
local function rect(x,y,w,h,c) color(c); gfx.rect(x,y,w,h,1) end
local function text(value,x,y,c,width,font)
  gfx.setfont(font or 1); color(c or C.text); gfx.x,gfx.y=x,y
  if width then gfx.drawstr(tostring(value),0,x+math.max(0,width),y+28) else gfx.drawstr(tostring(value)) end
end
local function inside(r,x,y) return r and x>=r.x and x<r.x+r.w and y>=r.y and y<r.y+r.h end
local function exists(path)
  if cache[path]==nil then cache[path]=reaper.file_exists(path) end
  return cache[path]
end
local function snapshot()
  local s=Model.settings(draft)
  local parts={}
  for _,key in ipairs({'song_name','bpm','time_signature_numerator','time_signature_denominator','cue_lang','is_double_click','click_accent','click_beat','song_structure_text'}) do
    local v=tostring(s[key]); parts[#parts+1]=#v..':'..v
  end
  return table.concat(parts)
end
local function load_project()
  local _,saved=builder.load_song_settings()
  local ok,value=pcall(Model.new,saved)
  if not ok then status=tostring(value); return false end
  draft=value; target=reaper.EnumProjects(-1,''); target_name=reaper.GetProjectName(target)
  scroll,language,cache=0,nil,{}
  applied=snapshot(); attempted=applied; status='UI changes are built automatically.'
  return true
end
local build_song
local function changed(message)
  status=message
  build_song()
end
local function refresh_palette()
  if language==draft.settings.cue_lang then return end
  language=draft.settings.cue_lang; palette={}; variants={}; cache={}
  local i=0
  while true do
    local file=reaper.EnumerateFiles(dir..'/media/'..language,i)
    if not file then break end
    local name=file:match('^(.*)%.wav$')
    if name and not name:match('^%d+$') then
      local base=name:match('^(.-)%s+%d+$') or name
      variants[base]=variants[base] or {}
      table.insert(variants[base],name)
      if base==name then palette[#palette+1]=name end
    end
    i=i+1
  end
  for base,choices in pairs(variants) do
    table.sort(choices,function(a,b)
      local na=a==base and -1 or tonumber(a:match('(%d+)$'))
      local nb=b==base and -1 or tonumber(b:match('(%d+)$'))
      if na~=nb then return na<nb end
      return a<b
    end)
  end
  local priority={Intro=1,Verse=2,['Pre Chorus']=3,Chorus=4,Bridge=5,Ending=6}
  common_sections,other_sections={},{}
  table.sort(palette,function(a,b)
    local pa,pb=priority[a] or 99,priority[b] or 99
    if pa~=pb then return pa<pb end
    return a<b
  end)
  for _,name in ipairs(palette) do
    local group=priority[name] and common_sections or other_sections
    group[#group+1]=name
  end
end
local function card_variants(card)
  local base=card.name:match('^(.-)%s+%d+$') or card.name
  local choices=variants[base]
  -- Also allow recovery when the current language lacks a saved variant.
  if choices and (#choices>1 or choices[1]~=card.name) then return choices end
end
local function choose_variant(card)
  local choices=card_variants(card)
  if not choices then return end
  local items={}
  for i,name in ipairs(choices) do items[i]=(name==card.name and '!' or '')..name end
  gfx.x,gfx.y=gfx.mouse_x,gfx.mouse_y
  local selected=gfx.showmenu(table.concat(items,'|'))
  if choices[selected] and choices[selected]~=card.name then
    card.name=choices[selected]
    changed('Cue changed to '..card.name..'.')
  end
end
local function begin_length_edit(card,is_new)
  editing={card=card, id='length:'..card.id, value=card.measures, selected=true, is_new=is_new}
  status='Type a whole-bar count. Enter applies; Escape cancels.'
end
local function minimum_length(card)
  return draft.sections[#draft.sections]==card and 0 or 1
end
local function commit_edit()
  if not editing then return true end
  local value=editing.value
  local number=tonumber(value)
  if editing.key then
    local key=editing.key
    local previous=draft.settings[key]
    if editing.key=='song_name' then
      if not value:match('%S') or value:find(',') then
        status='Enter a song name without commas.'; return false
      end
      draft.settings.song_name=value
    else
      if not number or number<=0 or number==math.huge then status='Tempo must be a positive number.'; return false end
      draft.settings.bpm=number
    end
    editing=nil
    if draft.settings[key]~=previous then changed('Song settings updated.') end
    return true
  end
  if not value:match('^%d+$') or not number or number<minimum_length(editing.card) or number>=math.maxinteger then
    status='Enter whole bars (zero is allowed only for the final section), or Escape to cancel.'
    return false
  end
  local card=editing.card
  local previous=card.measures
  card.measures=tostring(math.floor(number))
  editing=nil
  if card.measures~=previous then changed('Section length updated.') end
  return true
end
local function edit_key(char)
  if not editing then return false end
  if char==27 then
    if editing.is_new then Model.remove(draft,editing.card.id) end
    editing=nil; status='Edit canceled.'; return true
  end
  if char==13 then commit_edit(); return true end
  if char==1 then editing.selected=true; return true end -- Ctrl+A
  if char==8 or char==127 then
    local last=utf8.offset(editing.value,-1)
    editing.value=editing.selected and '' or (last and editing.value:sub(1,last-1) or '')
    editing.selected=false
  else
    local code=char>>24==string.byte('u') and (char&0xFFFFFF) or char
    local printable=(code>=32 and code<=255) or char>>24==string.byte('u')
    local allowed=editing.key=='song_name' and printable
      or (char>=48 and char<=57) or (editing.key=='bpm' and char==46)
    if allowed then
      editing.value=(editing.selected and '' or editing.value)..utf8.char(code)
      editing.selected=false
    end
  end
  return true
end
local function custom_length(card)
  local ok,value=reaper.GetUserInputs('Custom section length',1,'Measures (dot = half bar),extrawidth=180',card.measures)
  if not ok then return end
  value=value:match('^%s*(.-)%s*$')
  local bars,_,half=Model.length(value)
  if bars==0 and minimum_length(card)>0 then status='Only the final section can have zero bars.'; return end
  if not bars then status='Use positive whole bars or dots, for example 8 or 4.'; return end
  if half and draft.settings.time_signature_numerator%2~=0 then status='Half bars require an even meter numerator in this builder.'; return end
  if card.measures~=value then card.measures=value; changed('Custom length updated.') end
end
local function step_length(card,delta)
  -- Do not silently flatten a custom sequence such as 4.2.
  if not card.measures:match('^%d+$') then return end
  local value=tonumber(card.measures)
  if value and value+delta>=minimum_length(card) and value+delta<math.maxinteger then
    card.measures=tostring(math.floor(value+delta))
    changed('Section length updated.')
  end
end
local function add_section(name,position)
  local card=Model.add(draft,name,nil,position)
  if not position then scroll=math.max(0,#draft.sections*(CARD+GAP)-GAP-strip.w) end
  begin_length_edit(card,true)
end
build_song=function(force)
  local current=snapshot()
  if current==applied then return end
  if current==attempted and not force then return end
  if reaper.EnumProjects(-1,'')~=target then status='Switch back to '..target_name..' before building.'; return end
  if reaper.GetPlayState()~=0 then status='Stop playback before building.'; return end
  cache={}
  local errors=Model.validate(draft,exists,dir..'/media/')
  if #errors>0 then status=errors[1]; return end
  attempted=current
  local ok,result=pcall(builder.build,Model.settings(draft))
  if ok then
    target=reaper.EnumProjects(-1,''); target_name=reaper.GetProjectName(target)
    applied=current; attempted=current; status='Built and saved '..target_name..'.'
  else
    status='Build failed; the project may be partly updated.'
    reaper.ShowMessageBox(tostring(result),'AutoTiazinha build error',0)
  end
end
local function request_load()
  if snapshot()~=applied and reaper.ShowMessageBox('Discard unapplied changes and load the active project?','AutoTiazinha',4)~=6 then return end
  load_project()
end
-- Hit regions are in window coordinates, including clipped strip controls.
local function hit(id,x,y,w,h,action,kind,data,clip)
  if clip then
    local right,bottom=math.min(x+w,clip.x+clip.w),math.min(y+h,clip.y+clip.h)
    x,y=math.max(x,clip.x),math.max(y,clip.y); w,h=right-x,bottom-y
  end
  if w>0 and h>0 then hits[#hits+1]={id=id,x=x,y=y,w=w,h=h,action=action,kind=kind,data=data} end
end
local function button(label,x,y,w,h,action,enabled,id)
  local hover=inside({x=x,y=y,w=w,h=h},gfx.mouse_x,gfx.mouse_y)
  rect(x,y,w,h,enabled==false and C.panel or hover and C.hover or C.button)
  text(label,x+12,y+9,enabled==false and C.muted or C.text,w-20)
  if enabled~=false then hit(id or label,x,y,w,h,action) end
end
local function setting_field(key,label,x,y,w)
  text(label,x,y,C.muted,w)
  rect(x,y+22,w,30,C.button)
  local active=editing and editing.key==key
  local value=active and editing.value or tostring(draft.settings[key])
  gfx.setfont(1)
  while #value>0 and gfx.measurestr(value)>w-18 do
    value=value:sub(utf8.offset(value,2) or #value+1)
  end
  local tw,th=gfx.measurestr(value)
  if active and editing.selected then rect(x+6,y+26,tw+4,th+2,C.accent) end
  text(value,x+8,y+27,active and editing.selected and C.bg or C.text,w-16)
  if active and not editing.selected then rect(x+9+tw,y+27,1,th,C.accent) end
  hit('setting:'..key,x,y+22,w,30,function()
    editing={key=key,id='setting:'..key,value=tostring(draft.settings[key]),selected=true}
    status='Type a value. Enter applies; Escape cancels.'
  end)
end
local function select_setting(key,choices)
  local labels={}
  for i,v in ipairs(choices) do labels[i]=(v==draft.settings[key] and '!' or '')..(v=='' and 'Built-in' or tostring(v)) end
  gfx.x,gfx.y=gfx.mouse_x,gfx.mouse_y
  local choice=gfx.showmenu(table.concat(labels,'|'))
  if choices[choice]~=nil then
    local previous=draft.settings[key]
    local previous_double=draft.settings.is_double_click
    draft.settings[key]=choices[choice]
    if key=='time_signature_numerator' and choices[choice]~=4 then draft.settings.is_double_click=false end
    cache={}
    if draft.settings[key]~=previous or draft.settings.is_double_click~=previous_double then changed('Song settings updated.') end
  end
end
local function checkbox(label,x,y,w,checked,enabled,action)
  local ink=enabled and C.accent or C.muted
  rect(x,y+5,20,20,ink)
  rect(x+1,y+6,18,18,C.bg)
  if checked then
    color(ink)
    gfx.line(x+4,y+15,x+9,y+20)
    gfx.line(x+9,y+20,x+16,y+10)
  end
  text(label,x+29,y+7,enabled and C.text or C.muted,w-29)
  if enabled then hit('double-click',x,y,w,32,action) end
end
local function settings_panel(width)
  local s=draft.settings
  -- Song identity stays separate from the timing and click controls.
  setting_field('song_name','Song name',24,91,width-142)
  text('Cue language',width-102,91,C.muted,118)
  button(s.cue_lang,width-102,113,126,30,function() select_setting('cue_lang',{'EN','PT'}) end)
  local wide=width>=920
  rect(24,155,width,wide and 94 or 156,C.panel)
  text('RHYTHM & CLICK',36,164,C.muted,width-24)
  local tx=36
  setting_field('bpm','Tempo (BPM)',tx,185,76)
  button('-',tx+80,207,30,30,function()
    local value=math.max(1,s.bpm-1)
    if value~=s.bpm then s.bpm=value; changed('Tempo updated.') end
  end,true,'tempo-minus')
  button('+',tx+114,207,30,30,function() s.bpm=s.bpm+1; changed('Tempo updated.') end,true,'tempo-plus')
  local mx=tx+160
  text('Time signature',mx,185,C.muted,124)
  button(tostring(s.time_signature_numerator),mx,207,48,30,function() select_setting('time_signature_numerator',{2,3,4,6}) end,true,'meter-numerator')
  text('/',mx+55,215,C.muted,12)
  button(tostring(s.time_signature_denominator),mx+73,207,48,30,function() select_setting('time_signature_denominator',{2,4,8,16}) end,true,'meter-denominator')
  checkbox('Double click',mx+138,207,140,s.is_double_click,s.time_signature_numerator==4,function()
    s.is_double_click=not s.is_double_click; changed('Click pattern updated.')
  end)
  local sx=wide and mx+294 or 36
  local sy=wide and 185 or 247
  local sound_width=wide and (width-12-(sx-24)-12)/2 or (width-36)/2
  text('Accent sound',sx,sy,C.muted,sound_width)
  button(s.click_accent=='' and 'Built-in' or s.click_accent,sx,sy+22,sound_width,30,function() select_setting('click_accent',click_sounds) end,true,'click-accent')
  text('Secondary sound',sx+sound_width+12,sy,C.muted,sound_width)
  button(s.click_beat=='' and 'Built-in' or s.click_beat,sx+sound_width+12,sy+22,sound_width,30,function() select_setting('click_beat',click_sounds) end,true,'click-secondary')
  return wide and 261 or 323
end
local function gap_at(x)
  return math.max(1,math.min(#draft.sections+1,math.floor((x-strip.x+scroll+CARD/2)/(CARD+GAP))+1))
end
local function draw_order(y,width)
  strip={x=24,y=y,w=width,h=126}
  local max_scroll=math.max(0,#draft.sections*(CARD+GAP)-GAP-width)
  scroll=math.max(0,math.min(scroll,max_scroll))
  if inside(strip,gfx.mouse_x,gfx.mouse_y) then
    local wheel=(gfx.mouse_hwheel or 0)+(gfx.mouse_wheel or 0)
    scroll=math.max(0,math.min(scroll-wheel/120*90,max_scroll))
    if drag then
      if gfx.mouse_x<strip.x+30 then scroll=math.max(0,scroll-10)
      elseif gfx.mouse_x>strip.x+strip.w-30 then scroll=math.min(max_scroll,scroll+10) end
    end
  end
  -- Render into a viewport image so partially scrolled cards cannot paint
  -- outside the song-order strip. Mouse regions use the same clipping bounds.
  gfx.setimgdim(1,math.floor(width),126); gfx.dest=1
  rect(0,0,width,126,C.panel)
  for i,card in ipairs(draft.sections) do
    local x=(i-1)*(CARD+GAP)-scroll
    if x+CARD>0 and x<width then
      rect(x,8,CARD,108,C.button); rect(x,8,CARD,3,C.accent)
      text(string.format('%02d',i),x+12,20,C.muted,40)
      local choices=card_variants(card)
      local missing=not exists(dir..'/media/'..draft.settings.cue_lang..'/'..card.name..'.wav')
      text(card.name,x+12,45,missing and C.warning or C.text,choices and CARD-42 or CARD-24)
      if choices then
        color(C.muted)
        gfx.line(x+CARD-26,50,x+CARD-21,55)
        gfx.line(x+CARD-21,55,x+CARD-16,50)
      end
      local active=editing and editing.card and editing.card.id==card.id
      local whole=card.measures:match('^%d+$')~=nil
      rect(x+10,71,28,26,C.panel)
      rect(x+42,71,70,26,C.panel)
      rect(x+116,71,28,26,C.panel)
      text('-',x+19,75,whole and tonumber(card.measures)>minimum_length(card) and C.accent or C.muted,18)
      local value=active and editing.value or card.measures
      gfx.setfont(1)
      -- Keep the count centered; long edits show their trailing digits.
      while #value>0 and gfx.measurestr(value)>58 do value=value:sub(2) end
      local count_width,count_height=gfx.measurestr(value)
      local count_x=x+42+(70-count_width)/2
      local count_y=71+(26-count_height)/2
      if active and editing.selected and #value>0 then
        rect(count_x-2,count_y-1,count_width+4,count_height+2,C.accent)
      end
      text(value,count_x,count_y,active and editing.selected and C.bg or C.accent,60)
      if active and not editing.selected then
        rect(count_x+count_width+1,count_y,1,count_height,C.accent)
      end
      text('+',x+124,75,whole and C.accent or C.muted,18)
      text('Custom',x+90,99,C.muted,60)
      text('x',x+CARD-22,20,C.muted,16)
      hit('card:'..card.id,strip.x+x,strip.y+8,CARD,65,nil,'card',card.id,strip)
      if choices then
        hit('variant:'..card.id,strip.x+x,strip.y+38,CARD,30,function() choose_variant(card) end,'card',card.id,strip)
      end
      hit('remove:'..card.id,strip.x+x+CARD-30,strip.y+12,30,30,function()
        if Model.remove(draft,card.id) then changed('Section removed.') end
      end,nil,nil,strip)
      hit('length:'..card.id,strip.x+x+42,strip.y+71,70,26,function() begin_length_edit(card) end,nil,nil,strip)
      if whole then
        hit('minus:'..card.id,strip.x+x+10,strip.y+71,28,26,function() step_length(card,-1) end,nil,nil,strip)
        hit('plus:'..card.id,strip.x+x+116,strip.y+71,28,26,function() step_length(card,1) end,nil,nil,strip)
      end
      hit('custom:'..card.id,strip.x+x+85,strip.y+98,69,18,function() custom_length(card) end,nil,nil,strip)
    end
  end
  if #draft.sections==0 then text('Click or drag a section above to start your song.',18,50,C.muted,width-36) end
  if drag and inside(strip,gfx.mouse_x,gfx.mouse_y) then
    local x=(gap_at(gfx.mouse_x)-1)*(CARD+GAP)-scroll-5
    rect(math.max(1,math.min(width-3,x)),4,3,118,C.accent)
  end
  gfx.dest=-1; gfx.x,gfx.y=strip.x,strip.y; gfx.blit(1,1,0)
  local controls=y+140
  button('<',24,controls,38,32,function() scroll=math.max(0,scroll-(CARD+GAP)) end,scroll>0,'scroll-left')
  button('>',70,controls,38,32,function() scroll=math.min(max_scroll,scroll+CARD+GAP) end,scroll<max_scroll,'scroll-right')
  local barx,barw=125,width-101
  rect(barx,controls+13,barw,5,C.panel)
  local total=math.max(width,#draft.sections*(CARD+GAP)-GAP)
  local thumb=math.max(24,barw*width/total)
  local thumbx=barx+(max_scroll>0 and scroll/max_scroll*(barw-thumb) or 0)
  rect(thumbx,controls+9,thumb,13,C.muted)
  if max_scroll>0 then
    hit('scrollbar',barx,controls,barw,32,nil,'scrollbar',{x=barx,w=barw,thumb=thumb,max=max_scroll})
  end
end
local function draw()
  hits={}; gfx.dest=-1; rect(0,0,gfx.w,gfx.h,C.bg)
  if gfx.w<620 or gfx.h<760 then
    text('Enlarge this window to at least 620 x 760 to edit.',24,28,C.text,gfx.w-48)
    return false
  end
  local width=math.min(gfx.w-48,8100)
  text('AUTOTIAZINHA',24,22,C.accent,width,2)
  text('Project: '..target_name,24,61,C.muted,width)
  button('Load project',gfx.w-178,22,154,36,request_load)
  local s=draft.settings
  local settings_bottom=settings_panel(width)
  local palette_y=settings_bottom+33
  text('ADD SECTIONS',24,settings_bottom,C.muted,width)
  refresh_palette()
  local columns=math.max(1,math.floor((width+8)/150))
  local cell=(width-(columns-1)*8)/columns
  local groups={{label='Common sections',items=common_sections},{label='Other sections',items=other_sections}}
  local palette_height=0
  for _,group in ipairs(groups) do
    if #group.items>0 then palette_height=palette_height+28+math.ceil(#group.items/columns)*40 end
  end
  local order_y=palette_y+palette_height+42
  -- Compact windows retain the same grouping in two separate native menus.
  if order_y+320>gfx.h then
    for i,group in ipairs(groups) do
      button(group.label..' +',24+(i-1)*230,palette_y,220,36,function()
        gfx.x,gfx.y=gfx.mouse_x,gfx.mouse_y
        local choice=gfx.showmenu(table.concat(group.items,'|'))
        if choice>0 then add_section(group.items[choice]) end
      end,#group.items>0)
    end
    order_y=palette_y+84
  else
    local group_y=palette_y
    for _,group in ipairs(groups) do
      if #group.items>0 then
        text(group.label,24,group_y,C.muted,width)
        for i,name in ipairs(group.items) do
          local x=24+((i-1)%columns)*(cell+8)
          local y=group_y+28+math.floor((i-1)/columns)*40
          button(name,x,y,cell,32,function() add_section(name) end,true,'palette:'..name)
          hits[#hits].kind,hits[#hits].data='palette',name
        end
        group_y=group_y+28+math.ceil(#group.items/columns)*40
      end
    end
  end
  if #palette==0 then text('No unnumbered cues found in media/'..s.cue_lang,24,palette_y,C.warning,width) end
  text('SONG ORDER',24,order_y-30,C.muted,width)
  text('Drag titles to reorder. Click a count to edit.',190,order_y-30,C.muted,width-170)
  draw_order(order_y,width)
  local bottom=order_y+196
  local bars=Model.summary(draft)
  text(#draft.sections..' sections'..(bars and '  /  '..bars..' numbered bars' or ''),24,bottom,C.muted,width)
  local errors=Model.validate(draft,exists,dir..'/media/')
  local same=reaper.EnumProjects(-1,'')==target
  local stopped=reaper.GetPlayState()==0
  local pending=snapshot()~=applied
  button('Retry automatic build',24,bottom+32,205,40,function() build_song(true) end,pending and #errors==0 and same and stopped)
  text(pending and 'Waiting to build' or 'Project is up to date',245,bottom+45,C.muted,width-245)
  local message=not same and ('Switch back to '..target_name..' or load the active project.') or not stopped and 'Stop playback before building.' or errors[1] or status
  text(message,24,bottom+86,(not same or not stopped or #errors>0) and C.warning or C.muted,width)
  if drag and drag.kind~='scrollbar' then
    rect(gfx.mouse_x+12,gfx.mouse_y+16,160,30,C.hover)
    text(drag.kind=='palette' and drag.data or 'Move section',gfx.mouse_x+20,gfx.mouse_y+22,C.text,144)
  end
  return true
end
local function hit_at(x,y)
  for i=#hits,1,-1 do if inside(hits[i],x,y) then return hits[i] end end
end
local function input(down)
  if down and not last_down then
    pressed=hit_at(gfx.mouse_x,gfx.mouse_y)
    if editing and (not pressed or pressed.id~=editing.id) then
      if not commit_edit() then pressed=nil; last_down=down; return end
    end
    if pressed then pressed.startx,pressed.starty=gfx.mouse_x,gfx.mouse_y end
  end
  if down and pressed and pressed.kind then
    local distance=math.abs(gfx.mouse_x-pressed.startx)+math.abs(gfx.mouse_y-pressed.starty)
    if distance>5 or pressed.kind=='scrollbar' then drag=pressed end
    if drag and drag.kind=='scrollbar' then
      local d=drag.data
      scroll=math.max(0,math.min(d.max,(gfx.mouse_x-d.x-d.thumb/2)/math.max(1,d.w-d.thumb)*d.max))
    end
  end
  if not down and last_down and pressed then
    if drag then
      if drag.kind~='scrollbar' and inside(strip,gfx.mouse_x,gfx.mouse_y) then
        local destination=gap_at(gfx.mouse_x)
        if drag.kind=='card' then
          if Model.move(draft,drag.data,destination) then changed('Sections reordered.') end
        elseif drag.kind=='palette' then add_section(drag.data,destination) end
      end
    else
      local current=hit_at(gfx.mouse_x,gfx.mouse_y)
      if current and current.id==pressed.id and current.action then current.action() end
    end
    pressed,drag=nil,nil
  end
  last_down=down
end
local function open_window()
  gfx.init('AutoTiazinha — Native song editor',1080,960,0)
  gfx.setfont(1,'Arial',15); gfx.setfont(2,'Arial',23,string.byte('b'))
end
local function frame()
  local char=gfx.getchar()
  if char>=0 and edit_key(char) then char=0 end
  if char<0 or char==27 then
    if (snapshot()~=applied or (editing and editing.value~=tostring(editing.key and draft.settings[editing.key] or editing.card.measures))) and reaper.ShowMessageBox('Discard unapplied changes and close the editor?','AutoTiazinha',4)~=6 then
      if char<0 then open_window() end
      pressed,drag,last_down=nil,nil,false
    else closing=true end
  end
  if closing then gfx.quit(); return end
  local usable=draw()
  if usable then input((gfx.mouse_cap&1)==1) else pressed,drag,last_down=nil,nil,false end
  -- Guarded changes build as soon as the user returns to the target project
  -- and stops playback. Failed builds wait for the explicit retry button.
  if usable and not editing and snapshot()~=applied and snapshot()~=attempted then build_song() end
  gfx.mouse_wheel,gfx.mouse_hwheel=0,0
  gfx.update(); reaper.defer(frame)
end
if not load_project() then reaper.ShowMessageBox(status,'AutoTiazinha',0); return end
do
  local i=0
  while true do
    local file=reaper.EnumerateFiles(dir..'/media/click',i)
    if not file then break end
    local name=file:match('^(.*)%.wav$')
    if name then click_sounds[#click_sounds+1]=name end
    i=i+1
  end
  table.sort(click_sounds)
end
open_window()
reaper.atexit(function() gfx.quit() end)
reaper.defer(frame)
