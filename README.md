# nvim-herde

**Herde** brings your coding agents into Neovim. Connect it to [Herdr](https://herdr.dev) to browse projects, switch between agents, review requests for input, and open their checkouts in your editor.

It works with Pi, Codex, Claude, and other agents recognized by Herdr. Neovim can run in its own terminal or inside Herdr.

## Features

- A project sidebar with alphabetically ordered workspaces, agent status, and task labels.
- Fuzzy search for agents, workspaces, and attention items.
- An inbox for input requests and completed work, with configurable notifications.
- Terminal snapshots and a prompt composer with editor context.
- Workspace tabs, saved layouts, and quick navigation back to your previous workspace.
- A current-workspace field in lualine and colors that follow your Neovim theme.

## Requirements

- Neovim 0.10 or newer.
- Herdr installed and running, with `herdr` available on Neovim's `PATH`.
- Snacks Picker for the recommended LazyVim setup.

See [backend compatibility](docs/backends.md) for supported Herdr interfaces.

## Installation

### LazyVim

Create `~/.config/nvim/lua/plugins/herde.lua`:

```lua
return {
  "broemp/nvim-herde",
  name = "herde.nvim",
  main = "herde",
  cmd = "Herde",
  opts = {
    picker = "snacks",
  },
  keys = {
    { "<leader>aa", function() require("herde").toggle() end, desc = "Agent overview" },
    { "<leader>af", function() require("herde").agents() end, desc = "Find agent" },
    { "<leader>aw", function() require("herde").workspaces() end, desc = "Agent workspaces" },
    { "<leader>ai", function() require("herde").inbox() end, desc = "Agent attention inbox" },
    { "<leader>ao", function() require("herde").checkout() end, desc = "Open agent checkout" },
    { "<leader>ab", function() require("herde").back() end, desc = "Previous workspace" },
  },
}
```

Restart Neovim and install the plugin through `:Lazy`, then run `:Herde`.

For the full set of keymaps and automatic lualine integration, copy [examples/github.lua](examples/github.lua) instead. You can change its mappings to fit your configuration.

### Other Neovim configurations

The same lazy.nvim spec works with `opts = { picker = "native" }` to use `vim.ui.select`.

For Neovim's built-in package support:

```sh
git clone https://github.com/broemp/nvim-herde.git \
  ~/.local/share/nvim/site/pack/plugins/start/nvim-herde
```

Add to `init.lua`:

```lua
vim.cmd("packadd nvim-herde")
require("herde").setup({ picker = "native" })
```

## Connect to Herdr

Start Herdr and your agents, then open Neovim. Herde connects to Herdr's default session or the session inherited by your terminal.

To select a named session, add to `opts`:

```lua
herdr = { session = "work" },
```

For a saved remote machine profile:

```lua
herdr = { machine = "my-server" },
```

Use either `session` or `machine`. Remote checkout paths are shown in the overview; checkout navigation requires a local directory.

Run `:checkhealth herde` to check your connection and dependencies.

## Getting started

1. Press `<leader>aa` to open the sidebar on the right. Move into it with your usual window-navigation keys.
2. Press `<leader>af` to search agents. Enter focuses the selected agent's Herdr pane. If Herdr is in another window, switch to that window to interact with the agent.
3. Press Ctrl-O in the search to inspect a terminal snapshot.
4. Open `<leader>ai` to review agents needing input or completed work.
5. Press `o` on a workspace or agent in the sidebar to open its checkout. The sidebar follows you into the workspace tab.
6. Return with `<leader>ab`, `b` in the sidebar, or `:Herde back`.

The sidebar opens without taking focus from your editor. The full example configuration also provides `<leader>aA` to focus it directly.

## Sidebar

Projects are listed alphabetically, with numbered workspace rows and their agents underneath. Linked worktrees appear under their shared project. Agents needing attention appear first within each workspace.

- `j` / `k` — navigate.
- `Enter` — expand/collapse a workspace or focus an agent.
- `h` / `l` — collapse/expand a workspace.
- `o` — open the checkout.
- `b` — return to the previous workspace/editor tab.
- `P` — view a terminal snapshot.
- `p` — compose a prompt.
- `L` — edit the task label.
- `a` — acknowledge attention events.
- `i` — open the inbox.
- `/` or `f` — search agents.
- `r` — refresh.
- `?` — show shortcuts.
- `q` — close the sidebar.

Agent markers:

- `!` — needs input.
- `●` — working.
- `✓` — completed.
- `○` — idle.
- `?` — unknown.

The sidebar follows tab switches while open. Closing it keeps it closed until you reopen it with `<leader>aa`.

## Search and snapshots

Agent search matches names, workspaces, agent kinds, states, and task labels. In Snacks, Enter focuses an agent and Ctrl-O opens its snapshot. Workspace search filters the overview; attention search opens items for review.

A snapshot shows recent terminal history. Use `r` to refresh, `f` to toggle follow mode, Enter to focus the agent, and `q` to close. Interact with the full agent interface in Herdr.

The `picker` option supports `"snacks"`, `"native"`, `"fzf-lua"`, and `"auto"`. Automatic selection prefers Snacks, then fzf-lua, then `vim.ui.select`. Fzf-lua mode requires its Neovim plugin and the `fzf` executable; its additional shortcuts are documented in `:help herde-fzf`.

## Attention and notifications

The inbox shows input requests and unseen completions.

- `a` marks an agent's events as seen.
- `f` switches between active items, history, and all events.
- `w` filters by the current workspace.
- `m` mutes notifications for the highlighted workspace.
- Enter focuses the agent; `P` previews, `p` composes, and `o` opens its checkout.

Input requests remain active until the agent leaves its blocked state. Acknowledged completions move to history.

Use `:Herde quiet` to toggle notifications globally and `:Herde mute` to toggle them for the current workspace. Inbox items remain available while notifications are muted.

## Send editor context

Open the composer with `:Herde compose`, or `<leader>as` from the full keymap configuration.

- Normal mode includes the current file and cursor location.
- Visual mode includes the selected complete lines, their path, and line numbers.
- `<leader>ad` includes current-buffer diagnostics.

Check the workspace and agent in the composer title, edit your prompt, and press **Ctrl-S** to send. Close with `q` in normal mode or Ctrl-Q in insert mode to keep the draft for later.

Drafts stay available after a failed submission. If a send times out, check the agent before trying again: the prompt may already have been delivered. Approval dialogs and agent questions are handled in Herdr.

## Workspaces and saved layouts

Opening a checkout creates or reuses a workspace tab and restores its saved editor layout. Your previous tab and unsaved buffers stay available.

`<leader>ab` returns to the previous tab; pressing it again toggles back. `<leader>ap`, available in the full example, selects the previous agent in the overview.

Herde remembers sidebar width, collapsed workspaces, selected agents, preview visibility, and inbox filters. Saved editor layouts restore named files, splits, cursor positions, and views. Unsaved buffer contents remain in the running Neovim session and should be saved before exiting.

Task labels are restored for agents with a persistent conversation identity. Other labels last for the current session.

## Workspace statusline

The full [example configuration](examples/github.lua) adds `Workspace: <name>` beside the branch in lualine. It follows the workspace open in the active tab. For other tabs, it shows a matching project or the current directory name.

To add the field to your own lualine configuration:

```lua
function()
  return require("herde").workspace_statusline()
end
```

Agent counts are available separately:

```lua
function()
  local herde = package.loaded.herde
  return herde and herde.statusline() or ""
end
```

## Full keymap reference

[examples/github.lua](examples/github.lua) provides these mappings:

- `<leader>aa` — toggle overview.
- `<leader>aA` — focus the sidebar.
- `<leader>af` — find an agent.
- `<leader>ar` — refresh.
- `<leader>aw` — filter workspaces.
- `<leader>ai` — open the inbox.
- `<leader>a/` — search attention items.
- `<leader>an` — select the next agent needing attention.
- `<leader>ap` — select the previous agent.
- `<leader>ao` — open the checkout.
- `<leader>ab` — return to the previous tab.
- `<leader>al` — edit the task label.
- `<leader>as` — compose a prompt, including selected lines in visual mode.
- `<leader>ad` — compose with diagnostics.
- `<leader>aq` — toggle quiet mode.

## Configuration

Options are merged with the defaults. For example:

```lua
opts = {
  picker = "snacks",
  herdr = { command = "herdr" },
  sidebar = { width = 38, position = "right" },
  ui = { border = "rounded", icons = true },
  preview = { lines = 120, height = 12, follow = false },
  notifications = { enabled = true, blocked = true, completed = true },
  poll = { visible = 2000, hidden = 10000, max_backoff = 60000 },
}
```

Polling intervals are in milliseconds. Set `sidebar.position = "left"` to move the panel, or `ui.icons = false` for ASCII status markers.

Colors follow Neovim's highlight groups. You can customize individual groups:

```lua
vim.api.nvim_set_hl(0, "HerdeTitle", { link = "Special" })
```

See `:help herde-config` for the complete configuration reference.

## Commands and Lua API

Use `:Herde <command>`:

```text
toggle          focus-sidebar   agents          workspaces
inbox           attention       next-attention  previous
next            preview         focus           checkout
back            label           compose         acknowledge
quiet           mute            refresh         stop
```

Most commands also have a Lua function on `require("herde")`, with underscores replacing hyphens. The exceptions are `next` → `cycle(1)`, `acknowledge` → `ack()`, and `stop` → `teardown()`.

```lua
local herde = require("herde")
herde.compose({ selection = true })
herde.compose({ diagnostics = true })
herde.cycle(-1)
herde.back()
```

Use `:help herde` for the full command reference.

## Demo

To explore with sample agents, set:

```lua
opts = {
  backend = "demo",
  demo = { animate = true },
}
```

Then open `:Herde`. From a checkout, `make demo` starts a minimal demo session.

## Stored data

Layouts, labels, notification preferences, and attention history are stored under `stdpath("state")/herde`. Set `state_dir` to use another location. Prompt drafts last for the running session.

When several Neovim instances share the same state directory, one instance saves metadata; the others use temporary changes.

## Troubleshooting

### Disconnected or empty overview

Run `:Herde refresh`, then `:checkhealth herde`. Check that `herdr` is on Neovim's `PATH` and that the intended session is running. Set `herdr.session` when using a named session.

### Missing keymaps or statusline field

Use [the full configuration](examples/github.lua) for all suggested keys and the workspace field. Check for keymap conflicts or a later lualine override replacing the section containing the field.

### Attention item stays active

Marking an input request as seen leaves it active until the agent is ready again. Respond in Herdr, then refresh the overview.

### Checkout cannot be opened

Checkout navigation needs an existing local directory. Check the workspace path and whether it belongs to a remote machine.

### Prompt cannot be sent

Check the agent's state and respond to any pending dialog in Herdr. If the prompt starts with `-`, add an introductory sentence before the list.

## Development

```sh
make test
make demo
```

See [backend contracts](docs/backends.md), [architecture](docs/design.md), and [local development](docs/local-development.md) for implementation details and additional integration checks.
