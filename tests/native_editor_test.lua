-- REAPER/gfx behavioral tests. No GUI extensions or native window required.
local root=arg[1] or '.'
local function harness()
  local H={queue={},draws={},menus={},answers={},builds={},active='a',play=0,confirm=6,char=0,closed=false,dialogs={}}
  local g={w=1080,h=780,mouse_x=0,mouse_y=0,mouse_cap=0,mouse_wheel=0,mouse_hwheel=0,dest=-1,x=0,y=0}
  g.init=function(_,w,h) g.w,g.h=w,h; H.closed=false end
  g.setfont=function(_,_,_,flags) assert(flags==nil or type(flags)=='number') end
  g.measurestr=function(value) return #value*8,15 end
  g.set=function() end
  g.rect=function() end
  g.line=function() end
  g.drawstr=function(value) H.draws[#H.draws+1]={value=value,x=g.x,y=g.y,dest=g.dest} end
  g.setimgdim=function(_,w,h) assert(w>0 and w<=8192 and h>0 and h<=8192) end
  g.blit=function() H.strip={x=g.x,y=g.y} end
  g.getchar=function() return H.char end
  g.update=function() end
  g.quit=function() H.closed=true end
  g.showmenu=function(value)
    H.last_menu=value
    return table.remove(H.menus,1) or 0
  end
  setmetatable(g,{__index=function(_,key) error('Unknown gfx API '..key) end})
  local api={
    EnumProjects=function() return H.active end,
    GetProjectName=function() return 'Song Name.RPP' end,
    GetPlayState=function() return H.play end,
    file_exists=function(path) return not path:match('/PT/Chorus %d+%.wav$') end,
    EnumerateFiles=function(folder,i)
      if folder:match('/click$') then return ({'Classic-accents.wav','Classic-quarter.wav'})[i+1] end
      if folder:match('/PT$') then return ({'Intro.wav','Verse.wav','Chorus.wav','Ending.wav','2.wav'})[i+1] end
      return ({'Intro.wav','Verse.wav','Chorus.wav','Ending.wav','Chorus 10.wav','Chorus 2.wav','Chorus 1.wav','Verse 2.wav','2.wav'})[i+1]
    end,
    ShowMessageBox=function(value) H.dialogs[#H.dialogs+1]=value; return H.confirm end,
    GetUserInputs=function() local answer=table.remove(H.answers,1); return answer~=nil,answer end,
    defer=function(fn) H.queue[#H.queue+1]=fn end,
    atexit=function(fn) H.cleanup=fn end,
  }
  setmetatable(api,{__index=function(_,key) error('Unknown REAPER API '..key) end})
  local builder={load_song_settings=function() return false,{} end,build=function(settings)
    H.builds[#H.builds+1]=settings
    if H.fail then error('Simulated failure') end
    return 100
  end}
  local env=setmetatable({reaper=api,gfx=g},{__index=_G})
  env.dofile=function(path)
    if path:match('autoTiazinhaBuilder.lua$') then return builder end
    return dofile(path)
  end
  assert(loadfile(root..'/autoTiazinhaNativeEditor.lua','t',env))()
  function H.frame()
    H.draws={}
    assert(table.remove(H.queue,1),'editor stopped unexpectedly')()
  end
  function H.find(label,dest,occurrence)
    occurrence=occurrence or 1
    for _,d in ipairs(H.draws) do
      if d.value==label and (dest==nil or d.dest==dest) then
        occurrence=occurrence-1
        if occurrence==0 then return d.x+(d.dest==1 and H.strip.x or 0)+3,d.y+(d.dest==1 and H.strip.y or 0)+3 end
      end
    end
    error('Label not drawn: '..label)
  end
  function H.click(label,dest,occurrence)
    local x,y=H.find(label,dest,occurrence)
    g.mouse_x,g.mouse_y,g.mouse_cap=x,y,1; H.frame()
    g.mouse_cap=0; H.frame(); H.frame()
  end
  function H.key(code)
    H.char=code; H.frame(); H.char=0; H.frame()
  end
  function H.type(value)
    for i=1,#value do H.key(value:byte(i)) end
  end
  function H.build()
    H.click('Build / Update song',-1)
    return H.builds[#H.builds].song_structure_text
  end
  H.gfx=g; H.frame(); return H
end
local settings_test=harness()
settings_test.click('Song Name',-1); settings_test.type('My Song'); settings_test.key(13)
settings_test.click('120',-1); settings_test.type('97.5'); settings_test.key(13)
settings_test.click('+',-1); settings_test.click('-',-1)
settings_test.click('Double click',-1)
settings_test.menus={2}; settings_test.click('Built-in',-1,1)
settings_test.menus={3}; settings_test.click('Built-in',-1,1)
settings_test.build()
local settings=settings_test.builds[#settings_test.builds]
assert(settings.song_name=='My Song' and settings.bpm==97.5 and settings.is_double_click)
assert(settings.click_accent=='Classic-accents' and settings.click_beat=='Classic-quarter')
-- Meter changes clear an incompatible double-click choice.
settings_test.menus={4}; settings_test.click('4',-1,1)
settings_test.menus={3}; settings_test.click('4',-1,1)
settings_test.click('Double click',-1)
settings_test.build()
settings=settings_test.builds[#settings_test.builds]
assert(settings.time_signature_numerator==6 and settings.time_signature_denominator==8 and not settings.is_double_click)
-- Unicode names, backspace and commit-on-build share the inline editing flow.
settings_test.click('My Song',-1); settings_test.type('Can'); settings_test.key(231); settings_test.key(227); settings_test.type('o')
settings_test.key(8); settings_test.type('o')
settings_test.build(); assert(settings_test.builds[#settings_test.builds].song_name=='Canção')
settings_test.click('Canção',-1); settings_test.type('Changed'); settings_test.key(27)
settings_test.build(); assert(settings_test.builds[#settings_test.builds].song_name=='Canção')
local zero_test=harness()
zero_test.click('4',1,2); zero_test.type('0'); zero_test.key(13)
assert(zero_test.build()=='Intro:4|Verse:8|Chorus:8|Ending:0')
zero_test.click('-',1,4)
assert(zero_test.build():match('Ending:0$'))
zero_test.click('+',1,4); assert(zero_test.build():match('Ending:1$'))
zero_test.click('-',1,4); assert(zero_test.build():match('Ending:0$'))
local zero_builds=#zero_test.builds
zero_test.click('Chorus',-1); zero_test.key(13)
zero_test.click('Build / Update song',-1)
assert(#zero_test.builds==zero_builds,'non-final zero length was accepted')
local variant_test=harness()
variant_test.click('Chorus',1) -- cancel menu
assert(variant_test.last_menu=='!Chorus|Chorus 1|Chorus 2|Chorus 10')
variant_test.menus={3}; variant_test.click('Chorus',1)
assert(variant_test.build()=='Intro:4|Verse:8|Chorus 2:8|Ending:4')
-- A drag on the same title still reorders without opening its menu.
local vx,vy=variant_test.find('Chorus 2',1)
variant_test.last_menu=nil
variant_test.gfx.mouse_x,variant_test.gfx.mouse_y,variant_test.gfx.mouse_cap=vx,vy,1; variant_test.frame()
variant_test.gfx.mouse_x,variant_test.gfx.mouse_y=26,variant_test.strip.y+50; variant_test.frame()
variant_test.gfx.mouse_cap=0; variant_test.frame(); variant_test.frame()
assert(variant_test.last_menu==nil)
assert(variant_test.build()=='Chorus 2:8|Intro:4|Verse:8|Ending:4')
-- Changing languages preserves a missing choice and blocks building until fixed.
variant_test.menus={2}; variant_test.click('EN',-1)
local variant_builds=#variant_test.builds
variant_test.click('Build / Update song',-1); assert(#variant_test.builds==variant_builds)
variant_test.menus={1}; variant_test.click('Chorus 2',1)
assert(variant_test.last_menu=='Chorus')
assert(variant_test.build()=='Chorus:8|Intro:4|Verse:8|Ending:4')
local h=harness()
-- One-bar increments support odd counts, and minus cannot go below one.
h.click('+',1); assert(h.build():match('^Intro:5|'))
h.click('-',1); assert(h.build():match('^Intro:4|'))
h.click('4',1); h.type('1'); h.key(13); h.click('-',1)
assert(h.build():match('^Intro:1|'))
h.click('1',1); h.type('0'); h.key(13)
local previous=#h.builds; h.click('Build / Update song',-1)
assert(#h.builds==previous,'invalid edit allowed a build')
h.key(27); assert(not h.closed)
h.click('1',1); h.type('17'); h.key(13)
assert(h.build():match('^Intro:17|'))
-- Clicking Build commits an unfinished valid edit before dispatch.
h.click('17',1); h.type('9')
assert(h.build():match('^Intro:9|'))
h.click('9',1); h.type('4'); h.key(13)
h=harness()
assert(#h.builds==0,'opening modified the project')
for _,d in ipairs(h.draws) do assert(d.value~='Chorus 1' and d.value~='Verse 2' and d.value~='2' and d.value~='Duplicate') end
h.click('Chorus',-1); h.type('8'); h.key(13)
assert(h.build()=='Intro:4|Verse:8|Chorus:8|Ending:4|Chorus:8')
-- Escape cancels inline edits without closing the window.
h.click('4',1); h.type('7'); h.key(27); assert(not h.closed)
assert(h.build()=='Intro:4|Verse:8|Chorus:8|Ending:4|Chorus:8')
-- Custom half-bar notation is retained exactly.
h.answers={'4.'}; h.click('Custom',1)
assert(h.build()=='Intro:4.|Verse:8|Chorus:8|Ending:4|Chorus:8')
-- First-to-last dragging preserves the section identity and length.
local x,y=h.find('Intro',1)
h.gfx.mouse_x,h.gfx.mouse_y,h.gfx.mouse_cap=x,y,1; h.frame()
h.gfx.mouse_x,h.gfx.mouse_y=1000,h.strip.y+50; h.frame()
h.gfx.mouse_cap=0; h.frame(); h.frame()
assert(h.build()=='Verse:8|Chorus:8|Ending:4|Chorus:8|Intro:4.')
-- Remove has precedence over dragging and only removes the chosen card.
h.click('x',1)
assert(h.build()=='Chorus:8|Ending:4|Chorus:8|Intro:4.')
-- Drag a palette item into the beginning; choose two bars.
x,y=h.find('Verse',-1)
h.gfx.mouse_x,h.gfx.mouse_y,h.gfx.mouse_cap=x,y,1; h.frame()
h.gfx.mouse_x,h.gfx.mouse_y=26,h.strip.y+50; h.frame()
h.gfx.mouse_cap=0; h.frame(); h.frame(); h.type('2'); h.key(13)
assert(h.build()=='Verse:2|Chorus:8|Ending:4|Chorus:8|Intro:4.')
-- Invalid settings do not reach the draft/builder.
h.click('120',-1); h.type('0'); h.key(13); h.key(27)
assert(h.builds[#h.builds].bpm==120)
local count=#h.builds
h.active='b'; h.frame(); h.click('Build / Update song',-1); assert(#h.builds==count)
h.active='a'; h.play=1; h.frame(); h.click('Build / Update song',-1); assert(#h.builds==count)
h.play=0; h.fail=true; h.frame(); h.click('Build / Update song',-1); assert(#h.dialogs>0)
-- Long songs support scrolling; narrow layouts retain an add menu.
h=harness()
for _=1,8 do h.click('Chorus',-1); h.key(13) end
h.gfx.mouse_x,h.gfx.mouse_y=500,h.strip.y+50
h.gfx.mouse_wheel=12000; h.frame(); h.frame()
assert(h.find('Intro',1))
h.gfx.w,h.gfx.h=620,800; h.frame()
-- Four fixture sections still fit as buttons; all controls fit within height.
for _,d in ipairs(h.draws) do if d.dest==-1 then assert(d.y<h.gfx.h,'control below window') end end
-- Unapplied draft close can be canceled, including reopening a closed window.
h.char=-1; h.confirm=7; h.frame(); h.char=0; h.frame(); assert(not h.closed)
h.char=27; h.confirm=6; h.frame(); assert(h.closed and #h.queue==0)
print('PASS: native editor — palette filtering, add, length, drag/reorder, removal, scrolling, build guards, error recovery, close handling.')
