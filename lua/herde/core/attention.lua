local M = {}

function M.new(opts, data)
  opts = opts or {}
  local events, foreign = {}, {}
  if type(data) == "table" then
    for _, event in ipairs(data) do
      if type(event) == "table" and type(event.id) == "string" and type(event.agent_id) == "string"
        and type(event.workspace_id) == "string" and (event.kind == "blocked" or event.kind == "completed") then
        event = vim.deepcopy(event)
        event.created_at = type(event.created_at) == "number" and event.created_at or os.time()
        event.acknowledged, event.resolved = event.acknowledged == true, event.resolved == true
        local belongs = not opts.namespace or event.namespace == opts.namespace
          or (not event.namespace and event.agent_id:sub(1, #opts.namespace + 1) == opts.namespace .. "/")
        local target = belongs and events or foreign
        target[#target + 1] = event
      end
    end
  end
  local self = { events = events, observed = {}, had_work = {}, sequence = 0, initialized = false }
  local limit = opts.history_limit or opts.max_events or 200
  local function unresolved(agent_id)
    for i = #self.events, 1, -1 do
      local event = self.events[i]
      if event.agent_id == agent_id and event.kind == "blocked" and not event.resolved then return event end
    end
  end
  function self:update(snapshot, baseline)
    baseline = baseline == true or not self.initialized
    local notifications, present = {}, {}
    for _, agent in ipairs(snapshot.agents or {}) do
      present[agent.id] = true
      local blocked = unresolved(agent.id)
      -- Unknown is not evidence that a request has been answered.
      if blocked and agent.state ~= "blocked" and agent.state ~= "unknown" then blocked.resolved = true end
      local kind
      if agent.state == "blocked" and not blocked then kind = "blocked" end
      if not baseline and self.had_work[agent.id] and (agent.state == "idle" or agent.state == "done") then kind = "completed" end
      if kind then
        self.sequence = self.sequence + 1
        local event = {
          id = agent.id .. ":" .. tostring(vim.uv.hrtime()) .. ":" .. self.sequence,
          agent_id = agent.id, workspace_id = agent.workspace_id,
          kind = kind, name = agent.name, state = agent.state,
          namespace = opts.namespace or snapshot.namespace,
          created_at = os.time(), acknowledged = false, resolved = false,
        }
        self.events[#self.events + 1] = event
        if not baseline then notifications[#notifications + 1] = event end
      end
      self.observed[agent.id] = agent.state
      if baseline or agent.state == "idle" or agent.state == "done" then self.had_work[agent.id] = nil end
      if agent.state == "working" then self.had_work[agent.id] = true end
    end
    for id in pairs(self.observed) do
      if not present[id] then
        self.observed[id] = nil
        self.had_work[id] = nil
      end
    end
    -- Also reconcile events loaded from disk before any agent was observed.
    for _, event in ipairs(self.events) do
      if event.kind == "blocked" and not present[event.agent_id] then event.resolved = true end
    end
    -- Retain active input requests even when bounded history is full.
    while #self.events > limit do
      local removed = false
      for i, event in ipairs(self.events) do
        if event.kind ~= "blocked" or event.resolved then table.remove(self.events, i); removed = true; break end
      end
      if not removed then break end
    end
    self.initialized = true
    return notifications
  end
  function self:ack(agent_id)
    for _, event in ipairs(self.events) do if event.agent_id == agent_id then event.acknowledged = true end end
  end
  function self:list(filter, workspace_id)
    filter = filter or "active"
    local events = {}
    for i = #self.events, 1, -1 do
      local event = self.events[i]
      local active = (event.kind == "blocked" and not event.resolved) or (event.kind == "completed" and not event.acknowledged)
      local matches = filter == "all" or (filter == "active" and active) or (filter == "history" and not active)
        or (filter == "blocked" and event.kind == "blocked" and not event.resolved)
        or (filter == "completed" and event.kind == "completed" and not event.acknowledged)
      if matches and (not workspace_id or workspace_id == event.workspace_id) then events[#events + 1] = event end
    end
    return events
  end
  function self:serialize()
    -- Keep other backends' history on disk without showing it in this inbox.
    return vim.list_extend(vim.deepcopy(foreign), vim.deepcopy(self.events))
  end
  return self
end

return M
