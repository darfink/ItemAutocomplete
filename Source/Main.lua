select(2, ...) 'Main'

-- Imports
local EventSource = require 'Shared.EventSource'
local Persistence = require 'Shared.Persistence'
local TaskScheduler = require 'Shared.TaskScheduler'
local ItemDatabase = require 'ItemDatabase'
local ChatAutocompleteIntegrator = require 'ChatAutocompleteIntegrator'
local util = require 'Utility.Functions'

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

  chatAutocompleteIntegrator:Enable()

  local updateItemDatabase = function()
    print('[ItemAutocomplete]: Updating item database')
    itemDatabase:UpdateItemsAsync(function()
      print('[ItemAutocomplete]: The database has been updated.')
    end)
  end

  if itemDatabase:IsEmpty() then
    updateItemDatabase()
  end

  util.RegisterSlashCommand('iaupdate', updateItemDatabase)
end)