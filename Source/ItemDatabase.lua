select(2, ...) 'ItemDatabase'

-- Imports
local util = require 'Utility.Functions'

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
--
-- A range ending at 'math.huge' is open-ended, it's scanned until no item has
-- been found for 'openRangeGap' IDs. This is used for retail, which adds items
-- every patch, and for any client that has no measured ranges.
local function GetItemIdRanges()
  if util.IsWotlk() then
    -- See: https://www.wowhead.com/wotlk/items?filter=151;1;54798
    return {
      { 1, 54798 }, -- Defaults
      { 122270 }, -- WoW Token (AH)
      { 122284 }, -- WoW Token
      { 172070 }, -- Customer Service Package
      { 180089 }, -- Panda Collar
      { 192455, 198647 }, -- Elite Expedition Supplies
      { 198665 },
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

  if not util.IsClassicEra() then
    -- Retail's item table exceeds 210000 entries, with IDs beyond 287000.
    -- Forever's (1.60.1) has 32000 entries between 17 and 289560, of which
    -- roughly 12700 are hidden until they drop for someone on the server.
    return { { 1, math.huge } }
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

-- Returns the key of the item database for the current client
--
-- Item names are the same on every realm of a client, but differ by locale,
-- and seasonal realms (e.g. Season of Discovery) have items of their own.
local function GetDatabaseKey()
  return table.concat({ _G.WOW_PROJECT_ID or 0, util.GetActiveSeason() or 0, GetLocale() }, ':')
end

-- Consts
local const = util.ReadOnly({
  -- Local existence checks per frame, these never reach the server
  itemsCheckedPerUpdate = 2000,
  -- An open-ended range ends after this many IDs without an item
  openRangeGap = 50000,
  -- The expected end of an open-ended range, used to estimate the progress
  openRangeEstimate = 300000,
  -- The server answers item queries at its own pace and silently drops them
  -- when flooded, so the number of queries awaiting an answer is capped. Some
  -- are never answered though (e.g. Forever's hidden items), thus a query only
  -- counts towards the cap until it's older than 'requestLiveTime'.
  requestLimit = { initial = 20, min = 5, max = 100, total = 1000 },
  requestLiveTime = 1,
  requestTimeout = 5,
  requestAttempts = 3,
  -- Unlike an item the server won't answer, a dropped query is answered once
  -- it's retried. The cap grows whilst queries are answered, and is halved
  -- when such retries exceed this share of the answers.
  requestDropShare = 0.1,
})

-- Returns the seconds until items the server refused or never answered are
-- queried again, which also happens after a patch
--
-- On Forever, hidden items become available as they drop on the server, so
-- these are checked daily.
local function GetUnavailableRecheckTime()
  return util.IsForever() and 86400 or 7 * 86400
end

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

  -- Databases used to be stored per realm, along with every item's link
  persistence:RemoveRealmItemFromAllRealms('itemDatabase')
  persistence:RemoveRealmItemFromAllRealms('itemDatabaseInfo')

  local databases = persistence:GetAccountItem('itemDatabases')
  local databaseKey = GetDatabaseKey()
  databases[databaseKey] = databases[databaseKey] or {}

  self.database = databases[databaseKey]
  self.database.names = self.database.names or {}
  self.database.qualities = self.database.qualities or {}
  self.database.unavailable = self.database.unavailable or {}
  self.buildNumber = util.GetBuildNumber()
  self.unavailableRecheckTime = GetUnavailableRecheckTime()

  -- A patch may make items available, only dev items stay excluded
  if self.database.build ~= nil and self.database.build ~= self.buildNumber then
    for itemId, unavailableSince in pairs(self.database.unavailable) do
      if unavailableSince ~= 0 then
        self.database.unavailable[itemId] = nil
      end
    end
  end

  self.itemIdRanges = GetItemIdRanges()
  self.itemIds = self:_CreateItemIdList()
  self.methods = util.ContextBinder(self)
  self.eventSource = eventSource
  self.eventSource:AddListener('GET_ITEM_INFO_RECEIVED', self.methods._OnItemInfoReceived)
  self.taskScheduler = taskScheduler
  self:_ResetRequests()

  return self
end

------------------------------------------
-- Public methods
------------------------------------------

function ItemDatabase:AddItemById(itemId)
  local itemName, _, itemQuality = GetItemInfo(itemId)

  -- The item info may not yet exist, in that case it's received asynchronously
  -- from the server via the GET_ITEM_INFO_RECEIVED event.
  if itemName == nil then
    return false
  end

  if self:_IsDevItem(itemId, itemName) then
    self.database.unavailable[itemId] = 0
    return false
  end

  local names = self.database.names
  if names[itemId] == nil then
    self.itemIds[#self.itemIds + 1] = itemId
  end

  names[itemId] = itemName
  self.database.qualities[itemId] = itemQuality
  self.database.unavailable[itemId] = nil
  return true
end

function ItemDatabase:GetItemName(itemId)
  return self.database.names[itemId]
end

-- Returns an item's link, preferably the one provided by the client
--
-- Links aren't stored since they're three times the size of a name, and on
-- retail they encode the current character. Asking for one also requests the
-- item info from the server, should it not be cached.
function ItemDatabase:GetItemLink(itemId)
  local _, itemLink = GetItemInfo(itemId)

  if itemLink ~= nil then
    return itemLink, true
  end

  local itemName = self.database.names[itemId] or tostring(itemId)
  local qualityColor = _G.ITEM_QUALITY_COLORS and
                         _G.ITEM_QUALITY_COLORS[self.database.qualities[itemId] or 1]
  local colorCode = qualityColor and qualityColor.hex or '|cffffffff'

  return string.format('%s|Hitem:%d::::::::|h[%s]|h|r', colorCode, itemId, itemName), false
end

function ItemDatabase:GetItemCount()
  return #self.itemIds
end

-- Returns the list of item IDs and their names, for searching
--
-- The list is only ever appended to whilst the database updates, so it can be
-- traversed by index across frames without being affected.
function ItemDatabase:GetSearchData()
  return self.itemIds, self.database.names
end

-- Updates the database in the background
--
-- By default, only items missing from the database are queried, which is
-- what's needed after a patch. A rebuild discards the database first.
function ItemDatabase:UpdateItemsAsync(rebuild, onFinish)
  if self:IsUpdating() then
    return false
  end

  if rebuild then
    -- Fresh tables are used, rather than wiping, since a running search may
    -- still be traversing the current ones.
    self.database.names = {}
    self.database.qualities = {}
    self.database.unavailable = {}
    self.database.scan = nil
    self.itemIds = {}
  end

  self.database.scan = self.database.scan or { version = self:_GetLatestVersion(), unresolved = {} }

  -- An update interrupted by a patch starts over, the patch may have added
  -- items it has already moved past. Known items are not queried again.
  local scan = self.database.scan
  if scan.build ~= self.buildNumber then
    scan.build = self.buildNumber
    scan.rangeIndex = 1
    scan.nextId = self.itemIdRanges[1][1]
    scan.highestId = 0
  end

  -- Requests left unanswered by a previous session are sent again, the scan
  -- has already moved past them. Their attempts carry over, otherwise items
  -- the server never answers would be queried anew after every reload.
  self:_ResetRequests()
  for itemId, attempts in pairs(scan.unresolved) do
    if attempts >= const.requestAttempts then
      self.database.unavailable[itemId] = GetServerTime()
      scan.unresolved[itemId] = nil
    else
      self.requestAttempts[itemId] = attempts
      self.requestRetries[#self.requestRetries + 1] = itemId
    end
  end
  self.updateItemsTaskId = self.taskScheduler:Enqueue({
    onFinish = onFinish,
    task = function()
      return self:_TaskUpdateItems()
    end,
  })

  return true
end

-- Returns whether the database was built by an incompatible version
function ItemDatabase:IsObsolete()
  local scan = self.database.scan
  local version = (scan and scan.version) or self.database.version or 0
  return version < self:_GetLatestVersion()
end

-- Returns whether the database is incomplete, predates the client's build, or
-- has unavailable items due to be queried again
function ItemDatabase:IsOutdated()
  return self:IsEmpty() or self.database.scan ~= nil or self.database.build ~= self.buildNumber or
           GetServerTime() - (self.database.checkedAt or 0) > self.unavailableRecheckTime
end

function ItemDatabase:IsEmpty()
  return next(self.database.names) == nil
end

function ItemDatabase:IsUpdating()
  return self.taskScheduler:IsScheduled(self.updateItemsTaskId)
end

-- Returns how far the current update has come, between 0 and 1
function ItemDatabase:GetUpdateProgress()
  local scan = self.database.scan

  if scan == nil then
    return 1
  end

  local scanned, total = 0, 0
  for index, range in ipairs(self.itemIdRanges) do
    local lowId, highId = range[1], self:_GetRangeEnd(range, scan)
    local size = (range[2] == math.huge and math.max(highId, const.openRangeEstimate) or highId) -
                   lowId + 1

    total = total + size
    if index < scan.rangeIndex then
      scanned = scanned + size
    elseif index == scan.rangeIndex then
      scanned = scanned + math.max(0, math.min(scan.nextId, highId + 1) - lowId)
    end
  end

  -- The end of an open-ended range moves as items are found, the progress
  -- shouldn't move backwards because of it.
  self.updateProgress = math.max(self.updateProgress or 0, total > 0 and scanned / total or 1)
  return self.updateProgress
end

------------------------------------------
-- Private methods
------------------------------------------

function ItemDatabase:_GetLatestVersion()
  return tonumber(util.GetAddonMetadata('X-ItemDatabaseVersion'))
end

function ItemDatabase:_CreateItemIdList()
  local itemIds = {}

  for itemId in pairs(self.database.names) do
    itemIds[#itemIds + 1] = itemId
  end

  table.sort(itemIds)
  return itemIds
end

function ItemDatabase:_ResetRequests()
  self.pendingRequests = {}
  self.pendingRequestCount = 0
  self.requestAttempts = {}
  self.requestRetries = {}
  self.retriedRequests = {}
  self.liveRequests = {}
  self.liveRequestCount = 0
  self.requestLimit = const.requestLimit.initial
  self.requestWindow = { startedAt = GetTime(), answered = 0, retriesAnswered = 0 }
  self.updateProgress = nil
end

function ItemDatabase:_GetRangeEnd(range, scan)
  local highId = range[2] or range[1]

  if highId == math.huge then
    -- The previous update's highest ID is included, it's known to exist
    return math.max(range[1], scan.highestId, self.database.highestId or 0) + const.openRangeGap
  end

  return highId
end

-- Returns the next item ID to probe, or nil once every range is exhausted
function ItemDatabase:_AdvanceScan(scan)
  local range = self.itemIdRanges[scan.rangeIndex]

  while range ~= nil do
    if scan.nextId <= self:_GetRangeEnd(range, scan) then
      local itemId = scan.nextId
      scan.nextId = itemId + 1
      return itemId
    end

    scan.rangeIndex = scan.rangeIndex + 1
    range = self.itemIdRanges[scan.rangeIndex]
    scan.nextId = range and range[1]
  end

  return nil
end

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
    '^zz',
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
  if self.pendingRequests[itemId] == nil then
    -- The client also receives info of items encountered in the world
    if success then
      self:AddItemById(itemId)
    end
    return
  end

  -- The info may arrive before it can be read, in that case the request times
  -- out and is sent again.
  if success and not self:AddItemById(itemId) and not self.database.unavailable[itemId] then
    return
  end

  -- A false success means the server refuses to return the item, and nil that
  -- it does not exist. Neither is worth asking again until it's rechecked.
  if not success then
    self.database.unavailable[itemId] = GetServerTime()
  end

  local window = self.requestWindow
  window.answered = window.answered + 1
  if self.retriedRequests[itemId] then
    window.retriesAnswered = window.retriesAnswered + 1
  end

  self:_CompleteRequest(itemId)
  self:_ResolveRequest(itemId)
  self.requestLimit = math.min(const.requestLimit.max, self.requestLimit + 1 / self.requestLimit)
end

function ItemDatabase:_CompleteRequest(itemId)
  self:_EndLiveRequest(itemId)
  self.pendingRequests[itemId] = nil
  self.pendingRequestCount = self.pendingRequestCount - 1
  self.requestAttempts[itemId] = nil
  self.retriedRequests[itemId] = nil
end

function ItemDatabase:_EndLiveRequest(itemId)
  if self.liveRequests[itemId] then
    self.liveRequests[itemId] = nil
    self.liveRequestCount = self.liveRequestCount - 1
  end
end

-- Marks an item as settled, it won't be requested again by this update
function ItemDatabase:_ResolveRequest(itemId)
  local scan = self.database.scan

  if scan ~= nil then
    scan.unresolved[itemId] = nil
  end
end

-- Returns whether an item is not worth requesting
--
-- Dev items are excluded until a rebuild, whilst items the server refused or
-- never answered are requested again once they're due.
function ItemDatabase:_IsUnavailable(itemId)
  local unavailableSince = self.database.unavailable[itemId]

  if unavailableSince == nil then
    return false
  end

  return unavailableSince == 0 or GetServerTime() - unavailableSince < self.unavailableRecheckTime
end

function ItemDatabase:_ExpireRequests()
  local now = GetTime()

  for itemId, requestedAt in pairs(self.pendingRequests) do
    local age = now - requestedAt

    if age > const.requestTimeout then
      local attempts = self.requestAttempts[itemId]
      self:_CompleteRequest(itemId)

      if attempts < const.requestAttempts then
        self.requestAttempts[itemId] = attempts
        self.requestRetries[#self.requestRetries + 1] = itemId
      else
        -- The server won't answer, e.g. an item hidden on Forever
        self.database.unavailable[itemId] = GetServerTime()
        self:_ResolveRequest(itemId)
      end
    elseif age > const.requestLiveTime then
      self:_EndLiveRequest(itemId)
    end
  end

  -- Dropped queries are answered on retry, which happens a timeout later, so
  -- the cap is decreased at most once per timeout.
  local window = self.requestWindow
  if now - window.startedAt > const.requestTimeout then
    if window.retriesAnswered > const.requestDropShare * window.answered then
      self.requestLimit = math.max(const.requestLimit.min, self.requestLimit / 2)
    end

    self.requestWindow = { startedAt = now, answered = 0, retriesAnswered = 0 }
  end
end

-- Requests an item's info from the server, if it's missing from the database
function ItemDatabase:_RequestItem(itemId, scan)
  local isKnown = self.database.names[itemId] ~= nil or self:_IsUnavailable(itemId)

  if not isKnown and not DoesItemExist(itemId) then
    self:_ResolveRequest(itemId)
    return
  end

  -- Known items count as well, otherwise an update would end prematurely
  scan.highestId = math.max(scan.highestId, itemId)

  -- Ranges may overlap, an item can thus be reached whilst it's pending
  if self.pendingRequests[itemId] ~= nil then
    return
  end

  if isKnown then
    self:_ResolveRequest(itemId)
    return
  end

  -- An item due for a recheck is only queried once, most will still be
  -- unavailable and shouldn't hold up the update. Missing one only delays it
  -- until the next recheck.
  if self.database.unavailable[itemId] ~= nil and self.requestAttempts[itemId] == nil then
    self.requestAttempts[itemId] = const.requestAttempts - 1
  end

  self.database.unavailable[itemId] = nil

  if self:AddItemById(itemId) or self.database.unavailable[itemId] then
    self:_ResolveRequest(itemId)
    return false
  end

  self.pendingRequests[itemId] = GetTime()
  self.pendingRequestCount = self.pendingRequestCount + 1
  self.liveRequests[itemId] = true
  self.liveRequestCount = self.liveRequestCount + 1
  self.requestAttempts[itemId] = (self.requestAttempts[itemId] or 0) + 1
  scan.unresolved[itemId] = self.requestAttempts[itemId]
  return true
end

function ItemDatabase:_TaskUpdateItems()
  local scan = self.database.scan
  local isExhausted = false

  while not isExhausted or self.pendingRequestCount > 0 or #self.requestRetries > 0 do
    self:_ExpireRequests()

    -- Item queries are held back during combat to not compete for bandwidth
    if not InCombatLockdown() then
      local checks = 0

      while checks < const.itemsCheckedPerUpdate and self.liveRequestCount <
        math.floor(self.requestLimit) and self.pendingRequestCount < const.requestLimit.total do
        local retryId = table.remove(self.requestRetries)
        local itemId = retryId or self:_AdvanceScan(scan)

        if itemId == nil then
          isExhausted = true
          break
        end

        if self:_RequestItem(itemId, scan) and retryId ~= nil then
          self.retriedRequests[itemId] = true
        end

        checks = checks + 1
      end
    end

    coroutine.yield()
  end

  self.database.scan = nil
  self.database.checkedAt = GetServerTime()
  self.database.highestId = scan.highestId
  self.database.version = scan.version
  self.database.build = util.GetBuildNumber()
  return self:GetItemCount()
end

------------------------------------------
-- Exports
------------------------------------------

export.New = function(...)
  return ItemDatabase.New(...)
end
