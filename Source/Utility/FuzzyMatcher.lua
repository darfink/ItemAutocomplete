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

  for _, codePoint in utf8.CodePoints(pattern) do
    codePoint = caseInsensitive and utf8.ToLower(codePoint) or codePoint
    self.patternCodePoints[#self.patternCodePoints + 1] = codePoint
  end

  return self
end

------------------------------------------
-- Public methods
------------------------------------------

-- Cache this for performance
local lowerutf8 = utf8.ToLower

function FuzzyMatcher:Match(codePoints)
  -- Cache as many variables as possible to improve performance
  local caseInsensitive = self.caseInsensitive
  local patternCodePoints = self.patternCodePoints

  if #patternCodePoints == 0 then
    return 1, 1, 0
  end

  local pidx = 1
  local sidx = 0
  local eidx = 0

  for index = 1, #codePoints do
    local codePoint = caseInsensitive and lowerutf8(codePoints[index]) or codePoints[index]

    if codePoint == patternCodePoints[pidx] then
      if sidx < 1 then
        sidx = index
      end

      pidx = pidx + 1
      if pidx > #patternCodePoints then
        eidx = index + 1
        break
      end
    end
  end

  if sidx >= 1 and eidx >= 1 then
    pidx = pidx - 1

    for index = eidx - 1, sidx, -1 do
      local codePoint = caseInsensitive and lowerutf8(codePoints[index]) or codePoints[index]

      if codePoint == patternCodePoints[pidx] then
        pidx = pidx - 1

        if pidx < 1 then
          sidx = index
          break
        end
      end
    end

    return sidx, eidx, self:_EvaluateBonus(codePoints, sidx, eidx)
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
local scoreGapExtension = -1
local bonusBoundary = scoreMatch / 2
local bonusNonWord = scoreMatch / 2
local bonusCamel123 = bonusBoundary + scoreGapExtension
local bonusConsecutive = -(scoreGapStart + scoreGapExtension)
local bonusFirstCharMultiplier = 2
local bonusExactMatch = scoreMatch

local function GetCharacterClass(codePoint)
  if codePoint <= 127 then
    if codePoint >= 97 and codePoint <= 122 then
      return charLower
    end
    if codePoint >= 65 and codePoint <= 90 then
      return charUpper
    end
    if codePoint >= 48 and codePoint <= 57 then
      return charNumber
    end
  else
    if utf8.IsLowerCaseLetter(codePoint) then
      return charLower
    end
    if utf8.IsUpperCaseLetter(codePoint) then
      return charUpper
    end
    if utf8.IsLetter(codePoint) then
      return charLetter
    end
    if utf8.IsDigit(codePoint) then
      return charNumber
    end
  end

  return charNonWord
end

local function GetBonusFor(prevClass, class)
  if prevClass == charNonWord and class ~= charNonWord then
    return bonusBoundary
  elseif prevClass == charLower and class == charUpper or prevClass ~= charNumber and class ==
    charNumber then
    return bonusCamel123
  elseif class == charNonWord then
    return bonusNonWord
  end

  return 0
end

------------------------------------------
-- Private methods
------------------------------------------

function FuzzyMatcher:_EvaluateBonus(codePoints, sidx, eidx)
  -- Cache as many variables as possible to improve performance
  local caseInsensitive = self.caseInsensitive
  local patternCodePoints = self.patternCodePoints

  local pidx, score, inGap, consecutive, firstBonus = 1, 0, false, 0, 0
  local prevClass = sidx > 1 and GetCharacterClass(codePoints[sidx - 1]) or charNonWord

  for index = sidx, eidx - 1 do
    local codePoint = codePoints[index]
    local class = GetCharacterClass(codePoint)

    if caseInsensitive then
      codePoint = lowerutf8(codePoint)
    end

    if codePoint == patternCodePoints[pidx] then
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
        score = score + bonus * (bonusFirstCharMultiplier ^ additionalBonus)
      else
        score = score + bonus
      end

      inGap = false
      consecutive = consecutive + 1
      pidx = pidx + 1
    else
      score = score + (inGap and scoreGapExtension or scoreGapStart)
      inGap = true
      consecutive = 0
      firstBonus = 0
    end
    prevClass = class
  end

  if consecutive == #codePoints then
    score = score + bonusExactMatch
  end

  return score
end

------------------------------------------
-- Exports
------------------------------------------

export.New = function(...)
  return FuzzyMatcher.New(...)
end
