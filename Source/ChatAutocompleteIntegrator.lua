select(2, ...) 'ChatAutocompleteIntegrator'

-- Imports
local util = require 'Utility.Functions'

------------------------------------------
-- Private locals
------------------------------------------

-- Returns the number of chat windows the client provides
--
-- 'NUM_CHAT_WINDOWS' survives on modern clients only as a deprecation fallback,
-- which players can switch off with the 'loadDeprecationFallbacks' CVar.
local function GetChatWindowCount()
  local chatFrameConstants = _G.Constants and _G.Constants.ChatFrameConstants
  return (chatFrameConstants and chatFrameConstants.MaxChatWindows) or _G.NUM_CHAT_WINDOWS
end

-- Returns whether a value is a secret, which addons cannot inspect (retail)
local function IsSecretValue(value)
  return _G.issecretvalue ~= nil and _G.issecretvalue(value)
end

------------------------------------------
-- Class definition
------------------------------------------

local ChatAutocompleteIntegrator = {}
ChatAutocompleteIntegrator.__index = ChatAutocompleteIntegrator

------------------------------------------
-- Constructor
------------------------------------------

-- Creates a chat autocomplete menu
function ChatAutocompleteIntegrator.New(eventSource)
  local self = setmetatable({}, ChatAutocompleteIntegrator)

  self.activeCompletionSource = nil
  self.activeEditBox = nil
  self.completionSources = {}
  self.editBoxCursorOffsets = {}
  self.eventSource = eventSource
  self.initialCursorOffsetX = nil
  self.keyInterceptor = nil
  self.methods = util.ContextBinder(self)
  self.statusProvider = nil

  -- The visual menu to select links
  self.buttonMenu = CreateFrame('Frame', nil, UIParent, 'ItemAutocompleteButtonMenuTemplate')
  self.buttonMenu:SetFrameLevel(10)
  self.buttonMenu:SetClampedToScreen(true)
  self.buttonMenu:Hide()

  return self
end

------------------------------------------
-- Public methods
------------------------------------------

function ChatAutocompleteIntegrator:Enable()
  -- The chat edit box used to expose its handlers as the globals
  -- 'ChatEdit_OnTextChanged' & 'ChatEdit_OnEditFocusLost'. They became mixin
  -- methods in Classic Era 1.15.9 & Anniversary 2.5.6, so the scripts are
  -- hooked per edit box instead, which works on every client.
  for i = 1, GetChatWindowCount() do
    local chatFrameEditBox = _G['ChatFrame' .. i .. 'EditBox']

    if chatFrameEditBox ~= nil then
      -- These are not actual hooks, rather just listeners
      chatFrameEditBox:HookScript('OnEditFocusLost', self.methods._OnChatFocusLost)
      chatFrameEditBox:HookScript('OnTextChanged', self.methods._OnChatTextChanged)
      chatFrameEditBox:HookScript('OnCursorChanged', function(editBox, cursorOffsetX)
        self.editBoxCursorOffsets[editBox] = cursorOffsetX
      end)
    end
  end

  -- 'EnableKeyboard' is protected, so after a reload in combat the key
  -- interceptor is created once combat ends. The mouse works until then.
  if InCombatLockdown() then
    self.eventSource:AddListener('PLAYER_REGEN_ENABLED', self.methods._CreateKeyInterceptor)
  else
    self:_CreateKeyInterceptor()
  end
end

function ChatAutocompleteIntegrator:AddCompletionSource(trigger, source)
  self.completionSources[trigger] = source
end

-- Sets a function returning a status text, displayed in place of the hint
function ChatAutocompleteIntegrator:SetStatusProvider(statusProvider)
  self.statusProvider = statusProvider
end

-- Updates an entry's text, e.g. once its link has been received
function ChatAutocompleteIntegrator:RefreshEntry(value)
  if self.buttonMenu:IsShown() and self.activeCompletionSource ~= nil then
    self.buttonMenu:UpdateButtonText(value, self.activeCompletionSource:GetEntryLink(value))
  end
end

------------------------------------------
-- Private methods
------------------------------------------

function ChatAutocompleteIntegrator:_CreateKeyInterceptor()
  self.eventSource:RemoveListener('PLAYER_REGEN_ENABLED', self.methods._CreateKeyInterceptor)

  -- An invisible frame to intercept key inputs
  self.keyInterceptor = CreateFrame('Frame', nil, self.buttonMenu)
  self.keyInterceptor:SetFrameStrata('FULLSCREEN')
  self.keyInterceptor:EnableKeyboard(true)
  self.keyInterceptor:SetPropagateKeyboardInput(true)
  self.keyInterceptor:SetScript('OnKeyDown', self.methods._OnKeyDownIntercept)
  self.keyInterceptor:SetScript('OnKeyUp', self.methods._OnKeyUpIntercept)

  self.eventSource:AddListener('PLAYER_REGEN_DISABLED', self.methods._OnCombatStart)
  self.eventSource:AddListener('PLAYER_REGEN_ENABLED', self.methods._OnCombatEnd)
