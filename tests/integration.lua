local herde = require("herde")
local dir = vim.fn.tempname()
local inventory = {
  namespace = "integration",
  workspaces = { { id = "w1", name = "one" }, { id = "w2", name = "two" } },
  agents = {
    { id = "a1", workspace_id = "w1", name = "first", state = "idle", kind = "pi", identity_stable = true },
    { id = "a2", workspace_id = "w1", name = "second", state = "idle", kind = "codex", identity_stable = true },
    { id = "a3", workspace_id = "w2", name = "third", state = "idle", kind = "pi", identity_stable = true },
  },
}
local calls, prompts, stopped = 0, 0, 0
local deferred, pending
local backend = {
  capabilities = { snapshot = true, read = true, focus = true, prompt = true },
  snapshot = function(_, cb)
    calls = calls + 1
    if deferred then pending = cb else cb(nil, vim.deepcopy(inventory)) end
  end,
  read = function(_, _, cb) cb(nil, "Recent agent output") end,
  focus = function(_, _, cb) cb(nil, true) end,
  prompt = function(_, _, _, cb) prompts = prompts + 1; cb(nil, true) end,
  stop = function() stopped = stopped + 1 end,
}
local opts = { backend = backend, state_dir = dir, picker = "native", notifications = { enabled = false },
  poll = { visible = 100, hidden = 100, max_backoff = 100 } }
herde.setup(opts)
local ctx = herde.get_context()
assert(vim.wait(500, function() return #ctx.store.snapshot.agents == 3 end))
local editor = vim.api.nvim_get_current_win()
herde.toggle()
assert(vim.api.nvim_get_current_win() == editor, "overview must preserve editor focus")
ctx.actions.workspace("w1")
ctx.actions.select("a2")
ctx.actions.preview("a2")
ctx.actions.workspace("w2")
assert(ctx.store.selected_id == "a3" and ctx.store.workspace_filter == "w2")
assert(ctx.workspaces:layout("w1").selected_id == "a2")
assert(ctx.workspaces:layout("w1").preview_visible, "switching workspace must preserve preview preference")
ctx.actions.workspace("w1")
assert(ctx.store.selected_id == "a2" and ctx.preview:is_open(), "workspace layout restores selection and preview")
ctx.workspaces:layout("w2", { selected_id = "a1" })
ctx.actions.workspace("w2")
assert(ctx.store.selected_id == "a3", "foreign saved selections must not cross workspace filters")
ctx.actions.workspace(false)
assert(not ctx.store.workspace_filter and not ctx.store.workspace_id, "all-workspaces selector removes filtering")

ctx.actions.select("a1")
inventory.agents[1].id = "a-replacement"
local submit_error
ctx.actions.submit("a1", "Do something", function(err) submit_error = err end)
assert(vim.wait(500, function() return submit_error ~= nil end))
assert(prompts == 0 and submit_error:find("replaced"), "target occupant must be revalidated before submission")

local notify = vim.notify
local callback_errors = 0
vim.notify = function(msg) if tostring(msg):find("refresh callback", 1, true) then callback_errors = callback_errors + 1 end end
ctx.refresh:request(function() error("deliberate test callback failure") end)
assert(vim.wait(500, function() return callback_errors == 1 end))
local before = calls
assert(vim.wait(500, function() return calls > before end), "a failing refresh subscriber must not stop polling")
vim.notify = notify

deferred = true
ctx.refresh:request()
assert(pending)
local previous = ctx.store.snapshot
herde.teardown()
pending(nil, vim.deepcopy(inventory))
vim.wait(20)
assert(ctx.store.snapshot == previous and herde.get_context() == nil, "late callbacks must not resurrect stopped state")
assert(stopped == 1)
deferred = false
herde.setup(opts)
local reopened = herde.get_context()
assert(reopened.persistence.writable, "teardown must release the persistence writer lock")
assert(vim.wait(500, function() return #reopened.store.snapshot.agents == 3 end))
herde.teardown()
vim.fn.delete(dir, "rf")
print("integration checks passed")
