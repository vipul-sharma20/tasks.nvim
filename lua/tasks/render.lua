--- Inline rendering: highlights #task and #label tags as styled pills
--- in markdown/vimwiki buffers. Uses hl_group only — no conceal,
--- so w/e/b motions work normally on the underlying text.

local M = {}

local ns = vim.api.nvim_create_namespace("tasks_render")

--- Decorate a single buffer line
---@param buf number
---@param line_idx number 0-indexed
---@param line_text string
local function decorate_line(buf, line_idx, line_text)
  if not line_text:match("#task") then return end

  -- Highlight all #tags on the line
  local pos = 1
  while true do
    local tag_start, tag_end = line_text:find("#(%S+)", pos)
    if not tag_start then break end

    local tag = line_text:sub(tag_start + 1, tag_end) -- without #
    local hl = "NTasksLabelPill"
    if tag == "task" then
      hl = "NTasksTagPill"
    end

    vim.api.nvim_buf_set_extmark(buf, ns, line_idx, tag_start - 1, {
      end_col = tag_end,
      hl_group = hl,
    })

    pos = tag_end + 1
  end
end

--- Decorate all task lines in a buffer
---@param buf number
function M.decorate_buffer(buf)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i, line in ipairs(lines) do
    decorate_line(buf, i - 1, line)
  end
end

--- Set up rendering for a buffer
---@param buf number
function M.attach(buf)
  M.decorate_buffer(buf)

  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function(_, b)
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(b) then return end
        if vim.api.nvim_get_mode().mode:match("^i") then return end
        M.decorate_buffer(b)
      end)
    end,
    on_detach = function() end,
  })

  local augroup = vim.api.nvim_create_augroup("TasksRender_" .. buf, { clear = true })

  vim.api.nvim_create_autocmd("InsertEnter", {
    group = augroup,
    buffer = buf,
    callback = function()
      vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    end,
  })

  vim.api.nvim_create_autocmd("InsertLeave", {
    group = augroup,
    buffer = buf,
    callback = function()
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buf) then
          M.decorate_buffer(buf)
        end
      end)
    end,
  })
end

return M
