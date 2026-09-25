-- One pending Live-launched Native Editor session, shared through REAPER state.
local M = {}
local SECTION='AutoTiazinhaLiveEditor'

local function encode(value)
  return value:gsub('%%','%%25'):gsub('\r','%%0D'):gsub('\n','%%0A')
end
local function decode(value)
  return value:gsub('%%(%x%x)',function(hex) return string.char(tonumber(hex,16)) end)
end

function M.begin(mode, directory, api)
  api=api or reaper
  local token=api.genGuid('')
  api.SetExtState(SECTION,'request_token',token,false)
  api.SetExtState(SECTION,'request_mode',mode,false)
  api.SetExtState(SECTION,'request_directory',encode(directory or ''),false)
  api.DeleteExtState(SECTION,'result_token',false)
  return token
end

function M.take(api)
  api=api or reaper
  local token=api.GetExtState(SECTION,'request_token')
  if token=='' then return nil end
  local mode=api.GetExtState(SECTION,'request_mode')
  local directory=decode(api.GetExtState(SECTION,'request_directory'))
  api.DeleteExtState(SECTION,'request_token',false)
  api.DeleteExtState(SECTION,'request_mode',false)
  api.DeleteExtState(SECTION,'request_directory',false)
  return {token=token, mode=mode, directory=directory}
end

function M.pending(token, api)
  api=api or reaper
  return api.GetExtState(SECTION,'request_token')==token
end

function M.finish(context, path, built, api)
  api=api or reaper
  api.SetExtState(SECTION,'result_path',encode(path or ''),false)
  api.SetExtState(SECTION,'result_built',built and '1' or '0',false)
  api.SetExtState(SECTION,'result_token',context.token,false)
end

function M.poll(token, api)
  api=api or reaper
  if api.GetExtState(SECTION,'result_token')~=token then return nil end
  local result={path=decode(api.GetExtState(SECTION,'result_path')),
    built=api.GetExtState(SECTION,'result_built')=='1'}
  api.DeleteExtState(SECTION,'result_token',false)
  api.DeleteExtState(SECTION,'result_path',false)
  api.DeleteExtState(SECTION,'result_built',false)
  return result
end

function M.cancel(token, api)
  api=api or reaper
  if M.pending(token,api) then
    api.DeleteExtState(SECTION,'request_token',false)
    api.DeleteExtState(SECTION,'request_mode',false)
    api.DeleteExtState(SECTION,'request_directory',false)
  end
end

return M
