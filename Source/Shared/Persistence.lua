select(2, ...) 'Shared.Persistence'

------------------------------------------
-- Class definition
------------------------------------------

local Persistence = {}
Persistence.__index = Persistence

------------------------------------------
-- Constructor
------------------------------------------

-- Returns the singleton persistence object
function Persistence.New(persistentTableName)
  assert(type(persistentTableName) == 'string')

  _G[persistentTableName] = _G[persistentTableName] or { items = {}, realms = {} }
  local persistentTable = _G[persistentTableName]

  local realm = GetRealmName()
  if persistentTable.realms[realm] == nil then
    persistentTable.realms[realm] = {
      characterItems = {},
      items = {},
    }
  end

  local self = setmetatable({}, Persistence)
  self.persistentTable = persistentTable
  self.persistentRealmTable = persistentTable.realms[realm]
  return self
end

------------------------------------------
-- Public methods
------------------------------------------

-- Gets a persistent entry for all realms
function Persistence:GetAccountItem(entryName, defaultValue)
  assert(entryName ~= nil)
  if self.persistentTable.items[entryName] == nil then
    self.persistentTable.items[entryName] = defaultValue or {}
  end

  return self.persistentTable.items[entryName]
end

-- Gets a persistent entry for the current realm
function Persistence:GetRealmItem(entryName, defaultValue)
  assert(entryName ~= nil)
  if self.persistentRealmTable.items[entryName] == nil then
    self.persistentRealmTable.items[entryName] = defaultValue or {}
  end

  return self.persistentRealmTable.items[entryName]
end

-- Gets a persistent entry for the current character
function Persistence:GetCharacterItem(entryName, defaultValue)
  assert(entryName ~= nil)

  local characterName = UnitName('player')
  if self.persistentRealmTable.characterItems[characterName] == nil then
    self.persistentRealmTable.characterItems[characterName] = {}
  end

  if self.persistentRealmTable.characterItems[characterName][entryName] == nil then
    self.persistentRealmTable.characterItems[characterName][entryName] = defaultValue or {}
  end

  return self.persistentRealmTable.characterItems[characterName][entryName]
end

------------------------------------------
-- Exports
------------------------------------------

export.New = function(...) return Persistence.New(...) end