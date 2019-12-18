select(2, ...) 'Main'

-- Imports
local EventSource = require 'Shared.EventSource'
local Persistence = require 'Shared.Persistence'
local ItemDatabase = require 'ItemDatabase'
local ItemCompleter = require 'ItemCompleter'
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
  local itemCompleter = ItemCompleter.New(persistence, itemDatabase)

  if itemDatabase:IsEmpty() then
    print('[ItemAutocomplete]: Updating item database')
    itemDatabase:UpdateItems()
  end

  util.RegisterSlashCommand('gl', function(text)
    for item in itemCompleter:FindItems(text) do
      print(item.link)
    end
  end)

  hooksecurefunc('ChatEdit_SendText', function(editBox, _)
    local text = editBox:GetText();
    local itemLinkPattern = "|Hitem:(%d+)[%-?%d:]+|h"

    for itemId in text:gmatch(itemLinkPattern) do
      itemCompleter:SelectItem(tonumber(itemId))
    end
  end)

  -- The search term is extracted from an unclosed brace (e.g '[Linen')
  function GetItemSearchTerm(text)
    for i = #text, 1, -1 do
      if text:byte(i) == string.byte(']') then return end

      if text:byte(i) == string.byte('[') then
        return text:sub(i + 1)
      end
    end
  end

  local selectedButtonIndex = 1
  local itemsFoundBySearch = 0

  local function SelectItemIndex(selectedIndex)
      local previousSelectedButton = _G['ItemAutocompleteButton' .. selectedButtonIndex]
      local currentlySelectedButton = _G['ItemAutocompleteButton' .. selectedIndex]
      selectedButtonIndex = selectedIndex

      previousSelectedButton:UnlockHighlight()
      currentlySelectedButton:LockHighlight()
  end

  hooksecurefunc('ChatEdit_OnTextChanged', function(editBox, isUserInput)
    if not isUserInput or itemDatabase:IsUpdating() then
      return
    end

    -- TODO: Use 'strmatch' instead
    local itemSearchTerm = GetItemSearchTerm(editBox:GetText())

    if itemSearchTerm ~= nil then
      local nextItem = itemCompleter:FindItems(itemSearchTerm)
      itemsFoundBySearch = 0

      for i = 1, 10 do
        local item = nextItem()
        local button = _G['ItemAutocompleteButton' .. i]

        if item ~= nil then
          itemsFoundBySearch = itemsFoundBySearch + 1
          button:SetText(item ~= nil and item.link or nil)
          button:Show()
        else
          button:Hide()
        end
      end

      if itemsFoundBySearch > 0 then
        if selectedButtonIndex > itemsFoundBySearch then
          SelectItemIndex(itemsFoundBySearch)
        end

        ItemAutocompleteFrame:ClearAllPoints()
        ItemAutocompleteFrame:SetPoint('BOTTOMLEFT', editBox, 'TOPLEFT', editBox.autoCompleteXOffset or 0, editBox.autoCompleteYOffset or -AUTOCOMPLETE_DEFAULT_Y_OFFSET)
        ItemAutocompleteFrame:Show()
      else
        ItemAutocompleteFrame:Hide()
      end
    else
      ItemAutocompleteFrame:Hide()
    end
  end)

  local originalAutoCompleteEditBoxOnEnterPressed = AutoCompleteEditBox_OnEnterPressed
  _G['AutoCompleteEditBox_OnEnterPressed'] = function(editBox)
    if ItemAutocompleteFrame:IsShown() and itemsFoundBySearch > 0 then
      local selectedButton = _G['ItemAutocompleteButton' .. selectedButtonIndex]
      local currentText = editBox:GetText()

      for i = #currentText, 1, -1 do
        if currentText:byte(i) == string.byte('[') then
          currentText = currentText:sub(1, i - 1)
          break
        end
      end

      editBox:SetText(currentText .. selectedButton:GetText())
      ItemAutocompleteFrame:Hide()
      return true
    end

    return originalAutoCompleteEditBoxOnEnterPressed(editBox)
  end

  local originalChatEditCustomTabPressed = ChatEdit_CustomTabPressed
  _G['ChatEdit_CustomTabPressed'] = function(editBox)
    if ItemAutocompleteFrame:IsShown() and itemsFoundBySearch > 0 then
      local newIndex = selectedButtonIndex + (IsShiftKeyDown() and -1 or 1)

      if newIndex < 1 then newIndex = itemsFoundBySearch end
      if newIndex > itemsFoundBySearch then newIndex = 1 end

      SelectItemIndex(newIndex)
      return true
    end

    return originalChatEditCustomTabPressed(editBox)
  end
end)