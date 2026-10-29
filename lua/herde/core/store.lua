local M = {}

function M.new()
  local self = { snapshot = { workspaces = {}, agents = {} }, stale = false, has_snapshot = false, listeners = {} }
  function self:subscribe(fn)
    self.listeners[fn] = true
    return function() self.listeners[fn] = nil end
  end
  function self:emit()
    for fn in pairs(self.listeners) do
      local ok, err = pcall(fn, self)
      if not ok then vim.schedule(function() vim.notify("herde subscriber: " .. tostring(err), vim.log.levels.ERROR) end) end
    end
  end
  function self:get_agent(id)
    id = id or self.selected_id
    for _, agent in ipairs(self.snapshot.agents) do if agent.id == id then return agent end end
  end
  function self:get_workspace(id)
    id = id or self.workspace_id
    for _, workspace in ipairs(self.snapshot.workspaces) do if workspace.id == id then return workspace end end
  end
  function self:select(id)
    local agent = self:get_agent(id)
    if not agent then return nil, "Agent is no longer available" end
    self.selected_id, self.workspace_id = agent.id, agent.workspace_id
    if self.workspace_filter and self.workspace_filter ~= agent.workspace_id then
      self.workspace_filter = agent.workspace_id
    end
    self:emit()
    return agent
  end
  function self:update(snapshot)
    self.has_snapshot = true
    local previous = {}
    for _, agent in ipairs(self.snapshot.agents) do previous[agent.id] = agent end
    self.snapshot = snapshot
    self.snapshot.agents = self.snapshot.agents or {}
    self.snapshot.workspaces = self.snapshot.workspaces or {}
    self.cached_counts = nil
    for _, agent in ipairs(self.snapshot.agents) do
      local old = previous[agent.id]
      agent.state_since = old and old.state == agent.state and old.state_since or os.time()
    end
    self.stale, self.error = false, nil
    if self.selected_id and not self:get_agent(self.selected_id) then self.selected_id = nil end
    if self.workspace_id and not self:get_workspace(self.workspace_id) then self.workspace_id = nil end
    if not self.selected_id then
      for _, agent in ipairs(self.snapshot.agents) do
        if not self.workspace_id or agent.workspace_id == self.workspace_id then self.selected_id = agent.id; break end
      end
    end
    self:emit()
  end
  function self:counts()
    if self.cached_counts then return self.cached_counts end
    local counts = { total = #self.snapshot.agents, working = 0, blocked = 0, done = 0, idle = 0, unknown = 0 }
    for _, agent in ipairs(self.snapshot.agents) do
      local state = agent.state or "unknown"
      counts[state] = (counts[state] or 0) + 1
    end
    self.cached_counts = counts
    return counts
  end
  return self
end

return M
