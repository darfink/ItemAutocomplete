select(2, ...) 'Utility.Functions'

-- Imports
local utf8 = require 'Shared.UTF8'

------------------------------------------
-- Constants
------------------------------------------

local addonName = select(1, ...)

------------------------------------------
-- Exports
------------------------------------------

-- Returns the addon's name
function export.GetAddonName()
  return addonName
end

-- Returns a field's value from the addon's meta data
function export.GetAddonMetadata(field)
  return GetAddOnMetadata(addonName, field)
end

-- Prints an addon message to the default chat frame
function export.PrettyPrint(...)
  local args = table.concat({...}, ' ')
  local message = string.format('|cFFFFA500[%s]|r: %s', addonName, args)
  DEFAULT_CHAT_FRAME:AddMessage(message)
end

-- Dumps a value to console
local function Dump(table, indent)
  if not indent then indent = 0 end
  for k, v in pairs(table) do
    local formatting = string.rep('  ', indent) .. k .. ': '
    if type(v) == 'table' then
      print(formatting)
      Dump(v, indent + 1)
    elseif type(v) == 'boolean' then
      print(formatting .. tostring(v))
    else
      print(formatting .. v)
    end
  end
end

export.Dump = Dump

-- Registers an in-game slash command
function export.RegisterSlashCommand(command, callback)
  local identifier = (addonName .. '_' .. command):upper()
  _G['SLASH_' .. identifier .. '1'] = '/' .. command
  _G.SlashCmdList[identifier] = callback
end

-- Hooks a global function and returns the original
function export.Hook(fn, detour)
  local original = _G[fn]
  _G[fn] = detour
  return original
end

-- Aborts the execution flow whilst suppressing any error
function export.Abort()
  local originalErrorHandler = geterrorhandler()
  seterrorhandler(function() seterrorhandler(originalErrorHandler) end)
  error('ABORT')
end

-- Returns true if a string is nil or empty
function export.IsNilOrEmpty(string)
  return string == nil or string == ''
end

-- Returns a read only version of a table
function export.ReadOnly(table)
  return setmetatable({}, {
    __index = table,
    __newindex = function() error('Attempt to modify read-only table') end,
    __metatable = false
  })
end

-- Returns a table which exposes context bound methods
function export.ContextBinder(context)
  return setmetatable({}, {
    __index = function (self, key)
      local method = context[key]

      if type(method) ~= 'function' then
        error('Unknown method ' .. key)
      end

      self[key] = function(...)
        return method(context, ...)
      end

      return rawget(self, key)
    end,
    __metatable = false,
  })
end

-- Returns whether a string contains uppercase or not
function export.ContainsUppercase(text)
  for _, codePoint in utf8.CodePoints(text) do
    if utf8.IsUpperCaseLetter(codePoint) then return true end
  end
  return false
end