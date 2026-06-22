local parser = require("tasks.parser")

local M = {}

--- Slugify a string for use as a filename
---@param str string
---@return string
local function slugify(str)
  local slug = str:lower()
  slug = slug:gsub("[^%w%s-]", "")
  slug = slug:gsub("%s+", "-")
  slug = slug:gsub("%-+", "-")
  slug = slug:gsub("^%-+", "")
  slug = slug:gsub("%-+$", "")
  return slug
end

--- Resolve natural language date input to YYYY-MM-DD
---@param input string date input like "tomorrow", "today", "next week", or "2026-03-25"
---@return string|nil resolved date string, or nil if empty
local function resolve_date(input)
  if not input or input == "" then
    return nil
  end

  -- Already a date in YYYY-MM-DD format
  if input:match("^%d%d%d%d%-%d%d%-%d%d$") then
    return input
  end

  local now = os.time()
  local day = 86400 -- seconds in a day

  local aliases = {
    ["today"] = 0,
    ["tomorrow"] = 1,
    ["tmr"] = 1,
    ["tmrw"] = 1,
    ["yesterday"] = -1,
    ["next week"] = 7,
    ["next monday"] = nil, -- handled below
  }

  local offset = aliases[input:lower()]
  if offset then
    return os.date("%Y-%m-%d", now + offset * day)
  end

  -- "+Nd" or "+N" for N days from now
  local days = input:match("^%+(%d+)d?$")
  if days then
    return os.date("%Y-%m-%d", now + tonumber(days) * day)
  end

  -- If nothing matched, return as-is (user might have typed a partial date)
  vim.notify("tasks: could not parse date '" .. input .. "', using as-is", vim.log.levels.WARN)
  return input
end

--- Set a task's status in its source file
---@param task table parsed task
---@param new_status string the new status character
function M.set_task_status(task, new_status)
  if not task.source_file or not task.source_line then
    vim.notify("tasks: no source location for task", vim.log.levels.WARN)
    return
  end

  -- Check if the file is open in a buffer
  local bufnr = vim.fn.bufnr(task.source_file)
  local line_content

  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    -- Read from buffer
    local lines = vim.api.nvim_buf_get_lines(bufnr, task.source_line - 1, task.source_line, false)
    if #lines == 0 then
      return
    end
    line_content = lines[1]
  else
    -- Read from file
    local file_lines = vim.fn.readfile(task.source_file)
    if task.source_line > #file_lines then
      return
    end
    line_content = file_lines[task.source_line]
  end

  -- Replace the status character in the checkbox
  local new_line = line_content:gsub("%- %[.%]", "- [" .. new_status .. "]", 1)

  -- Handle completion date
  local today = os.date("%Y-%m-%d")
  if new_status == "x" or new_status == "-" then
    -- Add completion date if not present
    if not new_line:match("%[completion::") then
      new_line = new_line .. "  [completion:: " .. today .. "]"
    end
  else
    -- Remove completion date
    new_line = new_line:gsub("%s*%[completion::%s*[^%]]+%]", "")
  end

  -- Write back
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    vim.api.nvim_buf_set_lines(bufnr, task.source_line - 1, task.source_line, false, { new_line })
    -- Mark buffer as modified so the user knows to save
    vim.bo[bufnr].modified = true
  else
    local file_lines = vim.fn.readfile(task.source_file)
    file_lines[task.source_line] = new_line
    vim.fn.writefile(file_lines, task.source_file)
  end

  -- Update the task object in-place
  task.status = new_status
  task.raw = new_line
  if new_status == "x" or new_status == "-" then
    task.completion = today
  else
    task.completion = nil
  end
end

