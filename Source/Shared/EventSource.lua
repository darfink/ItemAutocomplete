select(2, ...) 'Shared.EventSource'

------------------------------------------
-- Class definition
------------------------------------------

local EventSource = {}
EventSource.__index = EventSource

------------------------------------------
-- Constructor
------------------------------------------

-- Creates a new event source
function EventSource.New(frame)
  local self = setmetatable({}, EventSource)

  self.frame = frame or CreateFrame('Frame')
  self.frame:SetScript('OnEvent', function(_, event, ...)
    self:_OnEvent(event, ...)
  end)
  self.eventListeners = {}

  return self
end

------------------------------------------
-- Public methods
------------------------------------------

-- Adds a new listener for an event
function EventSource:AddListener(event, listener)
  if self.eventListeners[event] == nil then
    self.frame:RegisterEvent(event)
    self.eventListeners[event] = {}
  end

  self.eventListeners[event][listener] = true
end

-- Removes an existing listener from an event
function EventSource:RemoveListener(event, listener)
  if self.eventListeners[event] == nil then
    return
  end

  self.eventListeners[event][listener] = nil

  if next(self.eventListeners[event]) == nil then
    self.frame:UnregisterEvent(event)
    self.eventListeners[event] = nil
  end
end

------------------------------------------
-- Private methods
------------------------------------------

function EventSource:_OnEvent(event, ...)
  -- Listeners may add or remove listeners, so iterate a copy
  local listeners = {}
  for listener, _ in pairs(self.eventListeners[event] or {}) do
    listeners[#listeners + 1] = listener
  end

  for _, listener in ipairs(listeners) do
    listener(...)
  end
end

------------------------------------------
-- Exports
------------------------------------------

export.New = function(...)
  return EventSource.New(...)
end
