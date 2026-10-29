-- Optional integration check: put installed snacks.nvim on runtimepath first.
vim.opt.rtp:prepend(vim.fn.getcwd())
require("snacks").setup({ picker = { enabled = true } })
local herde = require("herde")
local state = vim.fn.tempname()
herde.setup({ backend = "demo", picker = "snacks", state_dir = state, notifications = { enabled = false } })
local ctx = herde.get_context()
assert(vim.wait(1000, function() return #ctx.store.snapshot.agents == 3 end))
local function contains(text)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local lines = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
      if lines:find(text, 1, true) then return true end
    end
  end
  return false
end
herde.agents()
assert(vim.wait(2000, function() return contains("Demo preview for") end), "agent output must appear in actual Snacks preview")
local active = require("snacks.picker").get()[1]
assert(active and active.opts.title:find("herde / agents", 1, true))
active.opts.confirm(active, active:current())
assert(vim.wait(1000, function() return ctx.preview:is_open() end), "confirm must open main preview")
herde.workspaces()
assert(vim.wait(1000, function() return contains("Current project") end))
ctx.picker:stop()
assert(vim.wait(1000, function() return #require("snacks.picker").get() == 0 end), "stop must close the picker")
herde.attention()
assert(vim.wait(1000, function() return contains("Should retries include timeouts?") end), "attention should preview actual agent output")
assert(not package.loaded["fzf-lua"], "Snacks mode must never load fzf-lua")
herde.teardown()
-- A focus-capable backend must jump to the agent, never substitute a snapshot.
local focused = {}
local inventory = {
  namespace = "jump", workspaces = { { id = "jump/ws", name = "Jump workspace" } },
  agents = { { id = "jump/agent", name = "worker", kind = "pi", workspace_id = "jump/ws", state = "working" } },
}
local backend = {
  namespace = "jump", capabilities = { read = true, focus = true, prompt = false },
  snapshot = function(_, cb) cb(nil, vim.deepcopy(inventory)) end,
  read = function(_, _, cb) cb(nil, "Old terminal history: tests/run.lua traceback") end,
  focus = function(_, agent, cb) focused[#focused + 1] = agent.id; cb(nil, true) end,
  prompt = function(_, _, _, cb) cb("unsupported") end,
  stop = function() end,
}
herde.setup({ backend = backend, picker = "snacks", state_dir = state, notifications = { enabled = false } })
ctx = herde.get_context()
assert(vim.wait(1000, function() return ctx.store.has_snapshot end))
herde.agents()
assert(vim.wait(1000, function() return contains("Terminal snapshot · read-only") end))
active = require("snacks.picker").get()[1]
active.opts.confirm(active, active:current())
assert(vim.wait(1000, function() return #focused == 1 end))
assert(focused[1] == "jump/agent" and not ctx.preview:is_open(), "Enter must focus the live pane without opening a snapshot")
herde.agents()
active = require("snacks.picker").get()[1]
assert(vim.wait(1000, function() return active:current() ~= nil end))
active.opts.actions.herde_snapshot(active)
assert(vim.wait(1000, function() return ctx.preview:is_open() end))
assert(#focused == 1, "explicit snapshot action must not focus the live agent")
herde.agents()
active = require("snacks.picker").get()[1]
assert(vim.wait(1000, function() return active:current() ~= nil end))
active.opts.confirm(active, active:current())
assert(vim.wait(1000, function() return #focused == 2 end))
assert(not ctx.preview:is_open(), "a successful jump must dismiss the old snapshot")
herde.teardown()
vim.fn.delete(state, "rf")
print("Real Snacks integration passed: agent focus, explicit snapshots, workspaces, attention, cleanup")
vim.cmd("qa!")