--- Set a task's due date in its source file
---@param task table parsed task
---@param new_due string|nil new due date (YYYY-MM-DD) or nil to remove
function M.set_task_due(task, new_due)
  if not task.source_file or not task.source_line then
    vim.notify("tasks: no source location for task", vim.log.levels.WARN)
    return
  end

  local bufnr = vim.fn.bufnr(task.source_file)
  local line_content

  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    local lines = vim.api.nvim_buf_get_lines(bufnr, task.source_line - 1, task.source_line, false)
    if #lines == 0 then return end
    line_content = lines[1]
  else
    local file_lines = vim.fn.readfile(task.source_file)
    if task.source_line > #file_lines then return end
    line_content = file_lines[task.source_line]
  end

  local new_line
  if new_due then
    if line_content:match("%[due::") then
      -- Replace existing due date
      new_line = line_content:gsub("%[due::%s*[^%]]+%]", "[due:: " .. new_due .. "]")
    else
      -- Add due date before completion or at end
      local insert_pos = line_content:find("%s+%[completion::")
      if insert_pos then
        new_line = line_content:sub(1, insert_pos - 1) .. "  [due:: " .. new_due .. "]" .. line_content:sub(insert_pos)
      else
        new_line = line_content .. "  [due:: " .. new_due .. "]"
      end
    end
  else
    -- Remove due date
    new_line = line_content:gsub("%s*%[due::%s*[^%]]+%]", "")
  end

  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    vim.api.nvim_buf_set_lines(bufnr, task.source_line - 1, task.source_line, false, { new_line })
    vim.bo[bufnr].modified = true
    -- Auto-save
    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd("silent! write")
    end)
  else
    local file_lines = vim.fn.readfile(task.source_file)
    file_lines[task.source_line] = new_line
    vim.fn.writefile(file_lines, task.source_file)
  end

  task.due = new_due
  task.raw = new_line
end

--- Prompt for due date and set it on a task
---@param task table parsed task
---@param callback function|nil called after setting (for UI refresh)
function M.prompt_due_date(task, callback)
  local current = task.due or ""
  vim.ui.input({
    prompt = "Due (YYYY-MM-DD/today/tomorrow/+3d, empty to remove): ",
    default = current,
  }, function(input)
    if input == nil then return end -- cancelled
    local new_due = resolve_date(input)
    M.set_task_due(task, new_due)
    if callback then callback() end
  end)
end

--- Read a task's source line from buffer or file
---@param task table parsed task
---@return string|nil line_content
---@return number|nil bufnr (-1 if read from file)
local function read_task_line(task)
  if not task.source_file or not task.source_line then return nil, nil end
  local bufnr = vim.fn.bufnr(task.source_file)
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    local lines = vim.api.nvim_buf_get_lines(bufnr, task.source_line - 1, task.source_line, false)
    if #lines == 0 then return nil, nil end
    return lines[1], bufnr
  else
    local file_lines = vim.fn.readfile(task.source_file)
    if task.source_line > #file_lines then return nil, nil end
    return file_lines[task.source_line], -1
  end
end

--- Write a line back to the task's source
local function write_task_line(task, new_line, bufnr)
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    vim.api.nvim_buf_set_lines(bufnr, task.source_line - 1, task.source_line, false, { new_line })
    vim.bo[bufnr].modified = true
    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd("silent! write")
    end)
  else
    local file_lines = vim.fn.readfile(task.source_file)
    file_lines[task.source_line] = new_line
    vim.fn.writefile(file_lines, task.source_file)
  end
  task.raw = new_line
end

--- Full edit workflow for a task: description, due, priority.
--- Renames linked note file if description changes.
---@param task table parsed task
---@param config table plugin config
---@param callback function|nil called after edit
function M.edit_task(task, config, callback)
  if not task.source_file or not task.source_line then
    vim.notify("tasks: no source location for task", vim.log.levels.WARN)
    return
  end

  -- Step 1: Description
  vim.ui.input({
    prompt = "Description: ",
    default = task.description,
  }, function(new_desc)
    if new_desc == nil then return end -- cancelled
    if new_desc == "" then new_desc = task.description end

    -- Step 2: Due date
    vim.ui.input({
      prompt = "Due (YYYY-MM-DD/today/tomorrow/+3d, empty to remove): ",
      default = task.due or "",
    }, function(due_input)
      if due_input == nil then return end -- cancelled

      -- Step 3: Priority
      vim.ui.input({
        prompt = "Priority (highest/high/medium/low/lowest, empty to remove): ",
        default = task.priority or "",
      }, function(prio_input)
        if prio_input == nil then return end -- cancelled

        M.apply_task_edit(task, config, new_desc, due_input, prio_input)
        if callback then callback() end
      end)
    end)
  end)
end

