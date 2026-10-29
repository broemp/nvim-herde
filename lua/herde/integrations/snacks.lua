local U = require("herde.ui.util")
local M = {}
function M.available()
  local ok, picker = pcall(require, "snacks.picker")
  return ok and type(picker.pick) == "function"
end
function M.select(items, opts, callback, ctx)
  local picker = require("snacks.picker")
  local rows = {}
  for _, item in ipairs(items) do rows[#rows + 1] = { text = U.text(opts.format_item(item)), value = item } end
  local generation, busy, pending, alive = 0, false, nil, true
  local function snapshot(p)
    local item = p:current()
    local value = item and item.value
    local agent = value and (opts.agents and value or value.agent_id and ctx.store:get_agent(value.agent_id))
    if not agent then return end
    p:close()
    vim.schedule(function()
      if ctx.alive ~= false then U.action(ctx, "select", agent.id); U.action(ctx, "preview", agent.id) end
    end)
  end
  local function valid(req)
    return alive and ctx.alive ~= false and generation == req.generation
      and not req.preview.picker.closed and vim.api.nvim_buf_is_valid(req.preview.buf)
  end
  local pump
  pump = function()
    if busy or not pending or not alive then return end
    local req = pending
    pending, busy = nil, true
    ctx.backend:read(req.agent, function(err, text)
      vim.schedule(function()
        busy = false
        if valid(req) then
          if type(text) == "table" then text = text.text or text.output or "" end
          local body = err and ("Preview unavailable: " .. U.error(err)) or tostring(text or "")
          local lines = vim.split(U.clean(body:sub(-ctx.config.preview.max_bytes)), "\n", { plain = true })
          if #lines > ctx.config.preview.lines then lines = vim.list_slice(lines, #lines - ctx.config.preview.lines + 1) end
          req.preview.preview:set_lines(vim.list_extend(vim.deepcopy(req.header), lines))
        end
        pump()
      end)
    end)
  end
  return picker.pick({
    title = "herde / " .. (opts.title or opts.prompt) .. (opts.agents and
      ((ctx.backend.capabilities and ctx.backend.capabilities.focus == false) and " · Enter snapshot" or " · Enter focus · Ctrl-O snapshot") or ""),
    items = rows,
    format = "text",
    actions = { herde_snapshot = snapshot },
    win = {
      input = { keys = { ["<C-o>"] = { "herde_snapshot", mode = { "i", "n" }, desc = "Open read-only terminal snapshot" } } },
      list = { keys = { ["<C-o>"] = { "herde_snapshot", mode = { "n" }, desc = "Open read-only terminal snapshot" } } },
    },
    preview = function(p)
      generation, pending = generation + 1, nil
      p.preview:reset()
      if not p.item or not p.item.value then return end
      local item = p.item.value
      local agent = opts.agents and item or (item.agent_id and ctx.store:get_agent(item.agent_id))
      if not agent then
        local lines = { U.text(item.name or "Agent unavailable"), U.path(item.path or ""), "" }
        if item.agent_id then lines[2] = "This agent is no longer available."
        else
          for _, a in ipairs(ctx.store.snapshot.agents) do
            if not item.id or a.workspace_id == item.id then
              lines[#lines + 1] = U.text(a.name or a.id) .. " · " .. (U.states[a.state] or "Unknown")
            end
          end
        end
        p.preview:set_lines(lines)
        return
      end
      local ws = ctx.store:get_workspace(agent.workspace_id)
      local header = { U.text(agent.name or agent.id),
        U.text(ws and ws.name or "workspace") .. " · " .. U.text(agent.kind) .. " · " .. (U.states[agent.state] or "Unknown"),
        U.text(U.label(ctx, agent) or ""), "Terminal snapshot · read-only", "" }
      if ctx.backend.capabilities and ctx.backend.capabilities.read == false then
        p.preview:set_lines(vim.list_extend(header, { "Backend does not support previews." }))
        return
      end
      p.preview:set_lines(vim.list_extend(vim.deepcopy(header), { "Loading recent output…" }))
      pending = { preview = p, agent = agent, header = header, generation = generation }
      pump()
    end,
    confirm = function(p, item)
      p:close()
      if item then vim.schedule(function() if ctx.alive ~= false then callback(item.value) end end) end
    end,
    on_close = function() alive, pending, generation = false, nil, generation + 1 end,
  })
end
return M
