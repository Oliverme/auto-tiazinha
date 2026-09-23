-- UI-independent draft model. The original builder remains the only generator.
local M = {}
local root_notes = {'C','Db','D','Eb','E','F','Gb','G','Ab','A','Bb','B'}
local valid_root_notes = {}
for _,note in ipairs(root_notes) do valid_root_notes[note]=true end
M.root_notes = root_notes

local defaults = {
  song_name='', bpm=120, time_signature_numerator=4,
  time_signature_denominator=4, cue_lang='EN', is_double_click=false,
  click_accent='', click_beat='', root_note='C',
}

function M.new(saved, is_saved_song)
  saved = saved or {}
  if is_saved_song == nil then
    is_saved_song = saved.song_name ~= nil and saved.song_name ~= false and saved.song_name ~= ''
  end
  local draft = {settings={}, sections={}, next_id=1}
  for k,v in pairs(defaults) do
    if saved[k] ~= nil and saved[k] ~= false then v = saved[k] end
    draft.settings[k] = v
  end
  draft.settings.is_double_click = saved.is_double_click == true or saved.is_double_click == 'true'
  if is_saved_song and (saved.root_note == nil or saved.root_note == false or saved.root_note == '') then
    draft.settings.root_note = nil
  end
  local structure = saved.song_structure_text
  if structure and structure ~= '' then
    for part in (structure .. '|'):gmatch('(.-)|') do
      local name, measures = part:match('^%s*(.-)%s*:%s*(.-)%s*$')
      if not name or name == '' then error('Cannot load song structure: ' .. part) end
      M.add(draft, name, measures)
    end
  end
  return draft
end

function M.add(draft, name, measures, position)
  -- A UI-created section is incomplete until its length is explicitly entered.
  -- Loaded sections always pass their saved length here.
  local card = {id=draft.next_id, name=name, measures=measures or ''}
  draft.next_id = draft.next_id + 1
  table.insert(draft.sections, position or #draft.sections+1, card)
  return card
end

function M.remove(draft, id)
  for i,card in ipairs(draft.sections) do
    if card.id == id then
      table.remove(draft.sections, i)
      return true
    end
  end
  return false
end

-- destination is an insertion gap in the original list: 1 = before first,
-- #sections+1 = after last. Identity stays stable throughout a drag.
function M.move(draft, id, destination)
  for i,card in ipairs(draft.sections) do
    if card.id == id then
      if destination == i or destination == i+1 then return false end
      table.remove(draft.sections, i)
      if destination > i then destination = destination-1 end
      table.insert(draft.sections, destination, card)
      return true
    end
  end
  return false
end

function M.settings(draft)
  local settings, parts = {}, {}
  for k,v in pairs(draft.settings) do settings[k]=v end
  for _,card in ipairs(draft.sections) do
    parts[#parts+1] = card.name .. ':' .. card.measures
  end
  settings.song_structure_text = table.concat(parts, '|')
  return settings
end

-- Preserve the builder's notation: each dot is a separate half-length bar,
-- not a decimal point ("4.2" = four bars, a half bar, then two bars).
function M.length(text)
  if text:match('^0+$') then return 0,0,false end
  local i, bars, equivalent, half = 1, 0, 0, false
  if text == '' then return nil end
  while i <= #text do
    if text:sub(i,i) == '.' then
      bars, equivalent, half, i = bars+1, equivalent+0.5, true, i+1
    else
      local token = text:sub(i):match('^%d+')
      local count = tonumber(token)
      if not count or count < 1 or count == math.huge then return nil end
      bars, equivalent, i = bars+count, equivalent+count, i+#token
    end
  end
  return bars, equivalent, half
end

function M.summary(draft)
  local bars, equivalent = 0, 0
  for _,card in ipairs(draft.sections) do
    local b,e = M.length(card.measures)
    if not b then return nil end
    bars, equivalent = bars+b, equivalent+e
  end
  return bars, equivalent
end

function M.validate(draft, exists, media_dir)
  local errors, s = {}, draft.settings
  local function add(text) errors[#errors+1]=text end
  if not s.song_name:match('%S') then add('Enter a song name.') end
  if s.song_name:find(',') then add('Song names cannot contain commas (dialog compatibility).') end
  if not tonumber(s.bpm) or s.bpm <= 0 or s.bpm == math.huge then add('BPM must be a positive number.') end
  local num, den = s.time_signature_numerator, s.time_signature_denominator
  if num < 1 or num % 1 ~= 0 or den < 1 or den % 1 ~= 0 then add('Choose a valid time signature.') end
  if s.root_note == nil or s.root_note == '' then
    add('Choose a root note.')
  elseif not valid_root_notes[s.root_note] then
    add('Choose a valid root note.')
  end
  if #draft.sections == 0 then add('Add at least one section.') end
  for i,card in ipairs(draft.sections) do
    local bars,_,half = M.length(card.measures)
    if bars==0 and i~=#draft.sections then add('Section '..i..': only the final section can have zero bars.') end
    if not bars then add('Section '..i..': use positive whole bars and dots, e.g. 8 or 4..') end
    if half and num % 2 ~= 0 then add('Section '..i..': half bars require an even numerator in this builder.') end
    if card.name:find('[|:,/\\]') or not exists(media_dir..s.cue_lang..'/'..card.name..'.wav') then
      add('Section '..i..': cue unavailable for '..card.name..' ('..s.cue_lang..').')
    end
  end
  for beat=2,math.min(num,6) do
    if not exists(media_dir..s.cue_lang..'/'..beat..'.wav') then add('Missing count cue: '..beat..' ('..s.cue_lang..').') end
  end
  if not exists(media_dir..s.cue_lang..'/1.wav') then
    add('Missing count cue: 1 ('..s.cue_lang..').')
  end
  for _,key in ipairs({'click_accent','click_beat'}) do
    if s[key] ~= '' and not exists(media_dir..'click/'..s[key]..'.wav') then add('Missing click sample: '..s[key]) end
  end
  return errors
end

return M
