select(2, ...) 'Main'

-- Imports
local EventSource = require 'Shared.EventSource'
local Persistence = require 'Shared.Persistence'
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

  local persistence = Persistence.New(addonName .. 'DB')
  local itemDatabase = ItemDatabase.New(persistence, eventSource)
  local chatAutocompleteIntegrator = ChatAutocompleteIntegrator.New(itemDatabase)

  if itemDatabase:IsEmpty() then
    print('[ItemAutocomplete]: Updating item database')
    itemDatabase:UpdateItems()
  end

  util.RegisterSlashCommand('gl', function(text)
    for item in itemDatabase:FindItems(text) do
      print(item.link)
    end
  end)
end)