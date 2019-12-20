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
function ChatAutocompleteIntegrator.New(itemBrowser)
  local self = setmetatable({}, ChatAutocompleteIntegrator)

  self.activeEditBox = nil
  self.bindings = {
    onClickItem = util.Bind(self, self._OnClickItem),
    onChatArrowPressed = util.Bind(self, self._OnChatArrowPressed),
    onChatTextChanged = util.Bind(self, self._OnChatTextChanged),
    hookChatEnterPressed = util.Bind(self, self._HookChatEnterPressed),
    hookChatEscapePressed = util.Bind(self, self._HookChatEscapePressed),
    hookChatTabPressed = util.Bind(self, self._HookChatTabPressed),
  }

  self.buttonMenu = CreateFrame('Frame', nil, UIParent, 'ItemAutocompleteButtonMenuTemplate')
  self.buttonMenu:SetFrameLevel(10)
  self.buttonMenu:Hide()
  self.dummyTestString = nil
  self.hookedEditBoxes = {}
  self.itemBrowser = itemBrowser
  self.itemLinkDelimiters = { string.byte('['), string.byte(']') }
  self.original = {
    autoCompleteEditBoxOnEnterPressed = util.Hook(
      'AutoCompleteEditBox_OnEnterPressed',
      self.bindings.hookChatEnterPressed),
    autoCompleteEditBoxOnEscapePressed = util.Hook(
      'AutoCompleteEditBox_OnEscapePressed',
      self.bindings.hookChatEscapePressed),
    chatEditCustomTabPressed = util.Hook(
      'ChatEdit_CustomTabPressed',
      self.bindings.hookChatTabPressed),
  }

  hooksecurefunc('ChatEdit_OnTextChanged', self.bindings.onChatTextChanged)
end

------------------------------------------
-- Public methods
------------------------------------------

------------------------------------------
-- Private methods
------------------------------------------

function ChatAutocompleteIntegrator:_OnClickItem(item)
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

  self.activeEditBox = editBox
  self.buttonMenu:ClearAll()

  for item in self.itemBrowser:FindItems(searchTerm, const.maxItems) do
    self.buttonMenu:AddButton({
      text = item.link,
      value = item,
      onTooltipShow = function(tooltip) tooltip:SetHyperlink(item.link) end,
      onClick = self.bindings.onClickItem,
    })
  end

  if self.buttonMenu:IsEmpty() then
    self.buttonMenu:Hide()
    return
  end

  -- If the menu is not shown, some display initialization is required
  if not self.buttonMenu:IsShown() then
    if not self.hookedEditBoxes[editBox] then
      editBox:HookScript('OnArrowPressed', self.bindings.onChatArrowPressed)
      self.hookedEditBoxes[editBox] = true
    end

    -- Calculate the offset for the start bracket of the item link (this does
    -- not account for potential scrolling inside the edit box)
    local width = editBox:GetSize()
    local left, padding = editBox:GetTextInsets()
    local stringWidth = self:_GetChatStringWidth(activeText:sub(1, startIndex - 1))
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

function ChatAutocompleteIntegrator:_HookChatEnterPressed(editBox)
  if self.buttonMenu:IsShown() then
    self:_OnClickItem(self.buttonMenu:GetSelection())
    return true
  end

  return self.original.autoCompleteEditBoxOnEnterPressed(editBox)
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

function ChatAutocompleteIntegrator:_GetChatStringWidth(text)
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