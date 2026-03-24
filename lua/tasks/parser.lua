local M = {}

--- Parse a single task line into a structured table
--- Format: - [x] #task Description [[note-link]]  [due:: 2026-03-24]  [priority:: high]  [completion:: 2026-03-23]
---@param line string the raw markdown line
---@param source_file string|nil file path the line came from
---@param source_line number|nil line number in the file
---@return table|nil parsed task table, or nil if not a valid task line
function M.parse(line, source_file, source_line)
  -- Match: optional leading whitespace, dash, checkbox, then #task
  local indent, status_char, rest = line:match("^(%s*)%- %[(.)%]%s+#task%s+(.*)")
  if not status_char then
    return nil
  end

  -- Extract all inline metadata fields [key:: value]
  local metadata = {}
  local remaining = rest

  -- First, extract all metadata fields (handles both [key:: value] and [key::value])
  for key, value in remaining:gmatch("%[(%w+)::%s*([^%]]+)%]") do
    metadata[key:lower()] = vim.trim(value)
  end

  -- Extract wiki-link [[note-path]]
  local note_link = remaining:match("%[%[([^%]]+)%]%]")

  -- Remove metadata fields and wiki-link from the description
  local desc = remaining:gsub("%s*%[%w+::%s*[^%]]+%]", "")
  desc = desc:gsub("%s*%[%[([^%]]+)%]%]", "")
  desc = vim.trim(desc)

  -- Extract additional tags (beyond #task)
  local tags = { "task" }
  for tag in desc:gmatch("#(%S+)") do
    if tag ~= "task" then
      table.insert(tags, tag)
    end
  end

  -- Remove tags from the display description
  local display_desc = desc:gsub("#%S+%s*", "")
  display_desc = vim.trim(display_desc)

  return {
    status = status_char,
    description = display_desc,
    due = metadata.due or nil,
    priority = metadata.priority or nil,
    completion = metadata.completion or nil,
    note_link = note_link,
    tags = tags,
    source_file = source_file,
    source_line = source_line,
    raw = line,
    indent = indent or "",
  }
end

--- Resolve a wiki-link to an absolute file path
---@param note_link string the wiki-link path (e.g. "tasks/brex-call-transfer")
---@param vault_path string the vault root path
---@return string absolute path to the note file
function M.resolve_note_path(note_link, vault_path)
  vault_path = vim.fn.expand(vault_path)
  -- Add .md extension if not present
  if not note_link:match("%.md$") then
    note_link = note_link .. ".md"
  end
  return vault_path .. "/" .. note_link
end

--- Check if a status is considered "done"
---@param status string
---@return boolean
function M.is_done(status)
  return status == "x" or status == "-"
end

--- Get the next status in the cycle: " " -> "/" -> "x" -> "-" -> " "
---@param current string
---@return string
function M.next_status(current)
  local cycle = { [" "] = "/", ["/"] = "x", ["x"] = "-", ["-"] = " " }
  return cycle[current] or " "
end

--- Format a task back into a markdown line
---@param task table parsed task
---@return string
function M.format(task)
  local parts = { task.indent .. "- [" .. task.status .. "] #task " }

  -- Re-add tags
  for _, tag in ipairs(task.tags) do
    if tag ~= "task" then
      table.insert(parts, "#" .. tag .. " ")
    end
  end

  table.insert(parts, task.description)

  -- Add wiki-link if present
  if task.note_link then
    table.insert(parts, " [[" .. task.note_link .. "]]")
  end

  -- Add metadata fields
  if task.due then
    table.insert(parts, "  [due:: " .. task.due .. "]")
  end
  if task.priority then
    table.insert(parts, "  [priority:: " .. task.priority .. "]")
  end
  if task.completion then
    table.insert(parts, "  [completion:: " .. task.completion .. "]")
  end

  return table.concat(parts)
end

return M
