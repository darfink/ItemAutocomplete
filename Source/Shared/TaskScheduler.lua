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
  self.updateFrame:SetScript('OnUpdate', function()
    self:_OnUpdate()
  end)
  self.updateFrame:Hide()
  self.taskIncrementor = 1
  self.tasks = {}

  return self
end

------------------------------------------
-- Public methods
------------------------------------------

function TaskScheduler:Enqueue(info)
  local taskId = self.taskIncrementor
  self.tasks[taskId] = {
    onError = info.onError,
    onFinish = info.onFinish,
    thread = coroutine.create(info.task),
  }

  self.taskIncrementor = self.taskIncrementor + 1
  self.updateFrame:Show()

  return taskId
end

function TaskScheduler:Dequeue(taskId)
  if taskId == nil or self.tasks[taskId] == nil then
    return false
  end

  self.tasks[taskId] = nil
  return true
end

function TaskScheduler:IsScheduled(taskId)
  return taskId ~= nil and self.tasks[taskId] ~= nil
end

------------------------------------------
-- Private methods
------------------------------------------

function TaskScheduler:_OnUpdate()
  local finishedTasks = {}

  for taskId, task in pairs(self.tasks) do
    local success, result = coroutine.resume(task.thread)

    if coroutine.status(task.thread) == 'dead' then
      self.tasks[taskId] = nil
      finishedTasks[#finishedTasks + 1] = { task = task, success = success, result = result }
    end
  end

  -- Callbacks run once the iteration is complete, since they may enqueue new
  -- tasks and adding keys to a table whilst traversing it is undefined.
  for _, finished in ipairs(finishedTasks) do
    local task = finished.task

    if not finished.success then
      if task.onError ~= nil then
        task.onError(finished.result)
      else
        geterrorhandler()(finished.result)
      end
    elseif task.onFinish ~= nil then
      task.onFinish(finished.result)
    end
  end

  if next(self.tasks) == nil then
    self.updateFrame:Hide()
  end
end

------------------------------------------
-- Exports
------------------------------------------

export.New = function(...)
  return TaskScheduler.New(...)
end
