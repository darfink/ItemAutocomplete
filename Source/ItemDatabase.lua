select(2, ...) 'ItemDatabase'

-- Imports
local util = require 'Utility.Functions'
local utf8 = require 'Shared.UTF8'

-- The item API moved into the 'C_Item' namespace, the globals were removed
-- from the modern clients (e.g. Classic Era 1.15.9 & Anniversary 2.5.6).
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant

-- Returns whether the client knows of an item or not
--
-- 'C_Item.DoesItemExistByID' cannot be used for this, it answers true for every
-- ID (WoWUIBugs #449). 'GetItemInfoInstant' reads the client's own item table
-- without a server round trip, so a nil result means there is nothing to add,
-- and no item query is sent for an ID that does not exist.
local function DoesItemExist(itemId)
  return GetItemInfoInstant(itemId) ~= nil
end

-- Returns the item ID ranges to scan for the current client
--
-- Every ID in these ranges is probed during a database update, so keep them as
-- tight as the client's item table allows. To refresh them after a patch, walk
-- 'GetItemInfoInstant' over 1..250000 in game and note where the results
-- cluster, that is the client's item table verbatim.
local function GetItemIdRanges()
  if util.IsWotlk() then
    -- See: https://www.wowhead.com/wotlk/items?filter=151;1;54798
    return {
      { 1, 54798 }, -- Defaults
      { 122270 }, -- WoW Token (AH)
      { 122284 }, -- WoW Token
      { 172070 }, -- Customer Service Package
      { 180089 }, -- Panda Collar
      { 192455, 198647, 198665 }, -- Elite Expedition Supplies
      { 198628, 198644 },
    }
  end

  if util.IsTbc() then
    -- Measured against the item table of the 2.5.6 Anniversary client
    return {
      { 1, 39656 }, -- Defaults
      { 43516 }, -- Brutal Nether Drake
      { 122270, 122284 }, -- WoW Token
      { 172070 }, -- Customer Service Package
      { 180089 }, -- Panda Collar
      { 184865, 187815 }, -- Burning Crusade Classic additions
      { 190179, 190325 }, -- Anniversary additions
      { 191060, 191061 },
      { 194101 }, -- Netherwhelp's Collar
      { 209611, 209626 }, -- Faction insignias
      { 212160 }, -- Chronoboon Displacer
      { 234465 }, -- Reins of the Swift Spectral Tiger
    }
  end

  -- Measured against the item table of the 1.15.9 Classic Era client
  local ranges = {
    { 1, 24358 }, -- Defaults
    { 122270, 122284 }, -- WoW Token
    { 172070 }, -- Customer Service Package
    { 180089 }, -- Panda Collar
    { 184937, 184938 }, -- Chronoboon Displacers
    { 189419, 189421 }, -- Fire Resist Gear
    { 189426, 189427 }, -- Raid Consumables
  }

  if util.IsSod() then
    -- Season of Discovery, which accounts for every remaining item the client
    -- knows of. These are only worth scanning on a seasonal realm.
    for _, range in ipairs({
      { 190179, 190325 },
      { 191204, 191666 },
      { 202251, 202641 },
      { 203723, 213737 },
      { 214435 },
      { 215111, 215824 },
      { 216483, 218117 },
      { 219021, 221981 },
      { 222952, 224912 },
      { 225675, 232652 },
      { 233197, 240217 },
      { 240742, 243345 },
      { 244353, 244460 },
      { 245675, 246062 },
    }) do
      ranges[#ranges + 1] = range
    end
  end

  return ranges
end

-- Consts
local const = util.ReadOnly({
  itemIds = GetItemIdRanges(),
  itemsQueriedPerUpdate = 50,
})

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
      if DoesItemExist(itemId) then
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
