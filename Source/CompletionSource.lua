select(2, ...) 'CompletionSource'

-- Imports
local util = require 'Utility.Functions'
local utf8 = require 'Shared.UTF8'
local FuzzyMatcher = require 'Utility.FuzzyMatcher'

------------------------------------------
-- Private locals
------------------------------------------

-- Decodes a string's code points into a reusable array, returning its length
local function DecodeCodePoints(codePoints, previousCount, text)
  local count = 0

  for _, codePoint in utf8.CodePoints(text) do
    count = count + 1
    codePoints[count] = codePoint
  end

  for index = count + 1, previousCount do
    codePoints[index] = nil
  end

  return count
end

------------------------------------------
-- Class definition
------------------------------------------

local CompletionSource = {}
CompletionSource.__index = CompletionSource

------------------------------------------
-- Constructor
------------------------------------------

-- Creates a completion source
--
-- The source is a function returning an array of keys, and a table with the
-- name of each key. The array may only be appended to.
function CompletionSource.New(source, taskScheduler, config)
  local self = setmetatable({}, CompletionSource)

  self.config = config
  self.lastQuery = nil
  self.lowerCaseNames = {}
  self.lowerCaseNamesSource = nil
  self.methods = util.ContextBinder(self)
  self.source = source
  self.taskId = nil
  self.taskScheduler = taskScheduler

  return self
end

------------------------------------------
-- Public methods
------------------------------------------

function CompletionSource:QueryAsync(pattern, callback)
  self.taskScheduler:Dequeue(self.taskId)
  self.taskId = self.taskScheduler:Enqueue({
    onFinish = callback,
    task = function()
      return self:_TaskFilterEntries({
        limit = self.config.entriesDisplayed,
        pattern = pattern,
        caseInsensitive = self.config.caseInsensitive,
        yieldCount = self.config.entriesFilteredPerUpdate,
      })
    end,
  })
end

-- Returns the text inserted when an entry is selected
function CompletionSource:GetEntryLink(key)
  local _, names = self.source()
  return names[key]
end

function CompletionSource:SetupTooltip(tooltip, key)
  tooltip:SetHyperlink(self:GetEntryLink(key))
end

------------------------------------------
-- Private methods
------------------------------------------

function CompletionSource:_GetLowerCaseName(names, key)
  -- The cache is tied to the names table, which is replaced on a rebuild
  if self.lowerCaseNamesSource ~= names then
    self.lowerCaseNames = {}
    self.lowerCaseNamesSource = names
  end

  local lowerCaseName = self.lowerCaseNames[key]

  if lowerCaseName == nil then
    lowerCaseName = utf8.ToLowerString(names[key])
    self.lowerCaseNames[key] = lowerCaseName
  end

  return lowerCaseName
end

-- Returns the keys to search, and the keys matched by them
--
-- As long as the user keeps typing, a pattern extends the previous one, and
-- can only match what the previous one did. Only those keys and any added
-- since are searched, which narrows the search with every keystroke.
function CompletionSource:_GetSearchKeys(keys, names, pattern, caseInsensitive)
  local lastQuery = self.lastQuery
  local candidates = {}
  local query = {
    candidates = candidates,
    caseInsensitive = caseInsensitive,
    keyCount = #keys,
    names = names,
    pattern = pattern,
  }

  if lastQuery ~= nil and lastQuery.names == names and lastQuery.caseInsensitive ==
    caseInsensitive and pattern:sub(1, #lastQuery.pattern) == lastQuery.pattern then
    local searchKeys = lastQuery.candidates

    if query.keyCount > lastQuery.keyCount then
      searchKeys = {}

      for index = 1, #lastQuery.candidates do
        searchKeys[index] = lastQuery.candidates[index]
      end

      for index = lastQuery.keyCount + 1, query.keyCount do
        searchKeys[#searchKeys + 1] = keys[index]
      end
    end

    return searchKeys, #searchKeys, query
  end

  return keys, query.keyCount, query
end

function CompletionSource:_TaskFilterEntries(options)
  local limit = options.limit or 1 / 0
  local pattern = options.pattern or ''
  local caseInsensitive = options.caseInsensitive
  local yieldCount = options.yieldCount or 1 / 0

  if caseInsensitive == nil then
    -- Use smart case (i.e only check casing if the pattern contains uppercase letters)
    caseInsensitive = not util.ContainsUppercase(pattern)
  end

  local keys, names = self.source()
  local searchKeys, searchKeyCount, query = self:_GetSearchKeys(keys, names, pattern,
                                                                caseInsensitive)
  local candidates = query.candidates
  local fuzzyMatcher = FuzzyMatcher.New(pattern, caseInsensitive)
  local codePoints, codePointCount = {}, 0
  local foundEntries = {}

  -- The following is a trade-off between execution time & memory. Adding all
  -- entries to an array and sorting afterwards is O(nlogn), but requires a
  -- complete duplicate of all entries. A heap is good in theory but profiling
  -- shows it performs worst of all. The used solution is O(n²) due to the inner
  -- loop being O(n). Using binary search for the insertion point is also worse
  -- than insertion sort when a low 'limit' is used.
  for index = 1, searchKeyCount do
    local key = searchKeys[index]
    local name = names[key]
    local text = caseInsensitive and self:_GetLowerCaseName(names, key) or name

    -- Most names are rejected here, without decoding them
    if fuzzyMatcher:IsSubsequenceOf(text) then
      candidates[#candidates + 1] = key
      codePointCount = DecodeCodePoints(codePoints, codePointCount, name)

      local startIndex, _, score = fuzzyMatcher:Match(codePoints)

      if startIndex ~= 0 then
        local insertionPoint = #foundEntries + 1
        while insertionPoint > 1 do
          local previousEntry = foundEntries[insertionPoint - 1]

          -- Equal scores favour the shorter name, i.e the closer match
          if score > previousEntry.score or
            (score == previousEntry.score and #name < #names[previousEntry.key]) then
            insertionPoint = insertionPoint - 1
          else
            break
          end
        end

        if insertionPoint <= limit then
          table.insert(foundEntries, insertionPoint, { key = key, score = score })

          if #foundEntries > limit then
            foundEntries[#foundEntries] = nil
          end
        end
      end
    end

    if index % yieldCount == 0 then
      coroutine.yield()
    end
  end

  -- Only a completed query can narrow the next one
  self.lastQuery = query

  -- Return an iterator over all entries found
  local i = 0
  return function()
    i = i + 1
    return foundEntries[i] and foundEntries[i].key
  end
end

------------------------------------------
-- Exports
------------------------------------------

export.New = function(...)
  return CompletionSource.New(...)
end
