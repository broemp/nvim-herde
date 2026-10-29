local herde = require("herde")
local dir = vim.fn.tempname()
herde.setup({ backend = "demo", state_dir = dir, notifications = { enabled = false } })
local ctx = herde.get_context()
assert(vim.wait(2000, function() return #ctx.store.snapshot.agents > 0 end), "demo snapshot timed out")
local original = vim.api.nvim_get_current_win()
herde.toggle()
assert(ctx.sidebar:is_open())
assert(vim.api.nvim_get_current_win() == original, "opening sidebar stole editor focus")
local agent = ctx.store.snapshot.agents[1]
ctx.actions.select(agent.id)
herde.preview(agent.id)
herde.inbox()
ctx.inbox:close()
herde.compose()
ctx.composer:close()
local columns, lines = vim.o.columns, vim.o.lines
ctx.preview:close()
vim.o.columns, vim.o.lines = 160, 50
ctx.preview:open(agent.id)
assert(vim.api.nvim_win_get_config(ctx.preview.win).relative == "", "wide layout should use a preview split")
ctx.preview:close()
vim.o.columns, vim.o.lines = 50, 16
ctx.preview:open(agent.id)
assert(vim.api.nvim_win_get_config(ctx.preview.win).relative == "editor", "small layout should use a floating preview")
assert(vim.api.nvim_win_get_width(ctx.preview.win) <= 46)
ctx.preview:close()
vim.o.columns, vim.o.lines = columns, lines
assert(type(herde.statusline()) == "string")
herde.teardown()
assert(herde.get_context() == nil)
herde.setup({ backend = "demo", state_dir = dir, notifications = { enabled = false } })
assert(vim.wait(1000, function() return #herde.get_context().store.snapshot.agents > 0 end))
herde.teardown()
vim.fn.delete(dir, "rf")

-- Large inventories are reduced by the core store without backend jobs in rendering.
local store = require("herde.core.store").new()
local agents = {}
for i = 1, 1000 do agents[i] = { id = "demo:" .. i, name = "agent" .. i, state = "working", workspace_id = "demo:w" } end
store:update({ workspaces = { { id = "demo:w", name = "large" } }, agents = agents })
assert(store:counts().working == 1000)