--- Apply edits to a task from already-collected input values.
---@param task table parsed task
---@param config table plugin config
---@param new_desc string new description
---@param due_input string raw due input
---@param prio_input string raw priority input
function M.apply_task_edit(task, config, new_desc, due_input, prio_input)
  local new_due = resolve_date(due_input)
  local new_priority = (prio_input ~= "") and prio_input or nil

  local line_content, bufnr = read_task_line(task)
  if not line_content then return end

  local new_line = line_content
  local desc_changed = new_desc ~= task.description

  if desc_changed then
    local escaped_old = task.description:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    -- Escape % in the replacement so descriptions containing % don't break gsub.
    local escaped_new = new_desc:gsub("%%", "%%%%")
    new_line = new_line:gsub(escaped_old, escaped_new, 1)
  end

  if new_due ~= task.due then
    if new_due then
      if new_line:match("%[due::") then
        new_line = new_line:gsub("%[due::%s*[^%]]+%]", "[due:: " .. new_due .. "]")
      else
        local insert_pos = new_line:find("%s+%[completion::")
        if insert_pos then
          new_line = new_line:sub(1, insert_pos - 1) .. "  [due:: " .. new_due .. "]" .. new_line:sub(insert_pos)
        else
          new_line = new_line .. "  [due:: " .. new_due .. "]"
        end
      end
    else
      new_line = new_line:gsub("%s*%[due::%s*[^%]]+%]", "")
    end
  end

  if new_priority ~= task.priority then
    if new_priority then
      if new_line:match("%[priority::") then
        new_line = new_line:gsub("%[priority::%s*[^%]]+%]", "[priority:: " .. new_priority .. "]")
      else
        local insert_pos = new_line:find("%s+%[completion::")
        if insert_pos then
          new_line = new_line:sub(1, insert_pos - 1) .. "  [priority:: " .. new_priority .. "]" .. new_line:sub(insert_pos)
        else
          new_line = new_line .. "  [priority:: " .. new_priority .. "]"
        end
      end
    else
      new_line = new_line:gsub("%s*%[priority::%s*[^%]]+%]", "")
    end
  end

  if desc_changed and task.note_link then
    local old_path = parser.resolve_note_path(task.note_link, config.vault_path)
    local new_slug = slugify(new_desc)
    local new_note_link = "/" .. config.tasks_path .. "/" .. new_slug
    local new_path = parser.resolve_note_path(new_note_link, config.vault_path)

    if old_path ~= new_path and vim.fn.filereadable(old_path) == 1 then
      vim.fn.mkdir(vim.fn.fnamemodify(new_path, ":h"), "p")
      vim.fn.rename(old_path, new_path)

      local note_lines = vim.fn.readfile(new_path)
      if #note_lines > 0 and note_lines[1]:match("^# ") then
        note_lines[1] = "# " .. new_desc
        vim.fn.writefile(note_lines, new_path)
      end

      local old_bufnr = vim.fn.bufnr(old_path)
      if old_bufnr ~= -1 then
        vim.api.nvim_buf_delete(old_bufnr, { force = true })
      end

      local escaped_old_link = task.note_link:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
      new_line = new_line:gsub("%[%[" .. escaped_old_link .. "%]%]", "[[" .. new_note_link .. "]]")
      task.note_link = new_note_link
    end
  end

  write_task_line(task, new_line, bufnr)
  task.description = new_desc
  task.due = new_due
  task.priority = new_priority
end

--- Toggle the task on the current line in the current buffer
function M.toggle_current_line()
  local line = vim.api.nvim_get_current_line()
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local task = parser.parse(line)

  if not task then
    -- Not a task line, fall back to vimwiki toggle
    local ok = pcall(vim.cmd, "VimwikiToggleListItem")
    if not ok then
      vim.notify("tasks: not a task line", vim.log.levels.INFO)
    end
    return
  end

  local new_status = parser.next_status(task.status)
  task.source_file = vim.api.nvim_buf_get_name(0)
  task.source_line = lnum
  M.set_task_status(task, new_status)
end

--- Create a note file with a template
---@param note_path string absolute path to the note file
---@param title string task description to use as the note title
function M.create_note_file(note_path, title)
  -- Ensure parent directory exists
  local dir = vim.fn.fnamemodify(note_path, ":h")
  vim.fn.mkdir(dir, "p")

  local template = {
    "# " .. title,
    "",
    "## Context",
    "",
    "",
    "",
    "## Notes",
    "",
    "",
  }

  vim.fn.writefile(template, note_path)
end

