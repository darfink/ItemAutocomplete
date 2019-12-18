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

-- Returns a table's values
function export.Values(table)
  local i = 0
  return function() i = i + 1; return table[i] end
end