end

function ChatAutocompleteIntegrator:_OnQueryComplete(editBox, entries, searchInfo)
  if not editBox:IsShown() then
    return
  end

  local searchTerm = self:_GetEditBoxSearchTerm(editBox)

  -- Since this is received asynchronously, discard the result if it has become irrelevant
  if util.IsNilOrEmpty(searchTerm) or searchTerm:find(searchInfo.searchTerm, nil, true) ~= 1 then
    return self.buttonMenu:Hide()
  end

  local completionSource = self.activeCompletionSource

  self.buttonMenu:ClearAll()
  for entry in entries do
    self.buttonMenu:AddButton({
      text = completionSource:GetEntryLink(entry),
      value = entry,
      onTooltipShow = completionSource.methods.SetupTooltip,
      onClick = function(_)
        self:_OnEntrySelected(editBox, entry)
      end,
    })
  end

  if not self.buttonMenu:IsEmpty() then
    self.activeEditBox = editBox
    self.buttonMenu:SetFooterText(self.statusProvider and self.statusProvider())
    self.buttonMenu:SetParent(editBox)
    self:_AnchorButtonMenu(editBox, searchInfo.cursorOffsetX)
    self.buttonMenu:Show()
  else
    self.buttonMenu:Hide()
  end
end

-- Anchors the menu above the edit box, or below it if there's no room above
function ChatAutocompleteIntegrator:_AnchorButtonMenu(editBox, cursorOffsetX)
  local offsetX = editBox:GetTextInsets() + (cursorOffsetX or 0)
  local offsetY = AUTOCOMPLETE_DEFAULT_Y_OFFSET or 3
  local menuTop = ((editBox:GetTop() or 0) + self.buttonMenu:GetHeight() + offsetY) *
                    editBox:GetEffectiveScale()

  self.buttonMenu:ClearAllPoints()
  if menuTop > UIParent:GetTop() * UIParent:GetEffectiveScale() then
    self.buttonMenu:SetPoint('TOPLEFT', editBox, 'BOTTOMLEFT', offsetX,
                             editBox.autoCompleteYOffset or offsetY)
  else
    self.buttonMenu:SetPoint('BOTTOMLEFT', editBox, 'TOPLEFT', offsetX,
                             editBox.autoCompleteYOffset or -offsetY)
  end
end

function ChatAutocompleteIntegrator:_OnEntrySelected(editBox, entry)
  if editBox == nil or entry == nil then
    return self.buttonMenu:Hide()
  end

  local searchTerm, prefixText, suffixText = self:_GetEditBoxSearchTerm(editBox)
  local link = self.activeCompletionSource:GetEntryLink(entry)

  if not util.IsNilOrEmpty(searchTerm) and link ~= nil then
    editBox:SetText(prefixText .. link .. suffixText)
    editBox:SetCursorPosition(#prefixText + #link)
  end

  self.buttonMenu:Hide()
end

function ChatAutocompleteIntegrator:_OnChatTextChanged(editBox, isUserInput)
  if not isUserInput then
    return
  end

  -- If it's potentially a secure command, abort to avoid runtime taint
  local text = editBox:GetText()
  if IsSecretValue(text) or string.byte(text or '') == string.byte('/') then
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
      self:_OnEntrySelected(self.activeEditBox, self.buttonMenu:GetSelection())
    end,
  })[key]

  local isPropagating = self.keyInterceptor:GetPropagateKeyboardInput()

  if action ~= nil then
    action()
  end

  -- Since retail 10.1.5, 'SetPropagateKeyboardInput' cannot be called in
  -- combat. The keys then reach the chat as well, thus Enter sends the message
  -- along with the inserted link, and Escape also closes the edit box.
  if not InCombatLockdown() then
    self.keyInterceptor:SetPropagateKeyboardInput(action == nil)
  elseif not isPropagating then
    -- Combat began whilst a key was held, which would swallow every key
    self.keyInterceptor:Hide()
  end
end

function ChatAutocompleteIntegrator:_OnKeyUpIntercept(_, _)
  -- Only the key being pressed should be intercepted, should combat begin
  if not InCombatLockdown() then
    self.keyInterceptor:SetPropagateKeyboardInput(true)
  end
end

function ChatAutocompleteIntegrator:_OnCombatStart()
  if not InCombatLockdown() then
    self.keyInterceptor:SetPropagateKeyboardInput(true)
  end
end

function ChatAutocompleteIntegrator:_OnCombatEnd()
  self.keyInterceptor:SetPropagateKeyboardInput(true)
  self.keyInterceptor:Show()
end

function ChatAutocompleteIntegrator:_OnChatFocusLost(_)
  self.buttonMenu:Hide()
end

function ChatAutocompleteIntegrator:_GetEditBoxSearchTerm(editBox)
  local cursorPosition = editBox:GetCursorPosition()
  local text = editBox:GetText()

  if IsSecretValue(text) then
    return nil, nil, nil
  end
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
