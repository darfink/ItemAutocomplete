select(2, ...) 'Main'

-- Imports
local AceConfig = LibStub('AceConfig-3.0')
local AceConfigDialog = LibStub('AceConfigDialog-3.0')
local EventSource = require 'Shared.EventSource'
local Persistence = require 'Shared.Persistence'
local TaskScheduler = require 'Shared.TaskScheduler'
local ItemDatabase = require 'ItemDatabase'
local ChatAutocompleteIntegrator = require 'ChatAutocompleteIntegrator'
local util = require 'Utility.Functions'

------------------------------------------
-- Private functions
------------------------------------------

local function RegisterOptions(addonName, persistence, config)
  local options = persistence:GetAccountItem('options')
  for name, input in pairs(config) do
    local originalSetter = input.set
    input.get = function() return options[name] end
    input.set = function(_, value)
      options[name] = value
      originalSetter(value)
    end

    options[name] = options[name] or input.default
    originalSetter(options[name])
    input.default = nil
  end

  AceConfig:RegisterOptionsTable(addonName, { type = 'group', args = config })
  AceConfigDialog:AddToBlizOptions(addonName)
end

------------------------------------------
-- Bootstrap
------------------------------------------

local eventSource = EventSource.New()

eventSource:AddListener('ADDON_LOADED', function (addonName)
  if addonName ~= util.GetAddonName() then
    return
  end

  local taskScheduler = TaskScheduler.New()
  local persistence = Persistence.New(addonName .. 'DB')
  local itemDatabase = ItemDatabase.New(persistence, eventSource, taskScheduler)
  local chatAutocompleteIntegrator = ChatAutocompleteIntegrator.New(itemDatabase)

  local updateItemDatabase = function()
    util.PrettyPrint('Updating item database')
    itemDatabase:UpdateItemsAsync(function()
      util.PrettyPrint('The database has been updated.')
    end)
  end

  if itemDatabase:IsEmpty() or itemDatabase:IsObsolete() then
    updateItemDatabase()
  end

  local config = chatAutocompleteIntegrator:Config()
  chatAutocompleteIntegrator:Enable()

  RegisterOptions(addonName, persistence, config)
  util.RegisterSlashCommand('iaupdate', updateItemDatabase)
end)