select(2, ...) 'ItemDatabase'

-- Imports
local algo = require 'Utility.Algo'
local util = require 'Utility.Functions'

-- Consts
local const = {
  -- Find highest ID @ https://classic.wowhead.com/items?filter=151;2;24283
  highestItemId = 24283,
  itemsAddedPerUpdate = 50,
}

------------------------------------------
-- Class definition
------------------------------------------

local ItemDatabase = {}
ItemDatabase.__index = ItemDatabase

------------------------------------------
-- Constructor
------------------------------------------

-- Creates a new item database
function ItemDatabase.New(persistence, eventSource)
  local self = setmetatable({}, ItemDatabase)

  self.itemsById = persistence:GetGlobalItem('itemDatabase')
  self.isUpdating = false
  self.updateFrame = CreateFrame('Frame')
  self.eventSource = eventSource
  self.eventSource:AddListener('GET_ITEM_INFO_RECEIVED', util.Bind(self, self._OnItemInfoReceived))

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

function ItemDatabase:ItemIterator()
  return pairs(self.itemsById)
end

function ItemDatabase:FindItems(text, limit)
  local limit = limit or 1 / 0
  local foundItems = {}
  local pattern = text:lower()

  -- The following is a trade-off between execution time & memory. Adding all
  -- items to an array and sorting afterwards is O(nlogn), but requires a
  -- complete duplicate of the item database. A heap is good in theory but
  -- profiling shows it performs worst of all. The used solution is O(n²) due to
  -- the inner loop being O(n). Using binary search for the insertion point is
  -- also worse than insertion sort when a low 'limit' is used.
  for itemId, item in self:ItemIterator() do
    local startIndex, _, score = algo.FuzzyMatch(item.name, pattern, true)

    if startIndex > 0 then
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
  end

  -- Return an iterator over all items found
  local i = 0
  return function()
    i = i + 1;
    return foundItems[i] and foundItems[i].item
  end
end

function ItemDatabase:UpdateItems()
  if self.isUpdating then return end

  self.isUpdating = true
  self.currentItemId = 1
  self.updateFrame:SetScript('OnUpdate', util.Bind(self, self._OnUpdate))
end

function ItemDatabase:IsEmpty()
  for _ in pairs(self.itemsById) do return false end
  return true
end

function ItemDatabase:IsUpdating()
  return self.isUpdating
end

------------------------------------------
-- Private methods
------------------------------------------

function ItemDatabase:_OnUpdate()
  local upperItemId = min(const.highestItemId, self.currentItemId + const.itemsAddedPerUpdate)

  while self.currentItemId < upperItemId do
    if C_Item.DoesItemExistByID(self.currentItemId) then
      self:AddItemById(self.currentItemId)
    end

    self.currentItemId = self.currentItemId + 1
  end

  if self.currentItemId == const.highestItemId then
    self.updateFrame:SetScript('OnUpdate', nil)
    self.isUpdating = false

    -- TODO: Move this to event listener
    print('[ItemAutocomplete]: The database has been updated.')
  end
end

function ItemDatabase:_OnItemInfoReceived(itemId, success)
  if success then
    self:AddItemById(itemId)
  end
end

------------------------------------------
-- Exports
------------------------------------------

export.New = function(...) return ItemDatabase.New(...) end