local M = {}

function M.new(store, backend, attention)
  local self = { history = {} }
  function self:select(id)
    local current = store.selected_id
    local agent, err = store:select(id)
    if agent and current and current ~= id then
      self.history[#self.history + 1] = current
      if #self.history > 100 then table.remove(self.history, 1) end
    end
    return agent, err
  end
  function self:focus(id, cb)
    local agent = store:get_agent(id)
    cb = cb or function(err) if err then vim.notify(tostring(err), vim.log.levels.WARN) end end
    if not agent then cb("Agent is no longer available"); return end
    if store.stale then cb("Backend is disconnected; refresh before focusing an agent"); return end
    if backend.capabilities and backend.capabilities.focus == false then cb("This backend cannot focus terminals"); return end
    backend:focus(agent, function(err, result)
      if not err then self:select(agent.id); attention:ack(agent.id); store:emit() end
      cb(err, result)
    end)
  end
  function self:previous()
    while #self.history > 0 do
      local id = table.remove(self.history)
      if id ~= store.selected_id and store:get_agent(id) then
        local current = store.selected_id
        local agent = store:select(id)
        if current then self.history[#self.history + 1] = current end
        return agent
      end
    end
    return nil, "No previous live agent"
  end
  function self:cycle(delta)
    local agents = {}
    for _, agent in ipairs(store.snapshot.agents) do
      if not store.workspace_id or agent.workspace_id == store.workspace_id then agents[#agents + 1] = agent end
    end
    if #agents == 0 then return nil, "No agents in this workspace" end
    local index = 0
    for i, agent in ipairs(agents) do if agent.id == store.selected_id then index = i; break end end
    return self:select(agents[((index - 1 + (delta or 1)) % #agents) + 1].id)
  end
  function self:next_attention()
    local ids, seen = {}, {}
    for _, event in ipairs(attention:list("active")) do
      if store:get_agent(event.agent_id) and not seen[event.agent_id] then
        ids[#ids + 1], seen[event.agent_id] = event.agent_id, true
      end
    end
    if #ids == 0 then return nil, "No agents need attention" end
    local index = 0
    for i, id in ipairs(ids) do if id == store.selected_id then index = i; break end end
    return self:select(ids[(index % #ids) + 1])
  end
  return self
end

return M
