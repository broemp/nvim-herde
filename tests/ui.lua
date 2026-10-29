local store = require("herde.core.store").new()
local attention = require("herde.core.attention").new({ history_limit = 10 })
local a = { id = "ui-a", name = "builder", workspace_id = "ui-w", kind = "pi", state = "working" }
local b = { id = "ui-b", name = "reviewer", workspace_id = "ui-x", kind = "codex", state = "blocked" }
local snapshot = { workspaces = { { id = "ui-w", name = "Project" }, { id = "ui-x", name = "Other" } }, agents = { a, b } }
store:update(snapshot)
attention:update(snapshot)
local layouts, callbacks, notifications = {}, {}, {}
local old_notify = vim.notify
vim.notify = function(message) notifications[#notifications + 1] = message end
local ctx = {
  store = store, attention = attention,
  config = { sidebar = { width = 30 }, preview = { lines = 3, max_bytes = 1024, height = 8 }, poll = { visible = 10000 }, notifications = {} },
  backend = { read = function(_, agent, cb) callbacks[#callbacks + 1] = { id = agent.id, callback = cb } end },
  workspaces = {
    label = function() return "A task" end,
    layout = function(_, id, value) if value then layouts[id] = value end; return layouts[id] or {} end,
  },
  persistence = { data = { muted = {} }, save = function() end },
  actions = {},
}
local sidebar = require("herde.ui.sidebar").new(ctx)
local preview = require("herde.ui.preview").new(ctx)
local inbox = require("herde.ui.inbox").new(ctx)
local composer = require("herde.ui.composer").new(ctx)
local notifier = require("herde.ui.notify").new(ctx)
local ok, err = xpcall(function()
  local original = vim.api.nvim_get_current_win()
  sidebar:open()
  assert(vim.api.nvim_get_current_win() == original, "sidebar must preserve editor focus")
  store:select(b.id)
  sidebar:render()
  local lines = table.concat(vim.api.nvim_buf_get_lines(sidebar.buf, 0, -1, false), "\n")
  assert(lines:find("Project") and lines:find("Other"), "agent selection must not filter overview")
  store.workspace_filter = "ui-w"
  sidebar:render()
  lines = table.concat(vim.api.nvim_buf_get_lines(sidebar.buf, 0, -1, false), "\n")
  assert(not lines:find("Other"), "explicit workspace filter must apply")
  store.workspace_filter = nil
  preview:open(a.id)
  preview:refresh()
  preview:open(b.id)
  assert(#callbacks == 1, "slow output reads must coalesce")
  callbacks[1].callback(nil, "stale output from a")
  assert(#callbacks == 2 and callbacks[2].id == b.id)
  callbacks[2].callback(nil, "1\n2\n3\n4\n5")
  lines = table.concat(vim.api.nvim_buf_get_lines(preview.buf, 0, -1, false), "\n")
  assert(not lines:find("stale output") and lines:find("reviewer") and not lines:find("\n1\n"), "preview must discard stale output and bound lines")
  preview:open(a.id)
  preview:refresh()
  preview:refresh()
  callbacks[3].callback(nil, "same target output")
  lines = table.concat(vim.api.nvim_buf_get_lines(preview.buf, 0, -1, false), "\n")
  assert(lines:find("same target output") and #callbacks == 4, "slow same-target reads must render before one queued refresh")
  preview:close()
  callbacks[4].callback(nil, "late output after close")
  inbox:open()
  assert(inbox:is_open())
  inbox:close()
  composer:open(a.id, "exact context")
  ctx.actions.submit = function(id, text, cb)
    assert(id == a.id and text == "exact context")
    cb("delivery uncertain")
  end
  composer:send()
  assert(composer:is_open() and composer.drafts[a.id] == "exact context", "failed sends must retain drafts")
  vim.api.nvim_win_close(composer.win, true)
  assert(composer.drafts[a.id] == "exact context", "external close must retain draft")
  composer:open(a.id)
  ctx.actions.submit = function(_, _, cb) cb(nil) end
  composer:send()
  assert(not composer:is_open() and composer.drafts[a.id] == nil, "confirmed send clears matching draft")
  notifications = {}
  local event = { id = "ui-e1", kind = "completed", agent_id = a.id, workspace_id = a.workspace_id }
  notifier:deliver({ event }); notifier:deliver({ event })
  assert(#notifications == 1, "notification must deduplicate")
  notifier:mute(a.workspace_id, true)
  notifier:deliver({ vim.tbl_extend("force", event, { id = "ui-e2" }) })
  assert(#notifications == 1)
  notifier:mute(a.workspace_id, false)
  notifier:quiet(true)
  notifier:deliver({ vim.tbl_extend("force", event, { id = "ui-e3" }) })
  assert(#notifications == 1 and ctx.persistence.data.quiet == true)
end, debug.traceback)
for _, component in ipairs({ sidebar, preview, inbox, composer, notifier }) do component:stop() end
vim.notify = old_notify
assert(ok, err)
print("UI interactions passed")
