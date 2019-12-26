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
  self.fontStringWidthTester = nil
  self.itemDatabase = itemDatabase
  self.itemLinkDelimiters = { string.byte('<'), string.byte('>') }
  self.methods = util.ContextBinder(self)
  self.previousSearchTerm = nil

  return self
end

------------------------------------------
-- Public methods
------------------------------------------

function ChatAutocompleteIntegrator:Enable()
  -- These are not actually hooks, rather just listeners
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
  end
end

------------------------------------------
-- Private methods
------------------------------------------

function ChatAutocompleteIntegrator:_OnItemSearchComplete(editBox, items, searchInfo)
  if not editBox:IsShown() then return end

  self.buttonMenu:ClearAll()
  for item in items do
    self.buttonMenu:AddButton({
      text = item.link,
      value = item,
      onTooltipShow = function(tooltip) tooltip:SetHyperlink(item.link) end,
      onClick = function(item) self:_OnItemSelected(editBox, item) end
    })
  end

  if not self.buttonMenu:IsEmpty() then
    -- Calculate the offset for the start bracket of the item link (this does
    -- not account for potential scrolling inside the edit box)
    local left, padding = editBox:GetTextInsets()
    local stringWidth = self:_GetEditBoxStringWidth(editBox, searchInfo.preSearchTermText)
    local offsetX = math.min(left + stringWidth, editBox:GetSize() - padding * 2)
    self.buttonMenu:ClearAllPoints()
    self.buttonMenu:SetPoint('BOTTOMLEFT', editBox, 'TOPLEFT', offsetX, editBox.autoCompleteYOffset or -AUTOCOMPLETE_DEFAULT_Y_OFFSET)
    self.buttonMenu:Show()
  else
    self.buttonMenu:Hide()
  end
end

function ChatAutocompleteIntegrator:_OnItemSelected(editBox, item)
  local cursorPosition = editBox:GetCursorPosition()
  local text = editBox:GetText()
  local activeText = text:sub(1, cursorPosition)
  local _, startIndex = self:_ExtractSearchTerm(activeText)

  local prefixText = text:sub(1, startIndex - 1)
  local suffixText = text:sub(cursorPosition + 1)

  editBox:SetText(prefixText .. item.link .. suffixText)
  editBox:SetCursorPosition(#prefixText + #item.link)

  self.buttonMenu:Hide()
end

function ChatAutocompleteIntegrator:_OnChatTextChanged(editBox, isUserInput)
  if not isUserInput then return end

  local cursorPosition = editBox:GetCursorPosition()
  local activeText = editBox:GetText():sub(1, cursorPosition)
  local searchTerm, startIndex = self:_ExtractSearchTerm(activeText)

  if util.IsNilOrEmpty(searchTerm) then
    self.buttonMenu:Hide()
    return
  end

  -- This event may be triggered twice, therefore confirm it's a new search
  if searchTerm == self.previousSearchTerm and self.buttonMenu:IsShown() then
    return
  end

  self.previousSearchTerm = searchTerm
  self.itemDatabase:FindItemsAsync(searchTerm, const.maxItems, function(items)
    local searchInfo = { preSearchTermText = activeText:sub(1, startIndex - 1) }
    self:_OnItemSearchComplete(editBox, items, searchInfo)
  end)
end

function ChatAutocompleteIntegrator:_OnChatArrowPressed(editBox, key)
  if self.buttonMenu:IsShown() then
    if key == 'UP' then
      self.buttonMenu:IncrementSelection(true)
    elseif key == 'DOWN' then
      self.buttonMenu:IncrementSelection(false)
    end
  end
end

function ChatAutocompleteIntegrator:_OnChatFocusLost(editBox)
  self.buttonMenu:Hide()
end

function ChatAutocompleteIntegrator:_HookChatMessageBeforeSend(text)
  if self.buttonMenu:IsShown() then
    local editBox = GetCurrentKeyBoardFocus()

    -- Whilst hooking the 'enter pressed' event seems to be the most obvious, it
    -- taints the runtime and prevents any secure commands from being executed
    -- in the chat (e.g. /target). To circumvent this, a function run later in
    -- the invocation chain is hooked instead - SubstituteChatMessageBeforeSend.
    -- To actually prevent normal operations, the return value itself is
    -- irrelevant due to being unused. Instead an error is thrown whilst a
    -- temporary error handler is set to avoid any user inconvenience.
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

function ChatAutocompleteIntegrator:_GetEditBoxStringWidth(editBox, text)
  if self.fontStringWidthTester == nil then
    -- Assume each edit box use the same font
    local font, size, type = editBox:GetFont()
    self.fontStringWidthTester = UIParent:CreateFontString()
    self.fontStringWidthTester:SetFont(font, size, type)
  end

  self.fontStringWidthTester:SetText(text)
  return self.fontStringWidthTester:GetStringWidth()
end

function ChatAutocompleteIntegrator:_ExtractSearchTerm(text)
  local open, close = unpack(self.itemLinkDelimiters)

  for i = #text, 1, -1 do
    if text:byte(i) == close then return end

    if text:byte(i) == open then
      return text:sub(i + 1), i
    end
  end
end

------------------------------------------
-- Exports
------------------------------------------

export.New = function(...) return ChatAutocompleteIntegrator.New(...) end