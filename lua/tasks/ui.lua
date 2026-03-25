local query = require("tasks.query")
local scanner = require("tasks.scanner")
local parser = require("tasks.parser")

local M = {}

local state = {
  buf = nil,
  win = nil,
  search_buf = nil,
  search_win = nil,
  tasks_by_line = {},
  all_tasks = {},
  config = nil,
  custom_query = nil,
  filter_text = nil,
  -- note view state
  note_path = nil,
  note_task = nil,
  note_buf = nil,
  dashboard_buf = nil,
  -- layout
  layout = { row = 0, col = 0, width = 0, height = 0 },
}

-- ── helpers ──────────────────────────────────────────────────────────

local function get_symbol(status, config)
  local symbols = config.symbols
  local map = {
    [" "] = symbols.todo,
    ["/"] = symbols.in_progress,
    ["x"] = symbols.done,
    ["-"] = symbols.cancelled,
  }
  return map[status] or symbols.todo
end

local function get_task_highlight(task)
  if task.status == "x" then return "NTasksDone" end
  if task.status == "-" then return "NTasksCancelled" end
  local today = os.date("%Y-%m-%d")
  if task.due then
    if task.due < today then return "NTasksOverdue" end
    if task.due == today then return "NTasksDueToday" end
  end
  return "NTasksPending"
end

local function get_symbol_highlight(status)
  local map = {
    [" "] = "NTasksSymbolTodo",
    ["/"] = "NTasksSymbolProgress",
    ["x"] = "NTasksSymbolDone",
    ["-"] = "NTasksSymbolCancelled",
  }
  return map[status] or "NTasksSymbolTodo"
end

local function get_due_highlight(task)
  if not task.due then return "NTasksDueDateFuture" end
  local today = os.date("%Y-%m-%d")
  if task.due < today then return "NTasksDueDateOverdue" end
  if task.due == today then return "NTasksDueDateToday" end
  return "NTasksDueDateFuture"
end

local function format_due_short(due)
  if not due then return "" end
  local y, m, d = due:match("(%d+)-(%d+)-(%d+)")
  if not y then return due end
  local months = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
  return months[tonumber(m)] .. " " .. tonumber(d)
end

local function fuzzy_match(str, pattern)
  if not pattern or pattern == "" then return true end
  local lower_str = str:lower()
  local lower_pat = pattern:lower()
  local si = 1
  for pi = 1, #lower_pat do
    local ch = lower_pat:sub(pi, pi)
    local found = lower_str:find(ch, si, true)
    if not found then return false end
    si = found + 1
  end
  return true
end

local function filter_tasks(tasks, filter)
  if not filter or filter == "" then return tasks end
  local result = {}
  for _, task in ipairs(tasks) do
    local searchable = task.description .. " " .. (task.due or "") .. " " .. (task.priority or "")
    for _, tag in ipairs(task.tags) do
      searchable = searchable .. " " .. tag
    end
    if fuzzy_match(searchable, filter) then
      table.insert(result, task)
    end
  end
  return result
end

-- ── render ───────────────────────────────────────────────────────────

