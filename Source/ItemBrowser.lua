select(2, ...) 'ItemBrowser'

-- Imports
local util = require 'Utility.Functions'

-- Consts
local const = {
  itemStartWeight = 10,
  itemIncrementWeight = 10,
}

------------------------------------------
-- Class definition
------------------------------------------

local ItemBrowser = {}
ItemBrowser.__index = ItemBrowser

------------------------------------------
-- Constructor
------------------------------------------

-- Creates a new item browser
function ItemBrowser.New(persistence, itemDatabase)
  local self = setmetatable({}, ItemBrowser)

  self.itemWeights = persistence:GetGlobalItem('itemWeights')
  self.itemDatabase = itemDatabase
  return self
end

------------------------------------------
-- Public methods
------------------------------------------

function ItemBrowser:FindItems(text, limit)
  local foundItems = {}
  local needle = text:lower()

  -- TODO: Implement smart casing
  for itemId, item in self.itemDatabase:ItemIterator() do
    if string.find(item.name:lower(), needle) then
      foundItems[#foundItems + 1] = item
    end
  end

  table.sort(foundItems, util.Bind(self, ItemBrowser._CompareItems))

  -- TODO: Implement limit properly
  if limit ~= nil then
    foundItems[limit + 1] = nil
  end

  return util.Values(foundItems)
end

function ItemBrowser:SelectItem(itemId)
  self.itemWeights[itemId] = math.sqrt(
    math.pow(self.itemWeights[itemId] or const.itemStartWeight, 2) +
    math.pow(const.itemIncrementWeight, 2))
end

------------------------------------------
-- Private methods
------------------------------------------

function ItemBrowser:_CompareItems(itemA, itemB)
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

export.New = function(...) return ItemBrowser.New(...) end