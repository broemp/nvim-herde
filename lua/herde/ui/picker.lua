local U = require("herde.ui.util")
local M = {}
function M.new(ctx)
  local self = {}
  local function select(items, opts, cb)
    if #items == 0 then vim.notify("No " .. (opts.title or "items") .. " available", vim.log.levels.INFO, { title = "Herde" }); return end
    if self.active then self.active.close(); self.active = nil end
    local snacks = require("herde.integrations.snacks")
    if (ctx.config.picker == "snacks" or ctx.config.picker == "auto") and snacks.available() then
      local picker = snacks.select(items, opts, cb, ctx)
      self.active = { close = function() if picker and not picker.closed then picker:close() end end }
      return
    end
    if ctx.config.picker == "snacks" then
      vim.notify("Snacks Picker is unavailable; using vim.ui.select", vim.log.levels.WARN, { title = "Herde" })
    end
    local fzf = require("herde.integrations.fzf")
    if ctx.config.picker ~= "native" and ctx.config.picker ~= "snacks" then
      if fzf.available() then self.active = fzf.select(items, opts, cb, ctx); return end
      if ctx.config.picker == "fzf-lua" then
        vim.notify("Herde requires fzf-lua and the fzf executable for this picker. Check :checkhealth herde.", vim.log.levels.WARN)
        return
      end
    end
    vim.ui.select(items, opts, cb)
  end
  function self:agents()
    local items = {}
    for _, agent in ipairs(ctx.store.snapshot.agents) do items[#items + 1] = agent end
    table.sort(items, function(a, b) return (a.name or a.id) < (b.name or b.id) end)
    select(items, {
      title = "agents", prompt = "Agents", agents = true,
      format_item = function(agent)
        local ws = ctx.store:get_workspace(agent.workspace_id)
        local label = U.label(ctx, agent)
        return U.clean((ws and ws.name or "workspace") .. " / " .. (agent.name or agent.id) .. " [" .. (agent.kind or "agent") .. ": " .. (agent.state or "unknown") .. "]" .. (label and " · " .. label or ""))
      end,
    }, function(agent)
      if not agent then return end
      if ctx.backend.capabilities and ctx.backend.capabilities.focus == false then
        -- Demo/read-only backends can still explore their terminal snapshots.
        U.action(ctx, "select", agent.id)
        U.action(ctx, "preview", agent.id)
      else
        U.action(ctx, "focus", agent.id)
      end
    end)
  end
  function self:workspaces()
    local items = { { id = false, name = "All workspaces" } }
    vim.list_extend(items, ctx.store.snapshot.workspaces)
    select(items, { title = "workspaces", prompt = "Workspaces", format_item = function(ws) return U.text(ws.name or ws.id) .. (ws.path and "  " .. U.path(ws.path) or "") end }, function(ws)
      if ws then U.action(ctx, "workspace", ws.id or nil) end
    end)
  end
  function self:attention()
    select(ctx.attention:list("active", ctx.store.workspace_filter), {
      title = "attention", prompt = "Attention",
      format_item = function(event)
        local agent = ctx.store:get_agent(event.agent_id)
        local ws = ctx.store:get_workspace(event.workspace_id)
        return (event.kind == "blocked" and "! " or "✓ ") .. U.text(ws and ws.name or "workspace") .. " / "
          .. U.text(agent and agent.name or event.name or event.agent_id) .. " · "
          .. (event.kind == "blocked" and "Needs input" or "Completed") .. " · "
          .. U.text(agent and U.label(ctx, agent) or "")
      end,
    }, function(event)
      if ctx.store:get_agent(event.agent_id) then U.action(ctx, "select", event.agent_id); U.action(ctx, "preview", event.agent_id) end
    end)
  end
  function self:stop() if self.active then self.active.close(); self.active = nil end end
  return self
end
return M
