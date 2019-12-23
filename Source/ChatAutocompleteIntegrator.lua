select(2, ...) 'ChatAutocompleteIntegrator'

-- Imports
local util = require 'Utility.Functions'

-- Consts
local const = { maxItems = 10 }

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

  self.activeEditBox = nil
  self.bindings = {
    onMenuClickItem = util.Bind(self, self._OnMenuClickItem),
    onChatArrowPressed = util.Bind(self, self._OnChatArrowPressed),
    onChatTextChanged = util.Bind(self, self._OnChatTextChanged),
    onChatFocusLost = util.Bind(self, self._OnChatFocusLost),
    hookChatMessageBeforeSend = util.Bind(self, self._HookChatMessageBeforeSend),
    hookChatEscapePressed = util.Bind(self, self._HookChatEscapePressed),
    hookChatTabPressed = util.Bind(self, self._HookChatTabPressed),
  }

  self.buttonMenu = CreateFrame('Frame', nil, UIParent, 'ItemAutocompleteButtonMenuTemplate')
  self.buttonMenu:SetFrameLevel(10)
  self.buttonMenu:Hide()
  self.dummyTestString = nil
  self.previousSearchTerm = nil
  self.hookedEditBoxes = {}
  self.itemDatabase = itemDatabase
  self.itemLinkDelimiters = { string.byte('['), string.byte(']') }
  self.original = {
    substituteChatMessageBeforeSend = util.Hook(
      'SubstituteChatMessageBeforeSend',
      self.bindings.hookChatMessageBeforeSend),
    autoCompleteEditBoxOnEscapePressed = util.Hook(
      'AutoCompleteEditBox_OnEscapePressed',
      self.bindings.hookChatEscapePressed),
    chatEditCustomTabPressed = util.Hook(
      'ChatEdit_CustomTabPressed',
      self.bindings.hookChatTabPressed),
  }

  hooksecurefunc('ChatEdit_OnEditFocusLost', self.bindings.onChatFocusLost)
  hooksecurefunc('ChatEdit_OnTextChanged', self.bindings.onChatTextChanged)
end

------------------------------------------
-- Public methods
------------------------------------------

------------------------------------------
-- Private methods
------------------------------------------

function ChatAutocompleteIntegrator:_OnMenuClickItem(item)
  local editBox = self.activeEditBox
  local cursorPosition = editBox:GetCursorPosition()

  local text = editBox:GetText()
  local activeText = text:sub(1, cursorPosition)
  local searchTerm, startIndex = self:_ExtractSearchTerm(activeText)

  local prefixText = text:sub(1, startIndex - 1)
  local suffixText = text:sub(cursorPosition + 1)

  editBox:SetText(prefixText .. item.link .. suffixText)
  editBox:SetCursorPosition(#prefixText + #item.link)

  self.buttonMenu:Hide()
end

function ChatAutocompleteIntegrator:_OnChatTextChanged(editBox, isUserInput)
  local cursorPosition = editBox:GetCursorPosition()
  local activeText = editBox:GetText():sub(1, cursorPosition)
  local searchTerm, startIndex = self:_ExtractSearchTerm(activeText)

  if util.IsNilOrEmpty(searchTerm) then
    self.buttonMenu:Hide()
    return
  end

  -- This event is sometimes triggered twice
  if searchTerm == self.previousSearchTerm and self.buttonMenu:IsShown() then
    return
  end

  self.activeEditBox = editBox
  self.previousSearchTerm = searchTerm
  self.buttonMenu:ClearAll()

  for item in self.itemDatabase:FindItems(searchTerm, const.maxItems) do
    self.buttonMenu:AddButton({
      text = item.link,
      value = item,
      onTooltipShow = function(tooltip) tooltip:SetHyperlink(item.link) end,
      onClick = self.bindings.onMenuClickItem,
    })
  end

  if self.buttonMenu:IsEmpty() then
    self.buttonMenu:Hide()
    return
  end

  -- If the menu is not shown, display settings must be configured
  if not self.buttonMenu:IsShown() then
    if not self.hookedEditBoxes[editBox] then
      editBox:HookScript('OnArrowPressed', self.bindings.onChatArrowPressed)
      self.hookedEditBoxes[editBox] = true
    end

    -- Calculate the offset for the start bracket of the item link (this does
    -- not account for potential scrolling inside the edit box)
    local width = editBox:GetSize()
    local left, padding = editBox:GetTextInsets()
    local stringWidth = self:_GetEditBoxStringWidth(activeText:sub(1, startIndex - 1))
    local offsetX = math.min(left + stringWidth, width - padding * 2)

    -- TODO: Support chat in different corners?
    self.buttonMenu:ClearAllPoints()
    self.buttonMenu:SetPoint('BOTTOMLEFT', editBox, 'TOPLEFT', offsetX, editBox.autoCompleteYOffset or -AUTOCOMPLETE_DEFAULT_Y_OFFSET)
    self.buttonMenu:Show()
  end
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
    -- Whilst hooking the 'enter pressed' event seems to be the most obvious, it
    -- taints the runtime and prevents any secure commands from being executed
    -- in the chat (e.g. /target). To circumvent this, a function run later in
    -- the invocation chain is hooked instead - SubstituteChatMessageBeforeSend.
    -- To actually prevent normal operations, the return value itself is
    -- irrelevant due to being unused. Instead an error is thrown whilst a
    -- temporary error handler is set to avoid any user inconvenience.
    self:_OnMenuClickItem(self.buttonMenu:GetSelection())
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

  return self.original.autoCompleteEditBoxOnEscapePressed(editBox)
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

function ChatAutocompleteIntegrator:_GetEditBoxStringWidth(text)
  if self.dummyTestString == nil then
    -- Assume each edit box use the same font
    local font, size, type = self.activeEditBox:GetFont()
    self.dummyTestString = UIParent:CreateFontString()
    self.dummyTestString:SetFont(font, size, type)
  end

  self.dummyTestString:SetText(text)
  return self.dummyTestString:GetStringWidth()
end

------------------------------------------
-- Exports
------------------------------------------

export.New = function(...) return ChatAutocompleteIntegrator.New(...) end