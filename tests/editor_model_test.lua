local root=arg[1] or '.'
local M=dofile(root..'/autoTiazinhaEditorModel.lua')
local function equal(actual,expected) assert(actual==expected,tostring(actual)..' ~= '..tostring(expected)) end
local empty=M.new()
equal(M.settings(empty).song_structure_text,'')
equal(#empty.sections,0)
equal(empty.settings.is_double_click,false)
assert(#M.validate(empty,function() return true end,root..'/media/')>0)
equal(M.new({is_double_click='false'}).settings.is_double_click,false)
equal(M.new({is_double_click='true'}).settings.is_double_click,true)
local pending=M.add(empty,'Intro')
equal(pending.measures,'')
assert(#M.validate(empty,function() return true end,root..'/media/')>0)
assert(M.remove(empty,pending.id))
equal(#empty.sections,0)
local draft=M.new({song_structure_text='Intro:4|Verse:8|Chorus:8|Ending:4'})
local id=draft.sections[1].id
M.move(draft,id,5)
equal(M.settings(draft).song_structure_text,'Verse:8|Chorus:8|Ending:4|Intro:4')
M.move(draft,id,1)
equal(draft.sections[1].id,id)
equal(M.move(draft,id,2),false)
local bars,equivalent,half=M.length('4.2')
equal(bars,7); equal(equivalent,6.5); equal(half,true)
for _,bad in ipairs({'','-1','abc','4 2','0.','4.0'}) do equal(M.length(bad),nil) end
equal(M.length('0'),0)
local loaded=M.new({song_structure_text='Intro:.|Verse:4.2'})
equal(M.settings(loaded).song_structure_text,'Intro:.|Verse:4.2')
equal(M.summary(loaded),8)
local function exists(path) local f=io.open(path,'rb'); if f then f:close(); return true end; return false end
local media=root..'/media/'
local ending=M.new({song_structure_text='Intro:4|Ending:0'})
equal(#M.validate(ending,exists,media),0)
equal(M.summary(ending),4)
equal(M.settings(ending).song_structure_text,'Intro:4|Ending:0')
M.move(ending,ending.sections[2].id,1)
assert(#M.validate(ending,exists,media)>0)
M.move(ending,ending.sections[1].id,3)
M.add(ending,'Chorus','8')
assert(#M.validate(ending,exists,media)>0)
equal(#M.validate(draft,exists,media),0)
draft.sections[1].name='Missing cue'
assert(#M.validate(draft,exists,media)>0)
draft.sections[1].name='Intro'
draft.sections[1].measures='4.'
draft.settings.time_signature_numerator=3
assert(#M.validate(draft,exists,media)>0)
draft.settings.time_signature_numerator=4
equal(#M.validate(draft,exists,media),0)
draft.settings.bpm=0
assert(#M.validate(draft,exists,media)>0)
assert(not pcall(M.new,{song_structure_text='broken'}))
print('PASS: editor model — identity, reordering, structure round-trip, lengths, validation.')
