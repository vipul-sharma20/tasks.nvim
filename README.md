# tasks.nvim

Markdown-native task management for Neovim.

Works alongside Obsidian, vimwiki like note-taking system.

> [!NOTE]
> There are already loads of task management tools available. This note-taking
> setup is mostly tailored for ease of my personal workflow and to solve
> problems that I face.
>
> Creating this repository in case people find any utility in this way of
> note-taking.

## How it works

Tasks are markdown checkboxes with a `#task` tag and optional metadata:

```markdown
- [ ] #task Ship the API changes  [due:: 2026-03-25]  [priority:: high]
- [/] #task Review PR from @loremipsum  [due:: 2026-03-24]
- [x] #task Fix auth middleware  [due:: 2026-03-20]  [completion:: 2026-03-21]
- [-] #task Migrate to Redis (cancelled)
```

Statuses: `[ ]` todo · `[/]` in-progress · `[x]` done · `[-]` cancelled

Tasks can link to note files for context:

```markdown
- [/] #task Refactor payment service [[tasks/refactor-payments]]  [due:: 2026-03-25]  [priority:: high]
```

The linked file (`tasks/refactor-payments.md`) holds whatever context you need:
description, links, subtasks, scratch notes. Press `<CR>` on the task to
view/edit it inline in the dashboard float.

## The Dashboard

`:Tasks` opens a floating window with your tasks grouped by urgency:

![Dashboard](assets/dashboard.png)

`📎` means the task has a linked note. `j`/`k` skip between tasks.

Press `<CR>` on a task to open its note inline, editable in the same float.
`:w` saves and returns to the task list. `<CR>` again opens it in a full
buffer.

## Dashboard Keymaps

| Key | Action |
|---|---|
| `x` | Mark done |
| `p` | Mark in-progress |
| `-` | Mark cancelled |
| `<Space>` | Mark todo |
| `d` | Set/change due date |
| `<CR>` | Open note context inline (creates note + wiki-link if none exists) |
| `o` | Jump to source file at the task line |
| `n` | Create new task |
| `/` | Fuzzy search (fzf-style bar, filters live as you type) |
| `r` | Refresh |
| `q` / `:q` | Close |

### Note view (after `<CR>`)

The note opens in the same floating window, fully editable.

![Note view](assets/task-expanded.png)

| Key | Action |
|---|---|
| `:w` | Save and return to task list |
| `:wq` / `:q` | Same — save and return |
| `<CR>` | Open note in a full buffer |
| `<leader>w` | Save and return to task list |

### Search

Press `/` in the dashboard. A search bar appears above the float. Type to
fuzzy-filter across task descriptions, dates, priorities, and tags. `<CR>` or
`<Esc>` accepts the filter and drops you back into the filtered list. `<C-c>`
clears the filter. `<Esc>` in the dashboard clears an active filter.

## Inline toggle

`<C-Space>` on any `#task` line in a markdown/vimwiki buffer cycles the status:

`[ ]` → `[/]` → `[x]` → `[-]` → `[ ]`

Falls back to `VimwikiToggleListItem` on non-task lines.

## Query blocks

> [!NOTE]
> I am not too sure about this feature if I'll find a need for it or support it
> going forward.

If your markdown files have query blocks like this:

````markdown
```tasks
not done
due before today
sort by due
```
````

`:TaskQuery` evaluates the nearest block and shows results in the dashboard.

Supported clauses: `not done`, `done`, `due today`, `due before today`, `due
after today`, `no due date`, `has due date`, `priority is <level>`, `sort by
due`, `sort by priority`, `(A) OR (B)`.

## Requirements

- Neovim 0.9+
- [ripgrep](https://github.com/BurntSushi/ripgrep) (for vault scanning)

Optional:
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) for `:TaskFind`

## Install

With packer:

```lua
use {
    'vipul-sharma20/tasks.nvim',
    config = function()
        require("tasks").setup()
    end
}
```

With lazy.nvim:

```lua
{
    'vipul-sharma20/tasks.nvim',
    config = function()
        require("tasks").setup()
    end
}
```

## Setup

```lua
require("tasks").setup({
    vault_path = "~/notes",       -- root of your markdown vault
    diary_path = "~/notes/diary", -- where diary entries live
    tasks_path = "tasks",         -- note files dir (relative to vault_path)

    sections = {
        { name = "P0 (Overdue)",  query = "not done\ndue before today\nsort by due" },
        { name = "P1 (Due Today)", query = "not done\ndue today\nsort by due" },
        { name = "All Pending",   query = "not done\n(due after today) OR (no due date)" },
    },

    symbols = {
        todo        = "✗",
        in_progress = "◐",
        done        = "✓",
        cancelled   = "●",
    },

    width  = 0.6, -- float width as fraction of editor
    height = 0.7,
})
```

All fields are optional. Defaults are shown above.

## Commands

| Command | Description |
|---|---|
| `:Tasks` | Open the dashboard |
| `:TaskCreate` | Create a new task (prompts for description, due date, priority, note) |
| `:TaskToggle` | Toggle status of task under cursor |
| `:TaskQuery` | Evaluate the nearest ```` ```tasks ```` block |
| `:TaskFind` | Telescope picker across all tasks |

## Suggested keymaps

```lua
-- with which-key
t = {
    name = "Tasks",
    d = { "<cmd>Tasks<cr>", "Dashboard" },
    f = { "<cmd>TaskFind<cr>", "Find" },
    n = { "<cmd>TaskCreate<cr>", "New" },
    t = { "<cmd>TaskToggle<cr>", "Toggle" },
    q = { "<cmd>TaskQuery<cr>", "Query Block" },
}
```

## Task format reference

```markdown
- [ ] #task Description [[optional/note-link]]  [due:: YYYY-MM-DD]  [priority:: high]  [completion:: YYYY-MM-DD]
```

| Field | Required | Values |
|---|---|---|
| Checkbox | Yes | `[ ]`, `[/]`, `[x]`, `[-]` |
| `#task` | Yes | Marker that identifies the line as a task |
| Description | Yes | Free text, can include markdown links and @mentions |
| `[[link]]` | No | Wiki-link to a note file with task context |
| `[due:: DATE]` | No | Due date in YYYY-MM-DD |
| `[priority:: LEVEL]` | No | `highest`, `high`, `medium`, `low`, `lowest` |
| `[completion:: DATE]` | No | Auto-added when marking done/cancelled |

Date input accepts: `2026-03-25`, `today`, `tomorrow`, `tmr`, `+3d`, `+7d`, `next week`.

## License

MIT
