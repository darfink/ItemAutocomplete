select(2, ...) 'ItemDatabase'

-- Imports
local util = require 'Utility.Functions'
local FuzzyMatcher = require 'Utility.FuzzyMatcher'

-- Consts
local const = util.ReadOnly({
  -- Find highest ID @ https://classic.wowhead.com/items?filter=151;2;24283
  disjunctItemIds = {172070},
  highestItemId = 24283,
  itemsQueriedPerUpdate = 50,
  itemsSearchedPerUpdate = 1000,
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
  self.itemsById = persistence:GetAccountItem('itemDatabase')
  self.databaseInfo = persistence:GetAccountItem('itemDatabaseInfo')
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
    self.itemsById[itemId] = {
      id = itemId,
      name = itemName,
      link = itemLink,
    }
    return true
  else
    return false
  end
end

function ItemDatabase:GetItemById(itemId)
  return self.itemsById[itemId]
end

function ItemDatabase:FindItemsAsync(options, callback)
  -- This is a balance between responsiveness and frame drops
  options.itemsPerYield = const.itemsSearchedPerUpdate

  -- Only one item query may be running at a time, therefore replace any
  -- scheduled task since the result will most likely be obsolete when it's
  -- complete.
  self.taskScheduler:Dequeue(self.findItemsTaskId)

  self.findItemsTaskId = self.taskScheduler:Queue({
    onFinish = callback,
    task = function() return self:_TaskFindItems(options) end,
  })
end

function ItemDatabase:UpdateItemsAsync(callback)
  if self:IsUpdating() then return end

  wipe(self.itemsById)
  for _, itemId in ipairs(const.disjunctItemIds) do
    self:AddItemById(itemId)
  end

  self.updateItemsTaskId = self.taskScheduler:Queue({
    onFinish = callback,
    task = function() return self:_TaskUpdateItems(const.itemsQueriedPerUpdate) end,
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
  return pairs(self.itemsById)
end

------------------------------------------
-- Private methods
------------------------------------------

function ItemDatabase:_IsDevItem(itemId, itemName)
  if itemId == 19971 then return false end
  if itemName:match('Monster %-') then return true end
  if itemName:match('DEPRECATED') then return true end
  if itemName:match('Dep[rt][ie]cated') then return true end
  if itemName:match('DEP') then return true end
  if itemName:match('DEBUG') then return true end
  if itemName:match('%(old%d?%)') then return true end
  if itemName:match('OLD') then return true end
  if itemName:match('[ %(]test[%) ]') then return true end
  if itemName:match('^test ') then return true end
  if itemName:match('Testing ?%d?$') then return true end
  if itemName:match('Test[%u) ]') then return true end
  if itemName:match('Test$') then return true end
  if itemName:match('TEST') then return true end
  if itemName == 'test' then return true end
  return false
end

function ItemDatabase:_OnItemInfoReceived(itemId, success)
  if success then
    self:AddItemById(itemId)
  end
end

function ItemDatabase:_TaskUpdateItems(itemsPerYield)
  for itemId = 1, const.highestItemId do
    if C_Item.DoesItemExistByID(itemId) then
      self:AddItemById(itemId)
    end

    if itemId % itemsPerYield == 0 then
      coroutine.yield(itemId / const.highestItemId)
    end
  end

  self.databaseInfo.version = tonumber(util.GetAddonMetadata('X-ItemDatabaseVersion'))
  return 1
end

function ItemDatabase:_TaskFindItems(options)
  local limit = options.limit or 1 / 0
  local caseInsensitive = options.caseInsensitive

  if caseInsensitive == nil then
    -- Use smart case (i.e only check casing if the pattern contains uppercase letters)
    caseInsensitive = not util.ContainsUppercase(options.pattern)
  end

  local fuzzyMatcher = FuzzyMatcher.New(options.pattern, caseInsensitive)
  local foundItems = {}
  local iterations = 0

  -- The following is a trade-off between execution time & memory. Adding all
  -- items to an array and sorting afterwards is O(nlogn), but requires a
  -- complete duplicate of the item database. A heap is good in theory but
  -- profiling shows it performs worst of all. The used solution is O(n²) due to
  -- the inner loop being O(n). Using binary search for the insertion point is
  -- also worse than insertion sort when a low 'limit' is used.
  for _, item in self:ItemIterator() do
    local startIndex, _, score = fuzzyMatcher:Match(item.name)

    if startIndex ~= 0 then
      local insertionPoint = #foundItems + 1
      while insertionPoint > 1 and score > foundItems[insertionPoint - 1].score do
        insertionPoint = insertionPoint - 1
      end

      if insertionPoint < limit then
        table.insert(foundItems, insertionPoint, { item = item, score = score })

        if #foundItems > limit then
          foundItems[#foundItems] = nil
        end
      end
    end

    iterations = iterations + 1
    if iterations % options.itemsPerYield == 0 then
      coroutine.yield()
    end
  end

  -- Return an iterator over all items found
  local i = 0
  return function()
    i = i + 1
    return foundItems[i] and foundItems[i].item
  end
end

------------------------------------------
-- Exports
------------------------------------------

export.New = function(...) return ItemDatabase.New(...) end