------------------------------------------
-- Locals
------------------------------------------

local _, addonTable = ...
local environments = {}
local interfaces = {}
local func = {}
local empty = nil
local environmentMetaTable = { __index = _G }

------------------------------------------
-- Private methods
------------------------------------------

function func.pass() end

function func.require(name)
  if not interfaces[name] then
    createmodule(name)
  end

  return interfaces[name]
end

function func.createmodule(name)
  local exports = {}
  local environment = setmetatable({
    empty = empty,
    pass = func.pass,
    require = func.require,
  }, environmentMetaTable)

  environment.export = setmetatable({}, {
    __metatable = false,
    __newindex = function(_, k, v)
      environment[k], exports[k] = v, v
    end,
  })

  environment._M = environment
  environments[name] = environment
  interfaces[name] = setmetatable({}, { __metatable = false, __index = exports, __newindex = pass })
end

------------------------------------------
-- Initialization
------------------------------------------

-- Prevent any assignments to imported modules
empty = setmetatable({}, { __metatable = false, __newindex = func.pass })

-- This enables module declaration using: select(2, ...) '<name>'
setmetatable(addonTable, {
  __call = function(_, name)
    local defined = not not environments[name]
    if not defined then
      func.createmodule(name)
    end

    setfenv(2, environments[name])
    return defined
  end
})