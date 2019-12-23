select(2, ...) 'Utility.Functions'

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

-- Binds one argument to a function
function export.Bind(context, callee)
  assert(type(callee) == 'function', 'Callee must be a function')

  return function(...)
    return callee(context, ...)
  end
end

-- Dumps a value to console
function Dump(table, indent)
  if not indent then indent = 0 end
  for k, v in pairs(table) do
    formatting = string.rep('  ', indent) .. k .. ': '
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

-- Returns whether a string is nil or empty
function export.IsNilOrEmpty(string)
  return string == nil or string == ''
end

-- Returns the binary insertion point for a value in a sorted array
function export.BinaryInsertionPoint(table, value, comparator)
  local lower, upper, mid, state = 1, #table, 1, 0

  while lower <= upper do
    mid = math.floor((lower + upper) / 2)

    if comparator(value, table[mid]) then
      upper, state = mid - 1, 0
    else
      lower, state = mid + 1, 1
    end
  end

  return mid + state
end