select(2, ...) 'Utility.Algo'

------------------------------------------
-- Locals
------------------------------------------

local charLower = 1
local charUpper = 2
local charNumber = 3
local charNonWord = 4

local scoreMatch = 16
local scoreGapStart = -3
local scoreGapExtention = -1
local bonusBoundary = scoreMatch / 2
local bonusNonWord = scoreMatch / 2
local bonusCamel123 = bonusBoundary + scoreGapExtention
local bonusConsecutive = -(scoreGapStart + scoreGapExtention)
local bonusFirstCharMultiplier = 2
local bonusExactMatch = scoreMatch

local function IsLowerCaseLetter(char) return char >= 97 and char <= 122 end
local function IsUpperCaseLetter(char) return char >= 65 and char <= 90 end
local function IsDigit(char) return char >= 48 and char <= 57 end

local function GetCharacterClass(char)
  if IsLowerCaseLetter(char) then return charLower end
  if IsUpperCaseLetter(char) then return charUpper end
  if IsDigit(char) then return charNumber end
  return charNonWord
end

local function bonusFor(prevClass, class)
  if prevClass == charNonWord and class ~= charNonWord then
    -- Word boundary
    return bonusBoundary
  elseif prevClass == charLower and class == charUpper or prevClass ~= charNumber and class == charNumber then
    -- camelCase letter123
    return bonusCamel123
  elseif class == charNonWord then
    return bonusNonWord
  end

  return 0
end

local function EvaluateBonus(caseInsensitive, text, pattern, sidx, eidx)
  local pidx, score, inGap, consecutive, firstBonus = 1, 0, false, 0, 0
  local prevClass = charNonWord

  if sidx > 1 then
    prevClass = GetCharacterClass(text:byte(sidx - 1))
  end

  for index = sidx, eidx - 1 do
    local char = text:byte(index)
    local class = GetCharacterClass(char)

    if caseInsensitive and IsUpperCaseLetter(char) then
      char = char + 32
    end

    if char == pattern:byte(pidx) then
      local bonus = bonusFor(prevClass, class)
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
        score = score + bonus * bonusFirstCharMultiplier
      else
        score = score + bonus
      end

      inGap = false
      consecutive = consecutive + 1
      pidx = pidx + 1
    else
      if inGap then
        score = score + scoreGapExtention
      else
        score = score + scoreGapStart
      end

      inGap = true
      consecutive = 0
      firstBonus = 0
    end
    prevClass = class
  end

  if consecutive == #text then
    score = score + bonusExactMatch
  end

  return score
end

------------------------------------------
-- Exports
------------------------------------------

function export.FuzzyMatch(text, pattern, caseInsensitive)
  if #pattern == 0 then
    return 1, 1, 0
  end

  if caseInsensitive then
    pattern = pattern:lower()
  end

  local pidx = 1
  local sidx = 0
  local eidx = 0

  local lenText = #text
  local lenPattern = #pattern

  for index = 1, lenText do
    local char = text:byte(index)

    if caseInsensitive and IsUpperCaseLetter(char) then
      char = char + 32
    end

    local pchar = pattern:byte(pidx)

    if char == pchar then
      if sidx < 1 then
        sidx = index
      end

      pidx = pidx + 1
      if pidx > lenPattern then
        eidx = index + 1
        break
      end
    end
  end

  if sidx >= 1 and eidx >= 1 then
    pidx = pidx - 1
    for index = eidx - 1, sidx, -1 do
      char = text:byte(index)

      if caseInsensitive and IsUpperCaseLetter(char) then
        char = char + 32
      end

      local pchar = pattern:byte(pidx)

      if char == pchar then
        pidx = pidx - 1
        if pidx < 1 then
          sidx = index
          break
        end
      end
    end

    return sidx, eidx, EvaluateBonus(caseInsensitive, text, pattern, sidx, eidx)
  end

  return 0, 0, 0
end