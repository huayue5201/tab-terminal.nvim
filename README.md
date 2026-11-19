# tab-terminal.nvim

Per-tab (per-workspace) terminals for Neovim: a bottom panel with winbar tabs, an optional
sidebar, and hard tab isolation. Terminals are created lazily, survive hiding, and die with
their tab.

Requires **Neovim >= 0.10** (uses `winfixbuf`, `vim.keymap.set`, `vim.pack`-friendly layout).

## Features

- One terminal set per tab; switching tabs never leaks buffers or windows.
- Hide ≠ destroy: toggling the panel keeps the process and scrollback.
- Bottom panel with clickable winbar tabs (`+`, `✕`, middle-click close) and focus-aware colors.
- Optional sidebar listing **all** workspaces' terminals, grouped by workspace name, with a
  `+` button on each group header to open a new terminal in that workspace.
- `+` / `✕` mouse targets, `<CR>` jump, `x` kill, `q` hide.
- Edit-mode friendly terminal mappings: `Esc` is only "leave terminal mode" when the shell
  is at the prompt; full-screen TUIs (fzf/less/htop) keep their `Esc`. `Ctrl-Esc` is the
  unconditional escape hatch.
- Foreign terminals (dap console, `toggleterm`, …) are never adopted. Extensible rules via
  `register_foreign_rule`.
- Optional session-restore helpers for panel/sidebar windows (`restore_win`).
- No global keymaps unless you ask for them.

## Installation

With `vim.pack` (Neovim 0.12+):

```lua
vim.pack.add({ "https://github.com/huayue5201/tab-terminal.nvim" })
require("tab_terminal").setup()
```

With lazy.nvim:

```lua
{
  "huayue5201/tab-terminal.nvim",
  opts = {},
}
```

## Setup

```lua
require("tab_terminal").setup({
  position = "bot",        -- "bot" | "top"
  size = 18,               -- panel height
  startinsert = true,
  show_tabs = true,        -- winbar tab strip inside the panel
  sidebar = true,
  sidebar_width = 22,
  sidebar_plus_icon = "+",

  -- Where new terminals start. Return nil to fall back to the tab's cwd.
  cwd = function(tab)
    -- e.g. use your workspace/root resolver
    return nil
  end,

  -- Sidebar group title. Return nil to fall back to the cwd basename.
  workspace_name = function(tab)
    return nil
  end,

  -- Global keys are opt-in. Values can be a string or a list of strings.
  keys = {
    toggle = { "<C-;>", "<leader>To" },
    new = "<leader>TN",
    select = "<leader>Ts",
    rename = "<leader>Tn",
    tabs = "<leader>Tt",
    kill = "<leader>Tk",
    kill_all = "<leader>TK",
    -- Buffer-local, normal mode, terminals created by this plugin only:
    prev = "<",
    next = ">",
  },

  -- Optional extra "special shell" key:
  quick_shell = { key = "<leader>Tu", cmd = { "nu" }, desc = "terminal: nushell" },
})
```

All options are optional; `false` disables a key.

### Sidebar `+`

Clicking `+` on a workspace header switches to that tab and opens a new terminal there using
your `cwd` callback (so it lands in that workspace, not the current one). The button is drawn
at the right edge of the group header and is part of the same click handler as the `✕`.

### Buffer-local switching

`<` / `>` are mapped **only in terminal buffers created by this plugin**, in normal mode.
They cycle through the terminals of the current tab. No global `<` / `>` mapping is created.

## Commands

```
:TabTerminal [toggle|new|select|rename [name]|tabs|kill|kill-all]
```

`:checkhealth tab_terminal` reports load state, mapped keys and tracked terminals.

## Foreign terminals

Core rules are plugin-agnostic:

1. a `terminal` buffer with a non-empty filetype other than `tab_terminal` is foreign;
2. a window with `winfixbuf` is foreign.

Add your own rule:

```lua
require("tab_terminal").register_foreign_rule({
  name = "toggleterm",
  desc = "toggleterm manages its own terminals",
  match = function(ctx) -- ctx: bufnr, ft, buftype, name, wins
    return ctx.ft == "toggleterm"
  end,
})
```

## Integrations

- **dap / overseer**: register a `register_foreign_rule` in your config so their terminal
  windows are ignored.
- **resession**: `require("tab_terminal.sidebar").restore_win(win)` and
  `require("tab_terminal").restore_win(win, is_panel)` recreate the layout during restore.

## Tests

```sh
./tests/run.sh            # nvim --headless -u NONE -l tests/*.lua
```

## License

MIT
