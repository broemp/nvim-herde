local Refresh = require("herde.core.refresh")
local callbacks, updates, events, emits = {}, 0, 0, 0
local ctx = {
  config = require("herde.config").resolve({ backend = "demo" }),
  backend = { snapshot = function(_, cb) table.insert(callbacks, cb) end },
  store = { emit = function() emits = emits + 1 end, update = function() updates = updates + 1 end },
  attention = { update = function(_, _, baseline) if baseline then events = events + 1 end; return {} end },
  visible = function() return true end,
}
local r = Refresh.new(ctx)
local notified = 0
r:request(function() notified = notified + 1 end)
r:request(function() notified = notified + 1 end)
assert(#callbacks == 1, "overlapping refreshes must coalesce")
callbacks[1]("offline")
assert(vim.wait(1000, function() return notified == 2 end), "all waiters receive failure")
assert(ctx.store.stale and emits == 2 and not ctx.store.refreshing)
r:request()
callbacks[2](nil, { workspaces = {}, agents = {} })
assert(vim.wait(1000, function() return updates == 1 end))
assert(events == 1, "reconnect establishes baseline")
r:request()
r:stop()
callbacks[3](nil, { workspaces = {}, agents = {} })
vim.wait(20, function() return false end)
assert(updates == 1, "stopped refresh cannot update store")
