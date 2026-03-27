local M = {}

function M.setup()
  -- Try to get catppuccin colors, fallback to sensible defaults
  local ok, palette = pcall(function()
    return require("catppuccin.palettes").get_palette("mocha")
  end)

  local colors
  if ok and palette then
    colors = {
      red = palette.red,
      yellow = palette.yellow,
      blue = palette.blue,
      green = palette.green,
      mauve = palette.mauve,
      overlay0 = palette.overlay0,
      surface0 = palette.surface0,
      text = palette.text,
      subtext0 = palette.subtext0,
    }
  else
    colors = {
      red = "#f38ba8",
      yellow = "#f9e2af",
      blue = "#89b4fa",
      green = "#a6e3a1",
      mauve = "#cba6f7",
      overlay0 = "#6c7086",
      surface0 = "#313244",
      text = "#cdd6f4",
      subtext0 = "#a6adc8",
    }
  end

  -- Section headers
  vim.api.nvim_set_hl(0, "NTasksHeader", { fg = colors.mauve, bold = true })
  vim.api.nvim_set_hl(0, "NTasksTitle", { fg = colors.text, bold = true })
  vim.api.nvim_set_hl(0, "NTasksDate", { fg = colors.subtext0 })

  -- Task status highlights
  vim.api.nvim_set_hl(0, "NTasksOverdue", { fg = colors.red })
  vim.api.nvim_set_hl(0, "NTasksDueToday", { fg = colors.yellow })
  vim.api.nvim_set_hl(0, "NTasksPending", { fg = colors.blue })
  vim.api.nvim_set_hl(0, "NTasksDone", { fg = colors.green, strikethrough = true })
  vim.api.nvim_set_hl(0, "NTasksCancelled", { fg = colors.overlay0, strikethrough = true })

  -- Status symbols
  vim.api.nvim_set_hl(0, "NTasksSymbolTodo", { fg = colors.red })
  vim.api.nvim_set_hl(0, "NTasksSymbolProgress", { fg = colors.yellow })
  vim.api.nvim_set_hl(0, "NTasksSymbolDone", { fg = colors.green })
  vim.api.nvim_set_hl(0, "NTasksSymbolCancelled", { fg = colors.overlay0 })

  -- Priority indicators
  vim.api.nvim_set_hl(0, "NTasksPrioHighest", { fg = colors.red, bold = true })
  vim.api.nvim_set_hl(0, "NTasksPrioHigh", { fg = colors.red })
  vim.api.nvim_set_hl(0, "NTasksPrioMedium", { fg = colors.yellow })
  vim.api.nvim_set_hl(0, "NTasksPrioLow", { fg = colors.overlay0 })
  vim.api.nvim_set_hl(0, "NTasksPrioLowest", { fg = colors.overlay0, italic = true })

  -- Due date column
  vim.api.nvim_set_hl(0, "NTasksDueDateOverdue", { fg = colors.red, italic = true })
  vim.api.nvim_set_hl(0, "NTasksDueDateToday", { fg = colors.yellow, italic = true })
  vim.api.nvim_set_hl(0, "NTasksDueDateFuture", { fg = colors.subtext0, italic = true })

  -- Footer / help line
  vim.api.nvim_set_hl(0, "NTasksHelp", { fg = colors.overlay0 })

  -- Border
  vim.api.nvim_set_hl(0, "NTasksBorder", { fg = colors.surface0 })

  -- Count line
  vim.api.nvim_set_hl(0, "NTasksCount", { fg = colors.overlay0, italic = true })

  -- Inline pills (rendered in markdown/vimwiki buffers)
  vim.api.nvim_set_hl(0, "NTasksTagPill", { fg = colors.surface0, bg = colors.mauve, bold = true })
  vim.api.nvim_set_hl(0, "NTasksLabelPill", { fg = colors.surface0, bg = colors.blue })
  vim.api.nvim_set_hl(0, "NTasksLabelInline", { fg = colors.blue, italic = true })
  vim.api.nvim_set_hl(0, "NTasksLinkPill", { fg = colors.blue, bg = colors.surface0, italic = true })
end

return M
