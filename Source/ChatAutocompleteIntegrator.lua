select(2, ...) 'ChatAutocompleteIntegrator'

-- Imports
local util = require 'Utility.Functions'

-- Consts
local const = util.ReadOnly({ maxItems = 10 })

------------------------------------------
-- Class definition
------------------------------------------

local ChatAutocompleteIntegrator = {}
ChatAutocompleteIntegrator.__index = ChatAutocompleteIntegrator

------------------------------------------
-- Constructor
------------------------------------------

-- Creates a chat autocomplete menu
function ChatAutocompleteIntegrator.New(itemDatabase)
  local self = setmetatable({}, ChatAutocompleteIntegrator)

  self.caseInsensitive = nil
  self.editBoxCursorOffsets = {}
  self.itemDatabase = itemDatabase
  self.methods = util.ContextBinder(self)
  self.searchCursorOffsetX = nil
  self:SetItemLinkDelimiters('[', ']')

  -- The visual menu to select item links
  self.buttonMenu = CreateFrame('Frame', nil, UIParent, 'ItemAutocompleteButtonMenuTemplate')
  self.buttonMenu:SetFrameLevel(10)
  self.buttonMenu:Hide()

  -- An invisible frame to intercept key inputs
  self.keyInterceptor = CreateFrame('Frame', nil, self.buttonMenu)
  self.keyInterceptor:SetFrameStrata('FULLSCREEN')
  self.keyInterceptor:EnableKeyboard(true)
  self.keyInterceptor:SetPropagateKeyboardInput(true)
  self.keyInterceptor:SetScript('OnKeyDown', self.methods._OnKeyDownIntercept)

  return self
end

------------------------------------------
-- Public methods
------------------------------------------

function ChatAutocompleteIntegrator:Enable()
  -- These are not actual hooks, rather just listeners
  hooksecurefunc('ChatEdit_OnEditFocusLost', self.methods._OnChatFocusLost)
  hooksecurefunc('ChatEdit_OnTextChanged', self.methods._OnChatTextChanged)

  for i = 1, NUM_CHAT_WINDOWS do
    local chatFrameEditBox = _G['ChatFrame' .. i .. 'EditBox']
    chatFrameEditBox:HookScript('OnCursorChanged', function(editBox, cursorOffsetX)
      self.editBoxCursorOffsets[editBox] = cursorOffsetX
    end)
  end
end

function ChatAutocompleteIntegrator:Config()
  return {
    caseSensitivity = {
      type = 'select',
      values = { 'Smart case', 'Case-insensitive', 'Case-sensitive' },
      style = 'dropdown',
      name = 'Case sensitivity',
      desc = 'Specify the case sensitivity when searching.',
      default = 1,
      set = function(value)
        local map = { nil, true, false }
        self.caseInsensitive = map[value]
      end,
    },
    itemLinkDelimiters = {
      type = 'select',
      values = {
        ['<>'] = 'Angle brackets — <>',
        ['{}'] = 'Curly brackets — {}',
        ['[]'] = 'Square brackets — []',
        ['()'] = 'Parentheses — ()',
      },
      style = 'dropdown',
      name = 'Chat item link delimiters',
      desc = 'Specify the item link delimiters used.',
      default = '[]',
      set = function(value)
        self:SetItemLinkDelimiters(value:byte(1), value:byte(2))
      end,
    },
  }
end

function ChatAutocompleteIntegrator:SetItemLinkDelimiters(open, close)
  self.itemLinkDelimiters = {
    type(open) == 'string' and string.byte(open) or open,
    type(close) == 'string' and string.byte(close) or close,
  }
end

------------------------------------------
-- Private methods
------------------------------------------

