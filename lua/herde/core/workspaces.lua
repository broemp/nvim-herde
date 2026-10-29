local M = {}

function M.new(store, persistence)
  local self = { ephemeral_labels = {} }
  function self:label(agent_id, value)
    local agent = store:get_agent(agent_id)
    local labels = agent and agent.identity_stable and persistence.data.labels or self.ephemeral_labels
    if value ~= nil then
      if not agent then return nil, "Agent is no longer available" end
      labels[agent_id] = value ~= "" and value or nil
      persistence:save()
      store:emit()
    end
    return labels[agent_id]
  end
  function self:layout(workspace_id, value)
    if not workspace_id then return {} end
    if value ~= nil then
      persistence.data.layouts[workspace_id] = vim.tbl_deep_extend("force", persistence.data.layouts[workspace_id] or {}, value)
      persistence:save()
    end
    return persistence.data.layouts[workspace_id] or {}
  end
  function self:mute(workspace_id, value)
    if value ~= nil then persistence.data.muted[workspace_id] = value; persistence:save() end
    return persistence.data.muted[workspace_id] == true
  end
  return self
end

return M