--- Add a note link to an existing task (creates the note file and updates the task line)
---@param task table parsed task
---@param config table plugin config
function M.add_note_to_task(task, config)
  if not task.source_file or not task.source_line then
    vim.notify("tasks: no source location for task", vim.log.levels.WARN)
    return
  end

  -- Generate note path from task description
  local slug = slugify(task.description)
  local note_link = "/" .. config.tasks_path .. "/" .. slug
  local note_path = parser.resolve_note_path(note_link, config.vault_path)

  -- Create the note file
  M.create_note_file(note_path, task.description)

  -- Update the task line to include the wiki-link
  local bufnr = vim.fn.bufnr(task.source_file)
  local line_content

  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    local lines = vim.api.nvim_buf_get_lines(bufnr, task.source_line - 1, task.source_line, false)
    if #lines == 0 then
      return
    end
    line_content = lines[1]
  else
    local file_lines = vim.fn.readfile(task.source_file)
    if task.source_line > #file_lines then
      return
    end
    line_content = file_lines[task.source_line]
  end

  -- Insert [[note-link]] before the first metadata field or at end of description
  local new_line
  local meta_pos = line_content:find("%s+%[%w+::")
  if meta_pos then
    new_line = line_content:sub(1, meta_pos - 1) .. " [[" .. note_link .. "]]" .. line_content:sub(meta_pos)
  else
    new_line = line_content .. " [[" .. note_link .. "]]"
  end

  -- Write back
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    vim.api.nvim_buf_set_lines(bufnr, task.source_line - 1, task.source_line, false, { new_line })
    vim.bo[bufnr].modified = true
  else
    local file_lines = vim.fn.readfile(task.source_file)
    file_lines[task.source_line] = new_line
    vim.fn.writefile(file_lines, task.source_file)
  end

  vim.notify("tasks: note created at " .. note_link, vim.log.levels.INFO)

  -- Save the buffer so rg picks up the wiki-link
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].modified then
    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd("silent! write")
    end)
  end

  -- Update task object in-place
  task.note_link = note_link

  return note_path
end

--- Same as add_note_to_task but also opens the note in current buffer
function M.add_note_to_task_and_open(task, config)
  local note_path = M.add_note_to_task(task, config)
  if note_path then
    vim.cmd("edit " .. vim.fn.fnameescape(note_path))
  end
end

--- Create a new task interactively
---@param config table plugin config
---@param callback function|nil called after task is created (for dashboard refresh)
function M.create_task(config, callback)
  vim.ui.input({ prompt = "Task description: " }, function(desc)
    if not desc or desc == "" then
      return
    end

    vim.ui.input({ prompt = "Due (YYYY-MM-DD/today/tomorrow/+3d, empty for none): " }, function(due_raw)
      vim.ui.input({ prompt = "Priority (high/medium/low, empty for none): " }, function(priority)
        vim.ui.input({ prompt = "Create linked note? (y/n, default n): " }, function(create_note)
          local due = resolve_date(due_raw)

          local note_link = nil
          if create_note == "y" then
            local slug = slugify(desc)
            note_link = "/" .. config.tasks_path .. "/" .. slug
            local note_path = parser.resolve_note_path(note_link, config.vault_path)
            M.create_note_file(note_path, desc)
          end

          local parts = { "- [ ] #task " .. desc }

          if note_link then
            table.insert(parts, " [[" .. note_link .. "]]")
          end

          if due then
            table.insert(parts, "  [due:: " .. due .. "]")
          end

          if priority and priority ~= "" then
            table.insert(parts, "  [priority:: " .. priority .. "]")
          end

          local task_line = table.concat(parts)

          -- Append to today's diary
          local diary_path = vim.fn.expand(config.diary_path)
          local today = os.date("%Y-%m-%d")
          local diary_file = diary_path .. "/" .. today .. ".md"

          if vim.fn.filereadable(diary_file) == 1 then
            local file_lines = vim.fn.readfile(diary_file)
            table.insert(file_lines, task_line)
            vim.fn.writefile(file_lines, diary_file)
          else
            vim.fn.writefile({ "# " .. today, "", task_line }, diary_file)
          end

          vim.notify("tasks: task created in " .. today .. ".md", vim.log.levels.INFO)

          -- Reload the diary buffer if it's open
          local bufnr = vim.fn.bufnr(diary_file)
          if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
            vim.api.nvim_buf_call(bufnr, function()
              vim.cmd("edit!")
            end)
          end

          if callback then
            callback()
          else
            -- Refresh dashboard if open (standalone :TaskCreate)
            local ui = require("tasks.ui")
            if ui then
              pcall(ui.refresh)
            end

            -- If note was created, open it
            if note_link then
              local note_path = parser.resolve_note_path(note_link, config.vault_path)
              vim.cmd("edit " .. vim.fn.fnameescape(note_path))
            end
          end
        end)
      end)
    end)
  end)
end

return M