function ChatAutocompleteIntegrator:_OnItemQueryComplete(editBox, items, searchInfo)
  if not editBox:IsShown() then
    return
  end

  local searchTerm = self:_GetEditBoxSearchTerm(editBox)

  -- Since this is received asynchronously, discard the result if it has become irrelevant
  if util.IsNilOrEmpty(searchTerm) or searchTerm:find(searchInfo.searchTerm, nil, true) ~= 1 then
    return self.buttonMenu:Hide()
  end

  self.buttonMenu:ClearAll()
  for item in items do
    self.buttonMenu:AddButton({
      text = item.link,
      value = item,
      onTooltipShow = function(tooltip)
        tooltip:SetItemByID(item.id)
      end,
      onClick = function(_)
        self:_OnItemSelected(editBox, item)
      end,
    })
  end

  if not self.buttonMenu:IsEmpty() then
    local offsetX = editBox:GetTextInsets() + searchInfo.cursorOffsetX
    self.buttonMenu:SetParent(editBox)
    self.buttonMenu:ClearAllPoints()
    self.buttonMenu:SetPoint('BOTTOMLEFT', editBox, 'TOPLEFT', offsetX,
                             editBox.autoCompleteYOffset or -AUTOCOMPLETE_DEFAULT_Y_OFFSET)
    self.buttonMenu:Show()
  else
    self.buttonMenu:Hide()
  end
end

function ChatAutocompleteIntegrator:_OnItemSelected(editBox, item)
  local searchTerm, prefixText, suffixText = self:_GetEditBoxSearchTerm(editBox)

  if not util.IsNilOrEmpty(searchTerm) then
    editBox:SetText(prefixText .. item.link .. suffixText)
    editBox:SetCursorPosition(#prefixText + #item.link)
  end

  self.buttonMenu:Hide()
end

function ChatAutocompleteIntegrator:_OnChatTextChanged(editBox, isUserInput)
  if not isUserInput then
    return
  end

  -- If it's potentially a secure command, abort to avoid runtime taint
  if string.byte(editBox:GetText() or '') == string.byte('/') then
    self.buttonMenu:Hide()
    return
  end

  local searchTerm = self:_GetEditBoxSearchTerm(editBox)

  if util.IsNilOrEmpty(searchTerm) then
    self.searchCursorOffsetX = searchTerm == '' and self.editBoxCursorOffsets[editBox] or nil
    self.buttonMenu:Hide()
    return
  end

  self.itemDatabase:FindItemsAsync({
    pattern = searchTerm,
    limit = const.maxItems,
    caseInsensitive = self.caseInsensitive,
  }, function(items)
    self:_OnItemQueryComplete(editBox, items, {
      searchTerm = searchTerm,
      cursorOffsetX = self.searchCursorOffsetX or self.editBoxCursorOffsets[editBox],
    })
  end)
end

function ChatAutocompleteIntegrator:_OnKeyDownIntercept(_, key)
  local action = ({
    ['TAB'] = function()
      self.buttonMenu:IncrementSelection(IsShiftKeyDown())
    end,
    ['UP'] = function()
      self.buttonMenu:IncrementSelection(true)
    end,
    ['DOWN'] = function()
      self.buttonMenu:IncrementSelection(false)
    end,
    ['ESCAPE'] = function()
      self.buttonMenu:Hide()
    end,
    ['ENTER'] = function()
      local editBox = GetCurrentKeyBoardFocus()
      self:_OnItemSelected(editBox, self.buttonMenu:GetSelection())
    end,
  })[key]

  if action ~= nil then
    action()
  end

  self.keyInterceptor:SetPropagateKeyboardInput(action == nil)
end

function ChatAutocompleteIntegrator:_OnChatFocusLost(_)
  self.buttonMenu:Hide()
end

function ChatAutocompleteIntegrator:_GetEditBoxSearchTerm(editBox)
  local cursorPosition = editBox:GetCursorPosition()
  local text = editBox:GetText()
  local activeText = text:sub(1, cursorPosition)
  local searchTerm, startIndex = self:_ExtractSearchTerm(activeText)

  if searchTerm == nil then
    return nil, nil, nil
  end

  local prefixText = text:sub(1, startIndex - 1)
  local suffixText = text:sub(cursorPosition + 1)

  return searchTerm, prefixText, suffixText
end

function ChatAutocompleteIntegrator:_ExtractSearchTerm(text)
  local open, close = unpack(self.itemLinkDelimiters)

  for i = #text, 1, -1 do
    if text:byte(i) == close then
      return nil, 0
    end

    if text:byte(i) == open then
      return text:sub(i + 1), i
    end
  end

  return nil, 0
end

------------------------------------------
-- Exports
------------------------------------------

export.New = function(...)
  return ChatAutocompleteIntegrator.New(...)
end
