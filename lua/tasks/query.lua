local parser = require("tasks.parser")

local M = {}

local function today_str()
  return os.date("%Y-%m-%d")
end

--- Parse a single filter clause into a predicate function
---@param clause string
---@return function|nil predicate that takes a task and returns bool
local function parse_clause(clause)
  clause = vim.trim(clause)

  if clause == "not done" then
    return function(task)
      return not parser.is_done(task.status)
    end
  end

  if clause == "done" or clause == "is done" then
    return function(task)
      return parser.is_done(task.status)
    end
  end

  if clause == "due today" then
    return function(task)
      return task.due == today_str()
    end
  end

  if clause == "due before today" then
    return function(task)
      return task.due ~= nil and task.due < today_str()
    end
  end

  if clause == "due after today" then
    return function(task)
      return task.due ~= nil and task.due > today_str()
    end
  end

  if clause == "no due date" then
    return function(task)
      return task.due == nil
    end
  end

  -- Priority filters
  local prio = clause:match("^priority is (%w+)$")
  if prio then
    return function(task)
      return task.priority == prio
    end
  end

  -- has due date
  if clause == "has due date" then
    return function(task)
      return task.due ~= nil
    end
  end

  return nil -- unknown clause, skip
end

--- Parse a sort directive
---@param clause string
---@return function|nil comparator
local function parse_sort(clause)
  clause = vim.trim(clause)

  if clause == "sort by due" then
    return function(a, b)
      local ad = a.due or "9999-99-99"
      local bd = b.due or "9999-99-99"
      return ad < bd
    end
  end

  if clause == "sort by priority" then
    local prio_order = { highest = 1, high = 2, medium = 3, low = 4, lowest = 5 }
    return function(a, b)
      local ap = prio_order[a.priority] or 6
      local bp = prio_order[b.priority] or 6
      return ap < bp
    end
  end

  return nil
end

--- Evaluate a query string against a list of tasks
---@param query_text string the text between ```tasks fences
---@param tasks table[] list of parsed tasks
---@return table[] filtered and sorted tasks
function M.evaluate(query_text, tasks)
  local lines = vim.split(query_text, "\n")
  local filters = {}
  local sorter = nil
  local or_filters = {}

  for _, line in ipairs(lines) do
    line = vim.trim(line)
    if line == "" or line == "short mode" then
      goto continue
    end

    -- Check for sort directive
    local sort_fn = parse_sort(line)
    if sort_fn then
      sorter = sort_fn
      goto continue
    end

    -- Check for OR compound: (clause A) OR (clause B)
    local left, right = line:match("^%((.-)%)%s+OR%s+%((.-)%)$")
    if left and right then
      local left_fn = parse_clause(left)
      local right_fn = parse_clause(right)
      if left_fn and right_fn then
        table.insert(filters, function(task)
          return left_fn(task) or right_fn(task)
        end)
      end
      goto continue
    end

    -- Regular filter clause
    local pred = parse_clause(line)
    if pred then
      table.insert(filters, pred)
    end

    ::continue::
  end

  -- Apply all filters (AND logic)
  local result = {}
  for _, task in ipairs(tasks) do
    local pass = true
    for _, filter in ipairs(filters) do
      if not filter(task) then
        pass = false
        break
      end
    end
    if pass then
      table.insert(result, task)
    end
  end

  -- Apply sort
  if sorter then
    table.sort(result, sorter)
  end

  return result
end

return M
