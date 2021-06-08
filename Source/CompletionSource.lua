select(2, ...) 'CompletionSource'

-- Imports
local util = require 'Utility.Functions'
local FuzzyMatcher = require 'Utility.FuzzyMatcher'

------------------------------------------
-- Class definition
------------------------------------------

local CompletionSource = {}
CompletionSource.__index = CompletionSource

------------------------------------------
-- Constructor
------------------------------------------

-- Creates a chat autocomplete menu
function CompletionSource.New(source, taskScheduler, config)
  local self = setmetatable({}, CompletionSource)

  self.config = config
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

function CompletionSource:SetupTooltip(tooltip, entry)
  tooltip:SetHyperlink(entry.link)
end

------------------------------------------
-- Private methods
------------------------------------------

function CompletionSource:_TaskFilterEntries(options)
  local limit = options.limit or 1 / 0
  local pattern = options.pattern or ''
  local caseInsensitive = options.caseInsensitive
  local yieldCount = options.yieldCount or 1 / 0

  if caseInsensitive == nil then
    -- Use smart case (i.e only check casing if the pattern contains uppercase letters)
    caseInsensitive = not util.ContainsUppercase(pattern)
  end

  local fuzzyMatcher = FuzzyMatcher.New(pattern, caseInsensitive)
  local foundEntries = {}
  local iterations = 0

  -- The following is a trade-off between execution time & memory. Adding all
  -- entries to an array and sorting afterwards is O(nlogn), but requires a
  -- complete duplicate of all entries. A heap is good in theory but profiling
  -- shows it performs worst of all. The used solution is O(n²) due to the inner
  -- loop being O(n). Using binary search for the insertion point is also worse
  -- than insertion sort when a low 'limit' is used.
  for _, entry in self.source() do
    local startIndex, _, score = fuzzyMatcher:Match(entry.name)

    if startIndex ~= 0 then
      local insertionPoint = #foundEntries + 1
      while insertionPoint > 1 and score > foundEntries[insertionPoint - 1].score do
        insertionPoint = insertionPoint - 1
      end

      if insertionPoint <= limit then
        table.insert(foundEntries, insertionPoint, { entry = entry, score = score })

        if #foundEntries > limit then
          foundEntries[#foundEntries] = nil
        end
      end
    end

    iterations = iterations + 1
    if iterations % yieldCount == 0 then
      coroutine.yield()
    end
  end

  -- Return an iterator over all entries found
  local i = 0
  return function()
    i = i + 1
    return foundEntries[i] and foundEntries[i].entry
  end
end

------------------------------------------
-- Exports
------------------------------------------

export.New = function(...)
  return CompletionSource.New(...)
end
