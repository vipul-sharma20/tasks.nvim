local parser = require("tasks.parser")

local M = {}

--- Scan the vault for all tasks using ripgrep
---@param vault_path string path to the vault directory
---@return table[] list of parsed task tables
function M.scan(vault_path)
  vault_path = vim.fn.expand(vault_path)
  local cmd = string.format(
    "rg --no-heading -n --no-messages '#task' --glob '*.md' %s",
    vim.fn.shellescape(vault_path)
  )
  local lines = vim.fn.systemlist(cmd)

  if vim.v.shell_error ~= 0 and vim.v.shell_error ~= 1 then
    vim.notify("tasks: ripgrep scan failed", vim.log.levels.ERROR)
    return {}
  end

  local tasks = {}
  for _, line in ipairs(lines) do
    -- rg output: filepath:linenum:content
    local filepath, linenum, content = line:match("^(.+):(%d+):(.+)$")
    if filepath and content then
      local task = parser.parse(content, filepath, tonumber(linenum))
      if task then
        table.insert(tasks, task)
      end
    end
  end

  return tasks
end

--- Scan and deduplicate tasks (same description + due = keep most recent file)
---@param vault_path string
---@return table[]
function M.scan_deduped(vault_path)
  local tasks = M.scan(vault_path)
  local seen = {}
  local deduped = {}

  for _, task in ipairs(tasks) do
    local key = task.description .. "|" .. (task.due or "none")
    local existing = seen[key]
    if not existing then
      seen[key] = task
      table.insert(deduped, task)
    else
      -- Keep the one from the more recent file (lexicographic comparison works for YYYY-MM-DD filenames)
      if task.source_file > existing.source_file then
        -- Replace in the deduped list
        for i, t in ipairs(deduped) do
          if t == existing then
            deduped[i] = task
            break
          end
        end
        seen[key] = task
      end
    end
  end

  return deduped
end

return M
