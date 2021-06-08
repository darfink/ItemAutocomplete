select(2, ...) 'Main'

-- Imports
local AceConfig = LibStub('AceConfig-3.0')
local AceConfigDialog = LibStub('AceConfigDialog-3.0')
local ChatAutocompleteIntegrator = require 'ChatAutocompleteIntegrator'
local EventSource = require 'Shared.EventSource'
local ItemDatabase = require 'ItemDatabase'
local CompletionSource = require 'CompletionSource'
local Persistence = require 'Shared.Persistence'
local TaskScheduler = require 'Shared.TaskScheduler'
local util = require 'Utility.Functions'

------------------------------------------
-- Private locals
------------------------------------------

local function RegisterConfigDefinition(persistence, configDefinition)
  local options = persistence:GetAccountItem('options')
  local mappers = {}

  for name, definition in pairs(configDefinition) do
    if definition.type ~= 'header' and definition.type ~= 'description' then
      options[name] = options[name] or definition.default
      mappers[name] = definition.map

      -- Remove these to conform to the AceConfig interface
      definition.default = nil
      definition.map = nil
    end
  end

  local addonName = util.GetAddonName()
  local addonTitle = util.GetAddonMetadata('Title')
  local optionsTable = {
    type = 'group',
    name = addonTitle .. ' (' .. util.GetAddonMetadata('Version') .. ')',
    args = configDefinition,
    get = function(info)
      return options[info[#info]]
    end,
    set = function(info, value)
      options[info[#info]] = value
    end,
  }

  AceConfig:RegisterOptionsTable(addonName, optionsTable)
  AceConfigDialog:AddToBlizOptions(addonName, addonTitle)

  return setmetatable({}, {
    __index = function(_, key)
      if mappers[key] ~= nil then
        return mappers[key](options[key])
      else
        return options[key]
      end
    end,
    __newindex = function()
      error('Attempt to modify user option')
    end,
    __metatable = false,
  })
end

local configDefinition = {
  descriptionIntro = {
    type = 'description',
    order = 0,
    name = table.concat({
      'Created by |cff00ccff' .. util.GetAddonMetadata('Author') .. '|r',
      util.GetAddonMetadata('Notes'),
    }, '|n|n'),
    fontSize = 'medium',
  },
  headerInteraction = { type = 'header', order = 1, name = 'Interaction' },
  descriptionTrigger = {
    type = 'description',
    order = 1.3,
    name = '|cffff8888NOTE: Changing the item completion trigger requires an interface reload to take effect.|r',
  },
  caseInsensitive = {
    type = 'select',
    order = 1.1,
    values = { 'Smart case', 'Case-insensitive', 'Case-sensitive' },
    style = 'dropdown',
    name = 'Case sensitivity',
    desc = 'Specify the case sensitivity when searching.',
    default = 1,
    map = function(index)
      return ({ nil, true, false })[index]
    end,
  },
  itemCompletionTrigger = {
    type = 'select',
    order = 1.2,
    values = {
      ['<'] = 'Angle bracket — <',
      ['{'] = 'Curly bracket — {',
      ['['] = 'Square bracket — [',
      ['('] = 'Parenthesis — (',
    },
    style = 'dropdown',
    name = 'Item completion trigger',
    desc = 'Specify the character used to trigger item link completion.',
    default = '[',
    map = function(value)
      return string.byte(value)
    end,
  },
  headerQuery = { type = 'header', order = 2, name = 'Query' },
  entriesFilteredPerUpdate = {
    type = 'range',
    order = 2.1,
    min = 1,
    max = 100000,
    softMin = 100,
    softMax = 10000,
    bigStep = 100,
    name = 'Items searched per frame',
    desc = 'Specify the number of items filtered per frame. ' ..
      'A higher number will yield faster results, but cause a greater performance impact.',
    default = 2000,
  },
  entriesDisplayed = {
    type = 'range',
    order = 2.2,
    min = 1,
    max = 30,
    bigStep = 1,
    name = 'Items displayed',
    desc = 'Specify the number of items displayed. ' ..
      'A higher number will cause a greater performance impact.',
    default = 10,
    map = function(value)
      return math.floor(value)
    end,
  },
}

------------------------------------------
-- Bootstrap
------------------------------------------

local eventSource = EventSource.New()

eventSource:AddListener('ADDON_LOADED', function(addonName)
  if addonName ~= util.GetAddonName() then
    return
  end

  local taskScheduler = TaskScheduler.New()
  local persistence = Persistence.New(addonName .. 'DB')
  local itemDatabase = ItemDatabase.New(persistence, eventSource, taskScheduler)
  local config = RegisterConfigDefinition(persistence, configDefinition)

  local itemCompletionSource = CompletionSource.New(itemDatabase.methods.ItemIterator,
                                                    taskScheduler, config)

  -- Override tooltip setup to provide additional item information
  function itemCompletionSource:SetupTooltip(tooltip, entry)
    tooltip:SetItemByID(entry.id)
  end

  local updateItemDatabase = function()
    util.PrettyPrint('Updating item database')
    itemDatabase:UpdateItemsAsync(function()
      util.PrettyPrint('The database has been updated.')
    end)
  end

  -- Allow users to manually update the item database
  util.RegisterSlashCommand('iaupdate', updateItemDatabase)

  -- Bootstrapping complete - enable chat integration
  local chatAutocompleteIntegrator = ChatAutocompleteIntegrator.New()
  chatAutocompleteIntegrator:AddCompletionSource(config.itemCompletionTrigger, itemCompletionSource)
  chatAutocompleteIntegrator:Enable()

  if itemDatabase:IsEmpty() or itemDatabase:IsObsolete() then
    C_Timer.After(5, updateItemDatabase)
  end
end)
