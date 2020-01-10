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

  self.buttonMenu = CreateFrame('Frame', nil, UIParent, 'ItemAutocompleteButtonMenuTemplate')
  self.buttonMenu:Hide()
  self.buttonMenu:SetFrameLevel(10)
  self.caseInsensitive = nil
  self.editBoxCursorOffsets = {}
  self.itemDatabase = itemDatabase
  self.methods = util.ContextBinder(self)
  self.searchCursorOffsetX = nil
  self:SetItemLinkDelimiters('[', ']')

  return self
end

------------------------------------------
-- Public methods
------------------------------------------

function ChatAutocompleteIntegrator:Enable()
  -- These are not actual hooks, rather just listeners
  hooksecurefunc('ChatEdit_OnEditFocusLost', self.methods._OnChatFocusLost)
  hooksecurefunc('ChatEdit_OnTextChanged', self.methods._OnChatTextChanged)

  self.original = {
    substituteChatMessageBeforeSend = util.Hook(
      'SubstituteChatMessageBeforeSend',
      self.methods._HookChatMessageBeforeSend),
    autoCompleteEditBoxOnEscapePressed = util.Hook(
      'AutoCompleteEditBox_OnEscapePressed',
      self.methods._HookChatEscapePressed),
    chatEditCustomTabPressed = util.Hook(
      'ChatEdit_CustomTabPressed',
      self.methods._HookChatTabPressed),
  }

  for i = 1, NUM_CHAT_WINDOWS do
    local editBox = _G['ChatFrame' .. i .. 'EditBox']
    editBox:HookScript('OnArrowPressed', self.methods._OnChatArrowPressed)
    editBox:HookScript('OnCursorChanged', self.methods._OnChatCursorChanged)
  end

  self.buttonMenu:HookScript('OnShow', function(menu)
    local parent = menu:GetParent()
    menu.previousArrowKeyMode = parent:GetAltArrowKeyMode()
    parent:SetAltArrowKeyMode(false)
  end)

  self.buttonMenu:HookScript('OnHide', function(menu)
    if menu.previousArrowKeyMode then
      menu:GetParent():SetAltArrowKeyMode(menu.previousArrowKeyMode)
      menu.previousArrowKeyMode = nil
    end
  end)
end

function ChatAutocompleteIntegrator:Config()
  return {
    caseSensitivity = {
      type = 'select',
      values = {
        'Smart case',
        'Case-insensitive',
        'Case-sensitive',
      },
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

function ChatAutocompleteIntegrator:_OnItemSearchComplete(editBox, items, searchInfo)
  if not editBox:IsShown() then return end

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
      onTooltipShow = function(tooltip) tooltip:SetItemByID(item.id) end,
      onClick = function(_) self:_OnItemSelected(editBox, item) end
    })
  end

  if not self.buttonMenu:IsEmpty() then
    local offsetX = editBox:GetTextInsets() + searchInfo.searchOffsetX
    self.buttonMenu:SetParent(editBox)
    self.buttonMenu:ClearAllPoints()
    self.buttonMenu:SetPoint('BOTTOMLEFT', editBox, 'TOPLEFT', offsetX, editBox.autoCompleteYOffset or -AUTOCOMPLETE_DEFAULT_Y_OFFSET)
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
  if not isUserInput then return end

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
    self:_OnItemSearchComplete(editBox, items, {
      searchTerm = searchTerm,
      searchOffsetX = self.searchCursorOffsetX or self.editBoxCursorOffsets[editBox],
    })
  end)
end

function ChatAutocompleteIntegrator:_OnChatArrowPressed(_, key)
  if self.buttonMenu:IsShown() then
    if key == 'UP' then
      self.buttonMenu:IncrementSelection(true)
    elseif key == 'DOWN' then
      self.buttonMenu:IncrementSelection(false)
    end
  end
end

function ChatAutocompleteIntegrator:_OnChatCursorChanged(editBox, x)
  self.editBoxCursorOffsets[editBox] = x
end

function ChatAutocompleteIntegrator:_OnChatFocusLost(_)
  self.buttonMenu:Hide()
end

function ChatAutocompleteIntegrator:_HookChatMessageBeforeSend(text)
  if self.buttonMenu:IsShown() then
    local editBox = GetCurrentKeyBoardFocus()

    -- Whilst hooking the 'enter pressed' event seems to be the most obvious, it
    -- taints the runtime and prevents any secure commands from being executed
    -- in the chat (e.g. /target). To circumvent this, a function run later in
    -- the invocation chain is hooked instead - SubstituteChatMessageBeforeSend.
    -- To actually prevent normal operations, the return value cannot be
    -- utilized due to being unused. Instead an error is thrown whilst a
    -- temporary error handler is set to avoid any interference for users.
    self:_OnItemSelected(editBox, self.buttonMenu:GetSelection())
    util.Abort()
  end

  return self.original.substituteChatMessageBeforeSend(text)
end

function ChatAutocompleteIntegrator:_HookChatEscapePressed(editBox)
  if self.buttonMenu:IsShown() then
    self.buttonMenu:Hide()
    return true
  end

  return self.original.autoCompleteEditBoxOnEscapePressed(editBox)
end

function ChatAutocompleteIntegrator:_HookChatTabPressed(editBox)
  if self.buttonMenu:IsShown() then
    self.buttonMenu:IncrementSelection(IsShiftKeyDown())
    return true
  end

  return self.original.chatEditCustomTabPressed(editBox)
end

function ChatAutocompleteIntegrator:_GetEditBoxSearchTerm(editBox)
  local cursorPosition = editBox:GetCursorPosition()
  local text = editBox:GetText()
  local activeText = editBox:GetText():sub(1, cursorPosition)
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

export.New = function(...) return ChatAutocompleteIntegrator.New(...) end