local M = {}

M.config = {}

local defaults = {
  vault_path = "~/tools/noto",
  diary_path = "~/tools/noto/diary",
  tasks_path = "tasks", -- relative to vault_path, where note files are created
  sections = {
    { name = "P0 (Overdue)", query = "not done\ndue before today\nsort by due" },
    { name = "P1 (Due Today)", query = "not done\ndue today\nsort by due" },
    { name = "All Pending", query = "not done\n(due after today) OR (no due date)" },
    { name = "Recently Done", query = "done\ncompleted in last 7 days\nsort by due", collapsed = true },
  },
  symbols = {
    todo = "✗",
    in_progress = "◐",
    done = "✓",
    cancelled = "●",
  },
  width = 0.6,
  height = 0.7,
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", defaults, opts or {})

  -- Setup highlights
  require("tasks.highlights").setup()

  -- Register commands
  vim.api.nvim_create_user_command("Tasks", function()
    require("tasks.ui").open(M.config)
  end, { desc = "Open task dashboard" })

  vim.api.nvim_create_user_command("TaskCreate", function()
    require("tasks.actions").create_task(M.config)
  end, { desc = "Create a new task" })

  vim.api.nvim_create_user_command("TaskToggle", function()
    require("tasks.actions").toggle_current_line()
  end, { desc = "Toggle task status on current line" })

  vim.api.nvim_create_user_command("TaskQuery", function()
    M.evaluate_query_block()
  end, { desc = "Evaluate tasks query block under cursor" })

  -- Register telescope command directly (more reliable than extension registration)
  vim.api.nvim_create_user_command("TaskFind", function()
    require("tasks.telescope").picker()
  end, { desc = "Find tasks with telescope" })

  -- Set up <C-space> for task toggle on vimwiki/markdown buffers
  -- Replaces the global VimwikiToggleListItem mapping; falls back to it for non-task lines
  -- Use all key notations that terminals might send for Ctrl+Space
  local toggle = function()
    require("tasks.actions").toggle_current_line()
  end

  local function set_toggle_maps(buf)
    local bopts = { buffer = buf, noremap = true, silent = true, desc = "Toggle task status" }
    vim.keymap.set("n", "<C-space>", toggle, bopts)
    vim.keymap.set("n", "<C-Space>", toggle, bopts)
    vim.keymap.set("n", "<Nul>", toggle, bopts)
  end

  vim.api.nvim_create_autocmd("FileType", {
    pattern = { "vimwiki", "markdown" },
    callback = function(ev)
      set_toggle_maps(ev.buf)
      require("tasks.render").attach(ev.buf)
    end,
  })

  -- Apply to any already-open vimwiki/markdown buffers
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local ft = vim.bo[buf].filetype
      if ft == "vimwiki" or ft == "markdown" then
        set_toggle_maps(buf)
        require("tasks.render").attach(buf)
      end
    end
  end
end

--- Evaluate the ```tasks query block under or nearest to the cursor
function M.evaluate_query_block()
  local bufnr = vim.api.nvim_get_current_buf()
  local ft = vim.bo[bufnr].filetype
  if ft ~= "vimwiki" and ft ~= "markdown" then
    vim.notify("tasks: not a markdown/vimwiki buffer", vim.log.levels.WARN)
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor[1]
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Collect all ```tasks blocks
  local blocks = {}
  local block_start = nil

  for i, line in ipairs(lines) do
    if line:match("```tasks") then
      block_start = i
    elseif block_start and line:match("^```%s*$") then
      table.insert(blocks, { start = block_start, finish = i })
      block_start = nil
    end
  end

  if #blocks == 0 then
    vim.notify("tasks: no ```tasks blocks found in this file", vim.log.levels.WARN)
    return
  end

  -- Find the block the cursor is inside, or the nearest block above the cursor
  local target_block = nil
  for _, block in ipairs(blocks) do
    if line_num >= block.start and line_num <= block.finish then
      target_block = block
      break
    end
  end

  -- If not inside a block, find the nearest one above cursor
  if not target_block then
    for i = #blocks, 1, -1 do
      if blocks[i].finish <= line_num then
        target_block = blocks[i]
        break
      end
    end
  end

  -- Still nothing? Use the nearest block below cursor
  if not target_block then
    for _, block in ipairs(blocks) do
      if block.start >= line_num then
        target_block = block
        break
      end
    end
  end

  if not target_block then
    vim.notify("tasks: no ```tasks block found", vim.log.levels.WARN)
    return
  end

  -- Extract query text
  local query_lines = {}
  for i = target_block.start + 1, target_block.finish - 1 do
    table.insert(query_lines, lines[i])
  end
  local query_text = table.concat(query_lines, "\n")

  -- Open dashboard with this specific query
  require("tasks.ui").open(M.config, query_text)
end

return M
