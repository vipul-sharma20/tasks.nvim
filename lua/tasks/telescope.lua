local M = {}

function M.picker(opts)
  local ok, _ = pcall(require, "telescope")
  if not ok then
    vim.notify("tasks: telescope.nvim is required for this feature", vim.log.levels.ERROR)
    return
  end

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local previewers = require("telescope.previewers")

  local tasks_config = require("tasks").config
  local scanner = require("tasks.scanner")
  local parser_mod = require("tasks.parser")

  opts = opts or {}
  local tasks = scanner.scan_deduped(tasks_config.vault_path)

  local function get_symbol(status)
    local symbols = tasks_config.symbols
    local map = {
      [" "] = symbols.todo,
      ["/"] = symbols.in_progress,
      ["x"] = symbols.done,
      ["-"] = symbols.cancelled,
    }
    return map[status] or symbols.todo
  end

  local function format_due(due)
    if not due then
      return ""
    end
    local y, m, d = due:match("(%d+)-(%d+)-(%d+)")
    if not y then
      return due
    end
    local months = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
    return months[tonumber(m)] .. " " .. tonumber(d)
  end

  pickers
    .new(opts, {
      prompt_title = "Tasks",
      finder = finders.new_table({
        results = tasks,
        entry_maker = function(task)
          local symbol = get_symbol(task.status)
          local due = format_due(task.due)
          local note_indicator = task.note_link and " 📎" or ""
          local file_short = task.source_file:match("([^/]+/[^/]+)$") or task.source_file
          local display = string.format(
            "%s %s%s%s  (%s:%d)",
            symbol,
            task.description,
            note_indicator,
            due ~= "" and (" [" .. due .. "]") or "",
            file_short,
            task.source_line
          )

          -- If task has a note, preview the note file; otherwise preview source
          local preview_file = task.source_file
          local preview_lnum = task.source_line
          if task.note_link then
            local note_path = parser_mod.resolve_note_path(task.note_link, tasks_config.vault_path)
            if vim.fn.filereadable(note_path) == 1 then
              preview_file = note_path
              preview_lnum = 1
            end
          end

          return {
            value = task,
            display = display,
            ordinal = task.description .. " " .. (task.due or "") .. " " .. (task.priority or ""),
            filename = preview_file,
            lnum = preview_lnum,
          }
        end,
      }),
      sorter = conf.generic_sorter(opts),
      previewer = conf.file_previewer(opts),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if not selection then
            return
          end

          local task = selection.value
          -- If task has a note, open the note; otherwise go to source
          if task.note_link then
            local note_path = parser_mod.resolve_note_path(task.note_link, tasks_config.vault_path)
            if vim.fn.filereadable(note_path) == 1 then
              vim.cmd("edit " .. vim.fn.fnameescape(note_path))
              return
            end
          end
          vim.cmd("edit " .. vim.fn.fnameescape(task.source_file))
          vim.api.nvim_win_set_cursor(0, { task.source_line, 0 })
          vim.cmd("normal! zz")
        end)

        -- Toggle task status with <C-x>
        map("i", "<C-x>", function()
          local selection = action_state.get_selected_entry()
          if selection then
            local task = selection.value
            local new_status = parser_mod.next_status(task.status)
            require("tasks.actions").set_task_status(task, new_status)
            vim.notify("tasks: task marked as [" .. new_status .. "]", vim.log.levels.INFO)
          end
        end)

        -- Open source file with <C-o>
        map("i", "<C-o>", function()
          local selection = action_state.get_selected_entry()
          if selection then
            actions.close(prompt_bufnr)
            local task = selection.value
            vim.cmd("edit " .. vim.fn.fnameescape(task.source_file))
            vim.api.nvim_win_set_cursor(0, { task.source_line, 0 })
            vim.cmd("normal! zz")
          end
        end)

        return true
      end,
    })
    :find()
end

return M
