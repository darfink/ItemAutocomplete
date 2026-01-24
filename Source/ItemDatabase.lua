select(2, ...) 'ItemDatabase'

-- Imports
local util = require 'Utility.Functions'
local utf8 = require 'Shared.UTF8'

-- Build the item id ranges for each version
local function AppendRanges(out, ranges)
  for i = 1, #ranges do
    out[#out + 1] = ranges[i]
  end
end

local baseRangesByExpansion = {
  -- See: https://classic.wowhead.com/items?filter=151;2;24284
  [_G.WOW_PROJECT_CLASSIC] = {
    { 1, 24283 }, -- Defaults
    { 122270 }, -- WoW Token (AH)
    { 122284 }, -- WoW Token
    { 172070 }, -- Customer Service Package
    { 180089 }, -- Panda Collar
    { 184937, 184938 }, -- Chronoboon Displacers
    { 189419, 189421 }, -- Fire Resist Gear
    { 189426, 189427 }, -- Raid Consumables
  },
  -- See: https://tbc.wowhead.com/items?filter=151;1;187815
  [_G.WOW_PROJECT_BURNING_CRUSADE_CLASSIC] = {
    { 1, 187815 }, -- Defaults
    { 190179, 190181 }, --  Incubus quest items
    { 190186, 190187 }, --  Incubus quest items
    { 190232 }, --  Incubus quest items
    { 190309 }, --  Incubus quest items
    { 190325 }, --  Incubus quest items
    { 190307, 190308 }, -- Fire festival torches
    { 191060 }, -- Magtheridon gems
    { 191061 }, -- Brilliant Glass
    { 209611, 209618 }, -- Insignia of the Alliance
    { 209619, 209626 }, -- Insignia of the Horde
    { 212160 }, -- Chronoboon Displacer
    { 234465 }, -- Reins of the Swift Spectral Tiger
    { 260221 }, -- Shop mounts/pets
    { 260433 }, -- Shop mounts/pets
    { 260438 }, -- Shop mounts/pets
    { 260622 }, -- Shop mounts/pets
    { 260759 }, -- Shop mounts/pets
    { 265826 }, -- Communal Keys
    { 265830 }, -- Communal Keys
    { 265843 }, -- Communal Keys
    { 265845 }, -- Communal Keys
    { 265847 }, -- Communal Keys
    { 265849 }, -- Communal Keys
    { 265851 }, -- Communal Keys
    { 265853 }, -- Communal Keys
  },
  -- See: https://www.wowhead.com/wotlk/items?filter=151;1;54798
  -- (The below list is likely incomplete)
  [_G.WOW_PROJECT_WRATH_CLASSIC] = {
    { 1, 54798 }, -- Defaults
    { 122270 }, -- WoW Token (AH)
    { 122284 }, -- WoW Token
    { 172070 }, -- Customer Service Package
    { 180089 }, -- Panda Collar
    { 192455 }, -- Elite Expedition Supplies
    { 198647 }, -- Elite Expedition Supplies
    { 198665 }, -- Elite Expedition Supplies
    { 198628, 198644 },
  },
}

local sodExtras = { { 190179, 217704 } }

local function BuildItemIdRanges()
  local ranges = {}
  AppendRanges(ranges, assert(baseRangesByExpansion[_G.WOW_PROJECT_ID]))
  if util.IsSod() then
    AppendRanges(ranges, sodExtras)
  end
  return ranges
end

-- Consts
local const = util.ReadOnly({ itemIds = BuildItemIdRanges(), itemsQueriedPerUpdate = 50 })

------------------------------------------
-- Class definition
------------------------------------------

local ItemDatabase = {}
ItemDatabase.__index = ItemDatabase

------------------------------------------
-- Constructor
------------------------------------------

-- Creates a new item database
function ItemDatabase.New(persistence, eventSource, taskScheduler)
  local self = setmetatable({}, ItemDatabase)

  self.methods = util.ContextBinder(self)
  self.eventSource = eventSource
  self.eventSource:AddListener('GET_ITEM_INFO_RECEIVED', self.methods._OnItemInfoReceived)
  self.itemsById = persistence:GetRealmItem('itemDatabase')
  self.databaseInfo = persistence:GetRealmItem('itemDatabaseInfo')
  self.taskScheduler = taskScheduler

  return self
end

------------------------------------------
-- Public methods
------------------------------------------

function ItemDatabase:AddItemById(itemId)
  local itemName, itemLink = GetItemInfo(itemId)

  -- The item info may not yet exist, in that case it's received asynchronously
  -- from the server via the GET_ITEM_INFO_RECEIVED event.
  if itemName ~= nil and not self:_IsDevItem(itemId, itemName) then
    -- Precalculate each code point to improve query performance
    local itemNameCodePoints = {}
    for _, codePoint in utf8.CodePoints(itemName) do
      itemNameCodePoints[#itemNameCodePoints + 1] = codePoint
    end

    self.itemsById[itemId] = { id = itemId, name = itemNameCodePoints, link = itemLink }
    return true
  else
    return false
  end
end

function ItemDatabase:GetItemById(itemId)
  return self.itemsById[itemId]
end

function ItemDatabase:UpdateItemsAsync(onFinish)
  if self:IsUpdating() then
    return
  end

  -- Reset the current database
  wipe(self.itemsById)
  self.databaseInfo.version = 0
  self.updateItemsTaskId = self.taskScheduler:Enqueue({
    onFinish = onFinish,
    task = function()
      return self:_TaskUpdateItems(const.itemsQueriedPerUpdate)
    end,
  })
end

function ItemDatabase:IsObsolete()
  local latestVersion = tonumber(util.GetAddonMetadata('X-ItemDatabaseVersion'))
  return (self.databaseInfo.version or 0) < latestVersion
end

function ItemDatabase:IsEmpty()
  return next(self.itemsById) == nil
end

function ItemDatabase:IsUpdating()
  return self.taskScheduler:IsScheduled(self.updateItemsTaskId)
end

function ItemDatabase:ItemIterator()
  return pairs(self:IsUpdating() and {} or self.itemsById)
end

------------------------------------------
-- Private methods
------------------------------------------

function ItemDatabase:_IsDevItem(itemId, itemName)
  local whitelistedIds = { 19971, 31716 }

  for _, whitelistedId in ipairs(whitelistedIds) do
    if itemId == whitelistedId then
      return false
    end
  end

  local devPatterns = {
    -- LuaFormatter off
    'Monster %-',
    'Monster,',
    'DEPRECATED',
    'Dep[rt][ie]cated',
    'DEP',
    'DEBUG',
    '%(old%d?%)',
    'OLD',
    '[ %(]test[%) ]',
    '^test ',
    'Testing ?%d?$',
    'Test[%u) ]',
    'Test$',
    'Test_',
    'TEST',
    '^test$',
    'UNUSED',
    '^Unused ',
    'PH',
    -- LuaFormatter on
  }

  for _, pattern in ipairs(devPatterns) do
    if itemName:match(pattern) then
      return true
    end
  end

  return false
end

function ItemDatabase:_OnItemInfoReceived(itemId, success)
  if success then
    self:AddItemById(itemId)
  end
end

function ItemDatabase:_TaskUpdateItems(itemsPerYield)
  local itemsProcessed = 0

  for _, range in ipairs(const.itemIds) do
    local lowId, highId = range[1], range[2] or range[1]

    for itemId = lowId, highId do
      if C_Item.DoesItemExistByID(itemId) then
        self:AddItemById(itemId)
      end

      itemsProcessed = itemsProcessed + 1

      if itemsProcessed % itemsPerYield == 0 then
        coroutine.yield()
      end
    end
  end

  self.databaseInfo.version = tonumber(util.GetAddonMetadata('X-ItemDatabaseVersion'))
  return 1
end

------------------------------------------
-- Exports
------------------------------------------

export.New = function(...)
  return ItemDatabase.New(...)
end
