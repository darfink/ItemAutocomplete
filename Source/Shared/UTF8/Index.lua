select(2, ...) 'Shared.UTF8'

local casing = require 'Shared.UTF8.Casing'
local charsets = require 'Shared.UTF8.Charsets'

------------------------------------------
-- Locals
------------------------------------------

local maxAscii = 127

local function CodePoint(string, offset)
  offset = offset or 1

  if offset > #string then
    return nil
  end

  local char = string:byte(offset)

  if char <= maxAscii then
    return offset + 1, char
  end

  local codePoint = nil
  local size = 1

  if char < 192 then
    error('Byte values between 0x80 to 0xBF cannot start a multibyte sequence')
  elseif char < 224 then
    codePoint = char % 32
    size = 2
  elseif char < 240 then
    codePoint = char % 16
    size = 3
  elseif char < 248 then
    codePoint = char % 8
    size = 4
  elseif char < 252 then
    codePoint = char % 4
    size = 5
  elseif char < 254 then
    codePoint = char % 2
    size = 6
  else
    error('Byte values between 0xFE and OxFF cannot start a multibyte sequence')
  end

  for _ = 2, size do
    offset = offset + 1
    char = string:byte(offset)

    if char <= maxAscii or char > 191 then
      error('Following bytes must have values between 0x80 and 0xBF')
    end

    codePoint = codePoint * 64 + (char % 64)
  end

  return offset + 1, codePoint
end

local function GetCharacterCodePoint(input)
  local inputType = type(input)

  if inputType == 'string' then
    local codePoint = select(2, CodePoint(input))
    assert(codePoint ~= nil, 'bad argument (expected letter)')
    return codePoint
  elseif inputType == 'number' then
    return input
  end

  error(string.format('bad argument (%s expected, got %s)', 'string/number', inputType))
end

------------------------------------------
-- Exports
------------------------------------------

-- The maxium value of an ASCII character
export.maxAscii = maxAscii

-- Returns an iterator of an UTF-8 string's codepoints
--
-- This is intentionally a stateless iterator to improve performance and avoid
-- allocations whilst iterating a string's code points. Profiling showed that
-- this halves the execution time of the fuzzy search algorithm. The downside is
-- that the index value returned by the iterator may not be what is expected;
-- it's the byte index of the *next* code point (not the current one).
function export.CodePoints(string)
  return CodePoint, string, 1
end

-- Returns whether the character is a letter or not
function export.IsLetter(input)
  return not not charsets.Letters[GetCharacterCodePoint(input)]
end

-- Returns whether the character is an upper case letter or not
function export.IsUpperCaseLetter(input)
  return not not charsets.UpperCaseLetters[GetCharacterCodePoint(input)]
end

-- Returns whether the character is a lower case letter or not
function export.IsLowerCaseLetter(input)
  return not not charsets.LowerCaseLetters[GetCharacterCodePoint(input)]
end

-- Returns whether the character is a digit or not
function export.IsDigit(input)
  return not not charsets.Digits[GetCharacterCodePoint(input)]
end

-- Converts a character to lower case
function export.ToLower(input)
  if type(input) ~= 'number' then
    error('not implemented')
  end

  if input >= 65 and input <= 90 then
    return input + 32
  elseif input > maxAscii then
    return casing.UpperToLowerByCodePoint[input] or input
  end

  return input
end