function M.render(config, all_tasks, filter_text)
  local lines = {}
  local highlights = {}
  local task_line_map = {}

  local title = "  Tasks"
  local date_str = os.date("%Y-%m-%d")
  local right_side = date_str .. "  "
  local padding = config._inner_width - #title - #right_side
  if padding < 1 then padding = 1 end
  table.insert(lines, title .. string.rep(" ", padding) .. right_side)
  table.insert(highlights, { #lines, 0, #title, "NTasksTitle" })

  table.insert(lines, "  " .. string.rep("─", config._inner_width - 4) .. "  ")
  table.insert(highlights, { #lines, 0, #lines[#lines], "NTasksBorder" })
  table.insert(lines, "")

  for _, section in ipairs(config.sections) do
    local filtered = query.evaluate(section.query, all_tasks)
    filtered = filter_tasks(filtered, filter_text)

    local header = "  " .. section.name
    table.insert(lines, header)
    table.insert(highlights, { #lines, 0, #header, "NTasksHeader" })

    if #filtered == 0 then
      table.insert(lines, "    (none)")
      table.insert(highlights, { #lines, 0, #lines[#lines], "NTasksCount" })
    else
      local date_col = config._inner_width - 10

      for _, task in ipairs(filtered) do
        local symbol = get_symbol(task.status, config)
        local desc = task.description
        local note_indicator = task.note_link and " 📎" or ""
        local due_str = format_due_short(task.due)

        local left = "  " .. symbol .. " " .. desc .. note_indicator
        local left_display_width = vim.fn.strdisplaywidth(left)

        if left_display_width > date_col - 2 then
          local avail = date_col - 4 - vim.fn.strdisplaywidth("  " .. symbol .. " ") - vim.fn.strdisplaywidth(note_indicator)
          if avail > 3 then
            desc = vim.fn.strcharpart(desc, 0, avail) .. "…"
          end
          left = "  " .. symbol .. " " .. desc .. note_indicator
          left_display_width = vim.fn.strdisplaywidth(left)
        end

        local pad = math.max(date_col - left_display_width - vim.fn.strdisplaywidth(due_str), 1)
        local task_line = left .. string.rep(" ", pad) .. due_str

        table.insert(lines, task_line)
        local ln = #lines
        task_line_map[ln] = task

        local sym_byte_end = #("  " .. symbol)
        table.insert(highlights, { ln, 2, sym_byte_end, get_symbol_highlight(task.status) })
        local desc_byte_start = sym_byte_end + 1
        local desc_byte_end = desc_byte_start + #desc
        table.insert(highlights, { ln, desc_byte_start, desc_byte_end, get_task_highlight(task) })
        if due_str ~= "" then
          local due_byte_start = #task_line - #due_str
          table.insert(highlights, { ln, due_byte_start, #task_line, get_due_highlight(task) })
        end
      end
    end

    local count_str = "  " .. #filtered .. " task" .. (#filtered ~= 1 and "s" or "")
    table.insert(lines, count_str)
    table.insert(highlights, { #lines, 0, #count_str, "NTasksCount" })
    table.insert(lines, "")
  end

  local help = "  x:done p:prog -:cancel ␣:todo d:due /:search ⏎:context o:src n:new r:refresh q:close"
  table.insert(lines, help)
  table.insert(highlights, { #lines, 0, #help, "NTasksHelp" })

  return lines, highlights, task_line_map
end

function M.close_preview() end

-- ── note view (editable, in same float) ──────────────────────────────

function M.show_note_inline(task)
  if not state.win or not vim.api.nvim_win_is_valid(state.win) then return end

  -- Close preview since note takes over the float
  M.close_preview()

  local config = state.config
  local note_path = parser.resolve_note_path(task.note_link, config.vault_path)

  if vim.fn.filereadable(note_path) ~= 1 then
    require("tasks.actions").create_note_file(note_path, task.description)
  end

  -- Stash dashboard buffer
  state.dashboard_buf = state.buf

  -- Load the note as a real file buffer
  local note_buf = vim.fn.bufadd(note_path)
  vim.fn.bufload(note_buf)

  -- Swap buffer in the float
  vim.api.nvim_win_set_buf(state.win, note_buf)
  state.buf = note_buf
  state.note_buf = note_buf
  state.note_path = note_path
  state.note_task = task

  vim.wo[state.win].wrap = true
  vim.wo[state.win].cursorline = true

  vim.api.nvim_win_set_config(state.win, {
    title = " " .. task.note_link .. " [w:save+back  ⏎:open full] ",
    title_pos = "center",
  })

  -- Set keymaps AFTER filetype detection completes (vim.schedule)
  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(note_buf) then return end

    local opts = { buffer = note_buf, noremap = true, silent = true, nowait = true }

    -- <CR> in normal mode: open in full buffer
    vim.keymap.set("n", "<CR>", function()
      if vim.bo[note_buf].modified then
        vim.cmd("silent! write")
      end
      local np = state.note_path
      M.close()
      vim.cmd("edit " .. vim.fn.fnameescape(np))
    end, opts)

    -- <leader>w: save and go back to dashboard
    vim.keymap.set("n", "<leader>w", function()
      M.save_and_back()
    end, opts)

    -- Buffer-local commands for note view
    vim.api.nvim_buf_create_user_command(note_buf, "W", function()
      M.save_and_back()
    end, { desc = "Save note and return to task list" })

    -- :w saves and goes back to dashboard
    vim.api.nvim_create_autocmd("BufWritePost", {
      buffer = note_buf,
      callback = function()
        if state.note_path and state.win and vim.api.nvim_win_is_valid(state.win) then
          vim.schedule(function()
            M.restore_dashboard()
          end)
        end
      end,
    })

    -- :q in note view goes back to dashboard (save first if modified)
    vim.keymap.set("c", "<CR>", function()
      local cmd = vim.fn.getcmdline()
      if cmd == "q" or cmd == "q!" then
        -- Return to dashboard instead of quitting
        vim.schedule(function()
          M.save_and_back()
        end)
        return "<C-c>"
      elseif cmd == "wq" or cmd == "wq!" or cmd == "x" then
        -- Save and return to dashboard
        vim.schedule(function()
          M.save_and_back()
        end)
        return "<C-c>"
      end
      return "<CR>"
    end, { buffer = note_buf, expr = true, noremap = true })
  end)
end

--- Save note and restore dashboard
function M.save_and_back()
  if not state.note_buf or not vim.api.nvim_buf_is_valid(state.note_buf) then return end
  if vim.bo[state.note_buf].modified then
    vim.api.nvim_buf_call(state.note_buf, function()
      vim.cmd("silent! write")
    end)
  else
    -- Not modified, just go back
    M.restore_dashboard()
  end
end

--- Restore the dashboard view from note view
function M.restore_dashboard()
  if not state.win or not vim.api.nvim_win_is_valid(state.win) then return end
  if not state.dashboard_buf or not vim.api.nvim_buf_is_valid(state.dashboard_buf) then return end

  vim.api.nvim_win_set_buf(state.win, state.dashboard_buf)
  state.buf = state.dashboard_buf

  state.dashboard_buf = nil
  state.note_path = nil
  state.note_task = nil
  state.note_buf = nil

  vim.wo[state.win].wrap = false

  vim.api.nvim_win_set_config(state.win, {
    title = " tasks ",
    title_pos = "center",
  })
end

-- ── search bar ───────────────────────────────────────────────────────

function M.close_search()
  if state.search_win and vim.api.nvim_win_is_valid(state.search_win) then
    vim.api.nvim_win_close(state.search_win, true)
  end
  state.search_win = nil
  state.search_buf = nil
end

local function redraw_dashboard()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end

  local config = state.config
  local effective_config = config
  if state.custom_query then
    effective_config = vim.tbl_deep_extend("force", config, {
      sections = { { name = "Query Results", query = state.custom_query } },
    })
  end

  local lines, highlights, task_line_map = M.render(effective_config, state.all_tasks, state.filter_text)

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false

  local ns = vim.api.nvim_create_namespace("tasks")
  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  for _, hl in ipairs(highlights) do
    local line_idx = hl[1] - 1
    local col_start = hl[2]
    local col_end = hl[3]
    local hl_group = hl[4]
    if line_idx >= 0 and line_idx < #lines then
      local line_len = #lines[line_idx + 1]
      col_end = math.min(col_end, line_len)
      col_start = math.min(col_start, line_len)
      if col_start < col_end then
        pcall(vim.api.nvim_buf_add_highlight, state.buf, ns, hl_group, line_idx, col_start, col_end)
      end
    end
  end

  state.tasks_by_line = task_line_map
end

local function accept_search_and_focus_dashboard()
  if state.search_buf and vim.api.nvim_buf_is_valid(state.search_buf) then
    local lines = vim.api.nvim_buf_get_lines(state.search_buf, 0, 1, false)
    local text = (lines[1] or "")
    state.filter_text = text ~= "" and text or nil
  end
  vim.cmd("stopinsert")
  M.close_search()
  redraw_dashboard()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_set_current_win(state.win)
  end
end

function M.start_search()
  M.close_search()
  M.close_preview()

  local L = state.layout
  local search_row = L.row - 2
  if search_row < 0 then search_row = 0 end

  local search_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[search_buf].buftype = "nofile"
  vim.bo[search_buf].bufhidden = "wipe"

  vim.api.nvim_buf_set_lines(search_buf, 0, -1, false, { state.filter_text or "" })

  local search_win = vim.api.nvim_open_win(search_buf, true, {
    relative = "editor",
    width = L.width,
    height = 1,
    row = search_row,
    col = L.col,
    style = "minimal",
    border = {'┏', '━', '┓', '┃', '┛', '━', '┗', '┃'},
    title = "  search ",
    title_pos = "left",
  })

  vim.wo[search_win].winhl = "Normal:NormalFloat,FloatBorder:NTasksSymbolProgress,FloatTitle:NTasksSymbolProgress"

  state.search_buf = search_buf
  state.search_win = search_win

  vim.cmd("startinsert!")

  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    buffer = search_buf,
    callback = function()
      if not vim.api.nvim_buf_is_valid(search_buf) then return end
      local lines = vim.api.nvim_buf_get_lines(search_buf, 0, 1, false)
      local text = lines[1] or ""
      state.filter_text = text ~= "" and text or nil
      redraw_dashboard()
    end,
  })

  local sopts = { buffer = search_buf, noremap = true, silent = true }

  vim.keymap.set("i", "<CR>", accept_search_and_focus_dashboard, sopts)
  vim.keymap.set("i", "<Esc>", accept_search_and_focus_dashboard, sopts)
  vim.keymap.set("n", "<Esc>", accept_search_and_focus_dashboard, sopts)
  vim.keymap.set("n", "q", accept_search_and_focus_dashboard, sopts)
  vim.keymap.set("i", "<C-w>j", accept_search_and_focus_dashboard, sopts)
  vim.keymap.set("n", "<C-w>j", accept_search_and_focus_dashboard, sopts)

  vim.keymap.set("i", "<C-c>", function()
    state.filter_text = nil
    vim.cmd("stopinsert")
    M.close_search()
    redraw_dashboard()
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_set_current_win(state.win)
    end
  end, sopts)
end

-- ── dashboard open ───────────────────────────────────────────────────

function M.open(config, custom_query)
  M.close()

  local editor_width = vim.o.columns
  local editor_height = vim.o.lines
  local width = math.floor(editor_width * config.width)
  local height = math.floor(editor_height * config.height)
  local row = math.floor((editor_height - height) / 2) - 2
  if row < 3 then row = 3 end
  local col = math.floor((editor_width - width) / 2)

  config._inner_width = width - 2
  state.layout = { row = row, col = col, width = width, height = height }

  local all_tasks = scanner.scan_deduped(config.vault_path)
  state.all_tasks = all_tasks
  state.config = config
  state.custom_query = custom_query
  state.filter_text = nil

  local effective_config = config
  if custom_query then
    effective_config = vim.tbl_deep_extend("force", config, {
      sections = { { name = "Query Results", query = custom_query } },
    })
  end

  local lines, highlights, task_line_map = M.render(effective_config, all_tasks, nil)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide" -- not "wipe" — we need it to survive when swapped for note view
  vim.bo[buf].filetype = "tasks"

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local ns = vim.api.nvim_create_namespace("tasks")
  for _, hl in ipairs(highlights) do
    local line_idx = hl[1] - 1
    local col_start = hl[2]
    local col_end = hl[3]
    local hl_group = hl[4]
    if line_idx >= 0 and line_idx < #lines then
      local line_len = #lines[line_idx + 1]
      col_end = math.min(col_end, line_len)
      col_start = math.min(col_start, line_len)
      if col_start < col_end then
        pcall(vim.api.nvim_buf_add_highlight, buf, ns, hl_group, line_idx, col_start, col_end)
      end
    end
  end

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = {'┏', '━', '┓', '┃', '┛', '━', '┗', '┃'},
    title = " tasks ",
    title_pos = "center",
  })

  vim.wo[win].cursorline = true
  vim.wo[win].wrap = false

  state.buf = buf
  state.win = win
  state.tasks_by_line = task_line_map

  local opts = { buffer = buf, noremap = true, silent = true }

  -- j/k only land on task lines
  vim.keymap.set("n", "j", function()
    local cur = vim.api.nvim_win_get_cursor(state.win)[1]
    local total = vim.api.nvim_buf_line_count(state.buf)
    for i = cur + 1, total do
      if state.tasks_by_line[i] then
        vim.api.nvim_win_set_cursor(state.win, { i, 0 })
        return
      end
    end
    for i = 1, cur do
      if state.tasks_by_line[i] then
        vim.api.nvim_win_set_cursor(state.win, { i, 0 })
        return
      end
    end
  end, opts)

  vim.keymap.set("n", "k", function()
    local cur = vim.api.nvim_win_get_cursor(state.win)[1]
    local total = vim.api.nvim_buf_line_count(state.buf)
    for i = cur - 1, 1, -1 do
      if state.tasks_by_line[i] then
        vim.api.nvim_win_set_cursor(state.win, { i, 0 })
        return
      end
    end
    for i = total, cur, -1 do
      if state.tasks_by_line[i] then
        vim.api.nvim_win_set_cursor(state.win, { i, 0 })
        return
      end
    end
  end, opts)

  -- :q / :wq / :x in dashboard closes the float
  vim.keymap.set("c", "<CR>", function()
    local cmd = vim.fn.getcmdline()
    if cmd == "q" or cmd == "q!" or cmd == "wq" or cmd == "wq!" or cmd == "x" then
      vim.schedule(function() M.close() end)
      return "<C-c>"
    end
    return "<CR>"
  end, { buffer = buf, expr = true, noremap = true })

  vim.keymap.set("n", "q", function() M.close() end, opts)
  vim.keymap.set("n", "<Esc>", function()
    if state.filter_text then
      state.filter_text = nil
      redraw_dashboard()
    else
      M.close()
    end
  end, opts)
  vim.keymap.set("n", "<CR>", function() M.open_note() end, opts)
  vim.keymap.set("n", "o", function() M.jump_to_source() end, opts)
  vim.keymap.set("n", "x", function() M.set_status("x") end, opts)
  vim.keymap.set("n", "p", function() M.set_status("/") end, opts)
  vim.keymap.set("n", "-", function() M.set_status("-") end, opts)
  vim.keymap.set("n", "<Space>", function() M.set_status(" ") end, opts)
  vim.keymap.set("n", "d", function()
    local line = vim.api.nvim_win_get_cursor(state.win)[1]
    local task = state.tasks_by_line[line]
    if not task then return end
    require("tasks.actions").prompt_due_date(task, function()
      state.all_tasks = scanner.scan_deduped(state.config.vault_path)
      redraw_dashboard()
    end)
  end, opts)
  vim.keymap.set("n", "r", function() M.refresh() end, opts)
  vim.keymap.set("n", "n", function() require("tasks.actions").create_task(config) end, opts)
  vim.keymap.set("n", "/", function() M.start_search() end, opts)

  -- Place cursor on first task
  vim.schedule(function()
    local total = vim.api.nvim_buf_line_count(buf)
    for i = 1, total do
      if state.tasks_by_line[i] then
        vim.api.nvim_win_set_cursor(win, { i, 0 })
        break
      end
    end
  end)
end

-- ── close ────────────────────────────────────────────────────────────

function M.close()
  M.close_search()
  M.close_preview()
  -- Save note if in note view
  if state.note_buf and vim.api.nvim_buf_is_valid(state.note_buf) then
    if vim.bo[state.note_buf].modified then
      vim.api.nvim_buf_call(state.note_buf, function()
        vim.cmd("silent! write")
      end)
    end
  end
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  if state.dashboard_buf and vim.api.nvim_buf_is_valid(state.dashboard_buf) then
    vim.api.nvim_buf_delete(state.dashboard_buf, { force = true })
  end
  state.win = nil
  state.buf = nil
  state.dashboard_buf = nil
  state.note_path = nil
  state.note_task = nil
  state.note_buf = nil
  state.preview_task = nil
  state.tasks_by_line = {}
  state.all_tasks = {}
  state.filter_text = nil
  state.custom_query = nil
end

-- ── actions from dashboard ───────────────────────────────────────────

function M.open_note()
  if not state.win or not vim.api.nvim_win_is_valid(state.win) then return end
  local line = vim.api.nvim_win_get_cursor(state.win)[1]
  local task = state.tasks_by_line[line]
  if not task then return end

  if not task.note_link then
    require("tasks.actions").add_note_to_task(task, state.config)
  end

  if task.note_link then
    M.show_note_inline(task)
  end
end

function M.jump_to_source()
  if not state.win or not vim.api.nvim_win_is_valid(state.win) then return end
  local line = vim.api.nvim_win_get_cursor(state.win)[1]
  local task = state.tasks_by_line[line]
  if not task then return end

  M.close()
  vim.cmd("edit " .. vim.fn.fnameescape(task.source_file))
  vim.api.nvim_win_set_cursor(0, { task.source_line, 0 })
  vim.cmd("normal! zz")
end

function M.set_status(new_status)
  if not state.win or not vim.api.nvim_win_is_valid(state.win) then return end
  local line = vim.api.nvim_win_get_cursor(state.win)[1]
  local task = state.tasks_by_line[line]
  if not task then return end

  require("tasks.actions").set_task_status(task, new_status)

  local bufnr = vim.fn.bufnr(task.source_file)
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].modified then
    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd("silent! write")
    end)
  end

  local cursor = vim.api.nvim_win_get_cursor(state.win)
  redraw_dashboard()
  M.close_preview()
  local line_count = vim.api.nvim_buf_line_count(state.buf)
  if cursor[1] <= line_count then
    vim.api.nvim_win_set_cursor(state.win, cursor)
  end
end

function M.refresh()
  if not state.config then return end
  local cursor = nil
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    cursor = vim.api.nvim_win_get_cursor(state.win)
  end
  M.open(state.config, state.custom_query)
  if cursor and state.win and vim.api.nvim_win_is_valid(state.win) then
    local line_count = vim.api.nvim_buf_line_count(state.buf)
    if cursor[1] <= line_count then
      vim.api.nvim_win_set_cursor(state.win, cursor)
    end
  end
end

return M
