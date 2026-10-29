local M = {}
function M.new(ctx)
  local self = { stopped = false, busy = false, generation = 0, failures = 0 }
  local timer = (vim.uv or vim.loop).new_timer()
  local function schedule()
    if self.stopped or timer:is_closing() then return end
    local interval = ctx.visible() and ctx.config.poll.visible or ctx.config.poll.hidden
    interval = math.min(ctx.config.poll.max_backoff, interval * 2 ^ math.min(self.failures, 5))
    timer:start(interval, 0, vim.schedule_wrap(function() self:request() end))
  end
  function self:request(cb)
    if self.stopped then if cb then cb("herde stopped") end; return end
    if self.busy then
      if cb then table.insert(self.waiters, cb) end
      return
    end
    self.busy, self.waiters = true, cb and { cb } or {}
    ctx.store.refreshing = true
    ctx.store:emit()
    timer:stop()
    local generation = self.generation
    local completed = false
    local function done(err, snapshot)
      if completed then return end
      completed = true
      vim.schedule(function()
        if self.stopped or generation ~= self.generation then return end
        self.busy = false
        ctx.store.refreshing = false
        if not err and (type(snapshot) ~= "table" or type(snapshot.agents) ~= "table" or type(snapshot.workspaces) ~= "table") then
          err = "Backend returned an invalid inventory snapshot"
        end
        if err then
          self.failures = self.failures + 1
          ctx.store.stale, ctx.store.error = true, tostring(type(err) == "table" and (err.message or vim.inspect(err)) or err)
          ctx.store:emit()
        else
          local baseline = self.failures > 0
          self.failures = 0
          local events = ctx.attention:update(snapshot, baseline and true or nil)
          ctx.store:update(snapshot)
          if ctx.notify then
            local ok, notify_err = pcall(ctx.notify, events)
            if not ok then vim.notify("herde notification: " .. tostring(notify_err), vim.log.levels.WARN) end
          end
        end
        local waiters = self.waiters
        self.waiters = {}
        schedule()
        for _, fn in ipairs(waiters) do
          local ok, callback_err = pcall(fn, err, snapshot)
          if not ok then vim.notify("herde refresh callback: " .. tostring(callback_err), vim.log.levels.WARN) end
        end
      end)
    end
    local ok, err = pcall(ctx.backend.snapshot, ctx.backend, done)
    if not ok then done(err) end
  end
  function self:stop()
    self.stopped = true
    self.generation = self.generation + 1
    timer:stop()
    if not timer:is_closing() then timer:close() end
    self.waiters = {}
  end
  return self
end
return M
