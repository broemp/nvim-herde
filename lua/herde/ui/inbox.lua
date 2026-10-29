local U = require("herde.ui.util")
local M = {}
function M.new(ctx)
  local self = { rows = {}, filter = "active", workspace_id = nil }
  local function current()
    if not U.valid(self.win) then return end
    return self.rows[vim.api.nvim_win_get_cursor(self.win)[1]]
  end
  function self:render()
    if not U.valid(self.win) then return end
    local previous = current()
    local view = vim.api.nvim_win_call(self.win, vim.fn.winsaveview)
    local offset = 0
    if previous then
      local first = view.lnum
      while self.rows[first - 1] and self.rows[first - 1].id == previous.id do first = first - 1 end
      offset = view.lnum - first
    end
    local width = math.max(10, vim.api.nvim_win_get_width(self.win) - 4)
    local events = ctx.attention:list(self.filter, self.workspace_id)
    local lines = { "", "  " .. U.columns("Attention", #events .. " items", width),
      "  " .. self.filter .. (self.workspace_id and " · this workspace" or " · all workspaces"),
      "  " .. string.rep("─", width), "" }
    local highlights = { { 1, "HerdeTitle" }, { 2, "HerdeAccent" }, { 3, "HerdeSeparator" } }
    self.rows = {}
    for _, event in ipairs(events) do
      local agent = ctx.store:get_agent(event.agent_id)
      local ws = ctx.store:get_workspace(event.workspace_id)
      local kind = event.kind or event.type
      local state = kind == "blocked" and "Needs input" or "Completed"
      local name = agent and agent.name or event.name or event.agent_id
      local title = U.columns((kind == "blocked" and "! " or "✓ ") .. U.text(name), U.age(event.created_at) .. " ago", width)
      lines[#lines + 1] = "  " .. title
      highlights[#highlights + 1] = { #lines - 1, kind == "blocked" and "HerdeBlocked" or "HerdeDone", 2, kind == "blocked" and 3 or 5 }
      self.rows[#lines] = event
      local flags = (event.acknowledged and " [seen]" or "") .. (event.resolved and " [resolved]" or "")
      lines[#lines + 1] = "    " .. U.clip((ws and ws.name or "workspace") .. " · " .. state .. flags, width - 2)
      highlights[#highlights + 1] = { #lines - 1, "HerdeMuted" }
      self.rows[#lines] = event
      local label = agent and U.label(ctx, agent)
      if label and label ~= "" then lines[#lines + 1] = "    " .. U.clip(label, width - 2); self.rows[#lines] = event end
      lines[#lines + 1] = ""
    end
    if #events == 0 then lines[#lines + 1] = "No attention events in this view." end
    if ctx.store.stale then lines[#lines + 1] = "Backend unavailable: these events may be stale." end
    U.lines(self.buf, lines)
    U.paint(self.buf, highlights)
    if previous then
      for i = 1, #lines do
        if self.rows[i] and self.rows[i].id == previous.id then
          local target = i
          while target < i + offset and self.rows[target + 1] and self.rows[target + 1].id == previous.id do target = target + 1 end
          view.topline = math.max(1, view.topline + target - view.lnum)
          view.lnum, view.col = target, math.min(view.col, math.max(0, #lines[target] - 1))
          vim.api.nvim_win_call(self.win, function() vim.fn.winrestview(view) end)
          return
        end
      end
    end
    for i = 1, #lines do if self.rows[i] then pcall(vim.api.nvim_win_set_cursor, self.win, { i, 0 }); break end end
  end
  function self:open()
    if U.valid(self.win) then vim.api.nvim_set_current_win(self.win); return end
    local layout = ctx.workspaces and ctx.workspaces:layout(ctx.store.workspace_id) or {}
    self.filter = layout.inbox_filter or "active"
    self.buf = U.buf("inbox")
    local ui = vim.tbl_extend("force", ctx.config.ui or {}, { footer = "↵ focus   / search   a seen   f filter   ? help" })
    self.win = U.float(self.buf, " herde / inbox ", 94, 26, true, ui)
    U.map(self.buf, "/", function() U.action(ctx, "attention") end, "search attention")
    U.map(self.buf, "?", function()
      vim.notify("Inbox: Enter focus · P preview · p prompt · o checkout · a seen · / search · f active/history/all · w workspace · m mute · q close", vim.log.levels.INFO)
    end, "help")
    U.map(self.buf, "q", function() self:close() end, "close inbox")
    for key, action in pairs({ ["<CR>"] = "focus", o = "checkout", p = "compose", P = "preview", a = "ack" }) do
      local act = action
      U.map(self.buf, key, function() local event = current(); if event then U.action(ctx, act, event.agent_id); self:render() end end, act)
    end
    U.map(self.buf, "f", function()
      self.filter = ({ active = "history", history = "all", all = "active" })[self.filter] or "active"
      if ctx.workspaces and ctx.store.workspace_id then
        local l = ctx.workspaces:layout(ctx.store.workspace_id) or {}; l.inbox_filter = self.filter; ctx.workspaces:layout(ctx.store.workspace_id, l)
      end
      self:render()
    end, "change filter")
    U.map(self.buf, "w", function() self.workspace_id = not self.workspace_id and ctx.store.workspace_id or nil; self:render() end, "toggle workspace filter")
    U.map(self.buf, "m", function() local event = current(); if event then U.action(ctx, "mute", event.workspace_id) end end, "mute workspace notifications")
    self:render()
  end
  function self:close() U.delete(self) end
  function self:toggle() if U.valid(self.win) then self:close() else self:open() end end
  function self:stop() if self.unsubscribe then self.unsubscribe() end; self:close() end
  function self:is_open() return U.valid(self.win) or false end
  self.unsubscribe = ctx.store:subscribe(function() self:render() end)
  return self
end
return M
