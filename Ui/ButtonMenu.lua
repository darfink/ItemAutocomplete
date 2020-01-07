select(2, ...) 'Ui.ButtonMenu'

------------------------------------------
-- Global exports
------------------------------------------

function _G.ItemAutocompleteButtonMenuOnLoad(buttonMenu)
  buttonMenu:SetBackdropBorderColor(TOOLTIP_DEFAULT_COLOR.r, TOOLTIP_DEFAULT_COLOR.g, TOOLTIP_DEFAULT_COLOR.b)
  buttonMenu:SetBackdropColor(TOOLTIP_DEFAULT_BACKGROUND_COLOR.r, TOOLTIP_DEFAULT_BACKGROUND_COLOR.g, TOOLTIP_DEFAULT_BACKGROUND_COLOR.b)
  buttonMenu:SetScript('OnHide', function() buttonMenu:HideGameTooltipIfOwned() end)
  buttonMenu.selectedButtonIndex = nil
  buttonMenu.buttonCount = 0
  buttonMenu.buttons = {}
  buttonMenu.buttonMargin = 30
  buttonMenu.baseHeight = 40

  function buttonMenu:SelectButton(buttonIndex)
    assert(buttonIndex == nil or buttonIndex >= 1 and buttonIndex <= self.buttonCount, 'Button index is out of bounds')

    local previousButton = self.buttons[self.selectedButtonIndex]
    local selectedButton = self.buttons[buttonIndex]

    if previousButton ~= nil then
      previousButton:UnlockHighlight()

      if GameTooltip:GetOwner() == previousButton then
        GameTooltip:Hide()
      end
    end

    if selectedButton ~= nil then
      selectedButton:LockHighlight()
      selectedButton:ShowTooltip()
    end

    self.selectedButtonIndex = buttonIndex
  end

  function buttonMenu:GetSelection()
    local selectedButton = self.buttons[self.selectedButtonIndex]
    return selectedButton and selectedButton.info.value
  end

  function buttonMenu:IncrementSelection(decrement)
    if self:IsEmpty() then return end

    local buttonIndex = self.selectedButtonIndex + (decrement and -1 or 1)

    if buttonIndex <= 0 then
      buttonIndex = self.buttonCount
    elseif buttonIndex > self.buttonCount then
      buttonIndex = 1
    end

    self:SelectButton(buttonIndex)
  end

  function buttonMenu:AddButton(info)
    self.buttonCount = self.buttonCount + 1

    if self.buttons[self.buttonCount] == nil then
      -- Create a new button frame if one does not exist
      self.buttons[self.buttonCount] = self:_CreateButton()
    end

    local button = self.buttons[self.buttonCount]
    button.info = info
    button:SetText(info.text)
    button:Show()

    if self.selectedButtonIndex == nil then
      self:SelectButton(1)
    end

    local buttonWidth = button:GetFontString():GetStringWidth() + self.buttonMargin

    self:SetHeight(self.baseHeight + button:GetHeight() * self.buttonCount)
    self:SetWidth(math.max(buttonWidth, self:GetWidth()))
  end

  function buttonMenu:ClearAll()
    if self:IsEmpty() then return end
    self:SelectButton(nil)

    for i = 1, self.buttonCount do
      self.buttons[i]:Hide()
    end

    self.buttonCount = 0
    self:SetWidth(50)
  end

  function buttonMenu:IsEmpty()
    return self.buttonCount == 0
  end

  function buttonMenu:HideGameTooltipIfOwned()
    local owner = GameTooltip:GetOwner()

    for _, button in ipairs(self.buttons) do
      if owner == button then
        GameTooltip:Hide()
        break
      end
    end
  end

  function buttonMenu:_CreateButton()
    local button = CreateFrame('Button', nil, self, 'ItemAutocompleteButtonTemplate')

    button.ShowTooltip = function()
      if button.info.onTooltipShow ~= nil then
        GameTooltip:SetOwner(button, 'ANCHOR_RIGHT')
        button.info.onTooltipShow(GameTooltip)
      end
    end

    if self.buttonCount == 1 then
      button:SetPoint('TOPLEFT', 0, -10)
      button:SetPoint('TOPRIGHT', 0, -10)
    else
      local previousButton = self.buttons[self.buttonCount - 1]

      button:SetPoint('TOPLEFT', previousButton, 'BOTTOMLEFT')
      button:SetPoint('TOPRIGHT', previousButton, 'BOTTOMRIGHT')
    end

    button:GetFontString():SetPoint('LEFT', button, 'LEFT', 15, 0)
    button:SetScript('OnLeave', function() GameTooltip:Hide() end)
    button:SetScript('OnEnter', button.ShowTooltip)
    button:SetScript('OnClick', function()
      if button.info.onClick ~= nil then
        button.info.onClick(button.info.value)
      end
    end)

    return button
  end
end