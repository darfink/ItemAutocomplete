select(2, ...) 'ItemDatabase'

-- Imports
local algo = require 'Utility.Algo'
local util = require 'Utility.Functions'

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
  self.itemsById = persistence:GetGlobalItem('itemDatabase')
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
  if itemName ~= nil then
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

function ItemDatabase:FindItemsAsync(text, limit, callback)
  -- Only one item query may be running at a time, therefore replace any
  -- scheduled task since the result will most likely be obsolete when it's
  -- complete.
  self.taskScheduler:Dequeue(self.findItemsTaskId)

  self.findItemsTaskId = self.taskScheduler:Queue({
    onFinish = callback,
    task = function() return self:_TaskFindItems(text, limit, const.itemsSearchedPerUpdate) end,
  })
end

function ItemDatabase:UpdateItemsAsync(callback)
  if self:IsUpdating() then
    return
  end

  for _, itemId in ipairs(const.disjunctItemIds) do
    self:AddItemById(itemId)
  end

  self.updateItemsTaskId = self.taskScheduler:Queue({
    onFinish = callback,
    task = function() return self:_TaskUpdateItems(const.itemsQueriedPerUpdate) end,
  })
end

function ItemDatabase:IsEmpty()
  for _ in pairs(self.itemsById) do return false end
  return true
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

  return 1
end

function ItemDatabase:_TaskFindItems(text, limit, itemsPerYield)
  local limit = limit or 1 / 0
  local foundItems = {}
  local pattern = text:lower()
  local iterations = 0

  -- The following is a trade-off between execution time & memory. Adding all
  -- items to an array and sorting afterwards is O(nlogn), but requires a
  -- complete duplicate of the item database. A heap is good in theory but
  -- profiling shows it performs worst of all. The used solution is O(n²) due to
  -- the inner loop being O(n). Using binary search for the insertion point is
  -- also worse than insertion sort when a low 'limit' is used.
  for itemId, item in self:ItemIterator() do
    local startIndex, _, score = algo.FuzzyMatch(item.name, pattern, true)

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
    if iterations % itemsPerYield == 0 then
      coroutine.yield()
    end
  end

  -- Return an iterator over all items found
  local i = 0
  return function()
    i = i + 1;
    return foundItems[i] and foundItems[i].item
  end
end

------------------------------------------
-- Exports
------------------------------------------

export.New = function(...) return ItemDatabase.New(...) end