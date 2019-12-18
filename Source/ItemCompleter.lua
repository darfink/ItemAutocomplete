select(2, ...) 'ItemCompleter'

-- Imports
local util = require 'Utility.Functions'

------------------------------------------
-- Class definition
------------------------------------------

local ItemCompleter = {}
ItemCompleter.__index = ItemCompleter

------------------------------------------
-- Constants
------------------------------------------

local const = {
  itemStartWeight = 10,
  itemIncrementWeight = 10,
}

------------------------------------------
-- Constructor
------------------------------------------

-- Creates a new item database
function ItemCompleter.New(persistence, itemDatabase)
  local self = setmetatable({}, ItemCompleter)

  self.itemWeights = persistence:GetGlobalItem('itemWeights')
  self.itemDatabase = itemDatabase
  return self
end

------------------------------------------
-- Public methods
------------------------------------------

function ItemCompleter:FindItems(text)
  local foundItems = {}
  local needle = text:lower()

  -- TODO: Implement smart casing
  for itemId, item in self.itemDatabase:ItemIterator() do
    if string.find(item.name:lower(), needle) then
      foundItems[#foundItems + 1] = item
    end
  end

  table.sort(foundItems, util.Bind(self, ItemCompleter._CompareItems))
  return util.Values(foundItems)
end

function ItemCompleter:SelectItem(itemId)
  self.itemWeights[itemId] = math.sqrt(
    math.pow(self.itemWeights[itemId] or const.itemStartWeight, 2) +
    math.pow(const.itemIncrementWeight, 2))
end

------------------------------------------
-- Private methods
------------------------------------------

function ItemCompleter:_CompareItems(itemA, itemB)
  local itemWeightA = self.itemWeights[itemA.id] or const.itemStartWeight
  local itemWeightB = self.itemWeights[itemB.id] or const.itemStartWeight

  -- Order by item weight first, then lexicographical order
  if itemWeightA ~= itemWeightB then
    return itemWeightA > itemWeightB
  else
    return itemA.name < itemB.name
  end
end

------------------------------------------
-- Exports
------------------------------------------

export.New = function(...) return ItemCompleter.New(...) end