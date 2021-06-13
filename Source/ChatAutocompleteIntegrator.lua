select(2, ...) 'ChatAutocompleteIntegrator'

-- Imports
local util = require 'Utility.Functions'

------------------------------------------
-- Class definition
------------------------------------------

local ChatAutocompleteIntegrator = {}
ChatAutocompleteIntegrator.__index = ChatAutocompleteIntegrator

------------------------------------------
-- Constructor
------------------------------------------

-- Creates a chat autocomplete menu
function ChatAutocompleteIntegrator.New()
  local self = setmetatable({}, ChatAutocompleteIntegrator)

  self.activeCompletionSource = nil
  self.completionSources = {}
  self.editBoxCursorOffsets = {}
  self.initialCursorOffsetX = nil
  self.methods = util.ContextBinder(self)

  -- The visual menu to select links
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

function ChatAutocompleteIntegrator:AddCompletionSource(trigger, source)
  self.completionSources[trigger] = source
end

------------------------------------------
-- Private methods
------------------------------------------

function ChatAutocompleteIntegrator:_OnQueryComplete(editBox, entries, searchInfo)
  if not editBox:IsShown() then
    return
  end

  local searchTerm = self:_GetEditBoxSearchTerm(editBox)

  -- Since this is received asynchronously, discard the result if it has become irrelevant
  if util.IsNilOrEmpty(searchTerm) or searchTerm:find(searchInfo.searchTerm, nil, true) ~= 1 then
    return self.buttonMenu:Hide()
  end

  self.buttonMenu:ClearAll()
  for entry in entries do
    self.buttonMenu:AddButton({
      text = entry.link,
      value = entry,
      onTooltipShow = self.activeCompletionSource.methods.SetupTooltip,
      onClick = function(_)
        self:_OnEntrySelected(editBox, entry)
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

function ChatAutocompleteIntegrator:_OnEntrySelected(editBox, entry)
  local searchTerm, prefixText, suffixText = self:_GetEditBoxSearchTerm(editBox)

  if not util.IsNilOrEmpty(searchTerm) then
    editBox:SetText(prefixText .. entry.link .. suffixText)
    editBox:SetCursorPosition(#prefixText + #entry.link)
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
    -- Save the cursor position for when the search was initiated
    self.initialCursorOffsetX = searchTerm == '' and self.editBoxCursorOffsets[editBox] or nil
    self.buttonMenu:Hide()
    return
  end

  self.activeCompletionSource:QueryAsync(searchTerm, function(entries)
    self:_OnQueryComplete(editBox, entries, {
      searchTerm = searchTerm,
      cursorOffsetX = self.initialCursorOffsetX or self.editBoxCursorOffsets[editBox],
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
      self:_OnEntrySelected(editBox, self.buttonMenu:GetSelection())
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
  -- Regardless of trigger, all links are closed by the same delimiter
  local closeDelimiter = string.byte(']')

  for i = #text, 1, -1 do
    local character = text:byte(i)

    if character == closeDelimiter then
      return nil, 0
    end

    for trigger, source in pairs(self.completionSources) do
      if character == trigger then
        self.activeCompletionSource = source
        return text:sub(i + 1), i
      end
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
