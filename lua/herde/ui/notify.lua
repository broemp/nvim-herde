local U = require("herde.ui.util")
local M = {}
function M.new(ctx)
  local config = ctx.config.notifications or {}
  local data = ctx.persistence and ctx.persistence.data or { muted = {} }
  data.muted = data.muted or {}
  local self = { seen = {}, quiet_mode = data.quiet or config.quiet or false }
  function self:quiet(value)
    if value == nil then self.quiet_mode = not self.quiet_mode else self.quiet_mode = value end
    data.quiet = self.quiet_mode
    if ctx.persistence then ctx.persistence:save() end
    return self.quiet_mode
  end
  function self:mute(workspace_id, value)
    if not workspace_id then return end
    if value == nil then value = not data.muted[workspace_id] end
    data.muted[workspace_id] = value
    if ctx.persistence then ctx.persistence:save() end
    return value
  end
  function self:deliver(events)
    for _, event in ipairs(events or {}) do
      local id = event.id or event.agent_id .. ":" .. tostring(event.created_at)
      if not self.seen[id] then
        self.seen[id] = true
        self.order = self.order or {}
        self.order[#self.order + 1] = id
        while #self.order > 1000 do self.seen[table.remove(self.order, 1)] = nil end
        local kind = event.kind or event.type
        if config.enabled ~= false and not self.quiet_mode and not data.muted[event.workspace_id]
          and config[kind] ~= false then
          local agent = ctx.store:get_agent(event.agent_id)
          local ws = ctx.store:get_workspace(event.workspace_id)
          local name = agent and agent.name or event.agent_name or event.agent_id
          local text = name .. (kind == "blocked" and " needs input" or " completed work")
          local label = agent and U.label(ctx, agent)
          if label and label ~= "" then text = text .. "\n" .. label end
          vim.notify(U.clean(text), kind == "blocked" and vim.log.levels.WARN or vim.log.levels.INFO, {
            title = "Herde · " .. U.clean(ws and ws.name or "Agents"),
          })
        end
      end
    end
  end
  function self:stop() self.seen = {} end
  return self
end
return M
