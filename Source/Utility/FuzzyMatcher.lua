select(2, ...) 'Utility.FuzzyMatcher'

-- Imports
local utf8 = require 'Shared.UTF8'

------------------------------------------
-- Class definition
------------------------------------------

local FuzzyMatcher = {}
FuzzyMatcher.__index = FuzzyMatcher

------------------------------------------
-- Constructor
------------------------------------------

function FuzzyMatcher.New(pattern, caseInsensitive)
  local self = setmetatable({}, FuzzyMatcher)

  self.caseInsensitive = caseInsensitive
  self.patternCodePoints = {}
  self.textBuffer = {}

  for _, codePoint in utf8.CodePoints(pattern) do
    codePoint = caseInsensitive and utf8.ToLower(codePoint) or codePoint
    self.patternCodePoints[#self.patternCodePoints + 1] = codePoint
  end

  return self
end

------------------------------------------
-- Public methods
------------------------------------------

function FuzzyMatcher:Match(text)
  if #self.patternCodePoints == 0 then
    return 1, 1, 0
  end

  local textCodePoints = self.textBuffer
  local codePointIndex = 0
  local pidx = 1
  local sidx = 0
  local eidx = 0

  for _, codePoint in utf8.CodePoints(text) do
    codePointIndex = codePointIndex + 1
    textCodePoints[codePointIndex] = codePoint

    if self.caseInsensitive then
      codePoint = utf8.ToLower(codePoint)
    end

    if codePoint == self.patternCodePoints[pidx] then
      if sidx < 1 then
        sidx = codePointIndex
      end

      pidx = pidx + 1
      if pidx > #self.patternCodePoints then
        eidx = codePointIndex + 1
        break
      end
    end
  end

  if sidx >= 1 and eidx >= 1 then
    pidx = pidx - 1

    for index = eidx - 1, sidx, -1 do
      local codePoint = textCodePoints[index]

      if self.caseInsensitive then
        codePoint = utf8.ToLower(codePoint)
      end

      if codePoint == self.patternCodePoints[pidx] then
        pidx = pidx - 1

        if pidx < 1 then
          sidx = index
          break
        end
      end
    end

    return sidx, eidx, self:_EvaluateBonus(textCodePoints, strlenutf8(text), sidx, eidx)
  end

  return 0, 0, 0
end

------------------------------------------
-- Private statics
------------------------------------------

local charLower = 1
local charUpper = 2
local charLetter = 3
local charNumber = 4
local charNonWord = 5

local scoreMatch = 16
local scoreGapStart = -3
local scoreGapExtention = -1
local bonusBoundary = scoreMatch / 2
local bonusNonWord = scoreMatch / 2
local bonusCamel123 = bonusBoundary + scoreGapExtention
local bonusConsecutive = -(scoreGapStart + scoreGapExtention)
local bonusFirstCharMultiplier = 2
local bonusExactMatch = scoreMatch

local function GetCharacterClass(char)
  if char <= utf8.maxAscii then
    if char >= 97 and char <= 122 then return charLower end
    if char >= 65 and char <= 90 then return charUpper end
    if char >= 48 and char <= 57 then return charNumber end
  else
    if utf8.IsLowerCaseLetter(char) then return charLower end
    if utf8.IsUpperCaseLetter(char) then return charUpper end
    if utf8.IsLetter(char) then return charLetter end
    if utf8.IsDigit(char) then return charNumber end
  end

  return charNonWord
end

local function GetBonusFor(prevClass, class)
  if prevClass == charNonWord and class ~= charNonWord then
    return bonusBoundary
  elseif prevClass == charLower and class == charUpper or prevClass ~= charNumber and class == charNumber then
    return bonusCamel123
  elseif class == charNonWord then
    return bonusNonWord
  end

  return 0
end

------------------------------------------
-- Private methods
------------------------------------------

function FuzzyMatcher:_EvaluateBonus(textCodePoints, textLength, sidx, eidx)
  local pidx, score, inGap, consecutive, firstBonus = 1, 0, false, 0, 0
  local prevClass = charNonWord

  if sidx > 1 then
    prevClass = GetCharacterClass(textCodePoints[sidx - 1])
  end

  for index = sidx, eidx - 1 do
    local codePoint = textCodePoints[index]
    local class = GetCharacterClass(codePoint)

    if self.caseInsensitive then
      codePoint = utf8.ToLower(codePoint)
    end

    if codePoint == self.patternCodePoints[pidx] then
      local bonus = GetBonusFor(prevClass, class)
      score = score + scoreMatch

      if consecutive == 0 then
        firstBonus = bonus
      else
        -- Break consecutive chunk
        if bonus == bonusBoundary then
          firstBonus = bonus
        end

        bonus = math.max(math.max(bonus, firstBonus), bonusConsecutive)
      end

      if pidx == 1 then
        local additionalBonus = index == 1 and 2 or 1
        score = score + bonus * math.pow(bonusFirstCharMultiplier, additionalBonus)
      else
        score = score + bonus
      end

      inGap = false
      consecutive = consecutive + 1
      pidx = pidx + 1
    else
      score = score + (inGap and scoreGapExtention or scoreGapStart)
      inGap = true
      consecutive = 0
      firstBonus = 0
    end
    prevClass = class
  end

  if consecutive == textLength then
    score = score + bonusExactMatch
  end

  return score
end

------------------------------------------
-- Exports
------------------------------------------

export.New = function(...) return FuzzyMatcher.New(...) end