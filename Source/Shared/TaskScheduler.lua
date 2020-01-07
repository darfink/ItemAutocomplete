select(2, ...) 'Shared.TaskScheduler'

------------------------------------------
-- Class definition
------------------------------------------

local TaskScheduler = {}
TaskScheduler.__index = TaskScheduler

------------------------------------------
-- Constructor
------------------------------------------

-- Creates a new task scheduler
function TaskScheduler.New()
  local self = setmetatable({}, TaskScheduler)

  self.updateFrame = CreateFrame('Frame')
  self.updateFrame:SetScript('OnUpdate', function() self:_OnUpdate() end)
  self.updateFrame:Hide()
  self.taskIncrementor = 1
  self.tasks = {}

  return self
end

------------------------------------------
-- Public methods
------------------------------------------

function TaskScheduler:Queue(info)
  local taskId = self.taskIncrementor
  self.tasks[taskId] = {
    onFinish = info.onFinish,
    thread = coroutine.create(info.task),
  }

  self.taskIncrementor = self.taskIncrementor + 1
  self.updateFrame:Show()

  return taskId
end

function TaskScheduler:Dequeue(taskId)
  if self.tasks[taskId] == nil then
    return false
  end

  self.tasks[taskId] = nil
  return true
end

function TaskScheduler:IsScheduled(taskId)
  return self.tasks[taskId] ~= nil
end

------------------------------------------
-- Private methods
------------------------------------------

function TaskScheduler:_OnUpdate()
  local activeTasks = 0

  for taskId, task in pairs(self.tasks) do
    local success, result = coroutine.resume(task.thread)

    if coroutine.status(task.thread) == 'dead' then
      self.tasks[taskId] = nil

      if not success then
        if task.onError ~= nil then
          task.onError(result)
        else
          error(result)
        end
      elseif task.onFinish ~= nil then
        task.onFinish(result)
      end
    else
      activeTasks = activeTasks + 1
    end
  end

  if activeTasks == 0 then
    self.updateFrame:Hide()
  end
end

------------------------------------------
-- Exports
------------------------------------------

export.New = function(...) return TaskScheduler.New(...) end