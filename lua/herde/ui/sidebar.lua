local U = require("herde.ui.util")
local M = {}
function M.new(ctx)
  local self = { ctx = ctx, rows = {}, collapsed = {}, rendering = false }
  local group = vim.api.nvim_create_augroup("HerdeSidebar" .. tostring(self):gsub("[^%w]", ""), { clear = true })
  local function selected()
    if not U.valid(self.win) then return end
    return self.rows[vim.api.nvim_win_get_cursor(self.win)[1]]
  end
  function self:is_open()
    return U.valid(self.win) and vim.api.nvim_win_get_tabpage(self.win) == vim.api.nvim_get_current_tabpage() or false
  end
  local function save_layout()
    if not ctx.workspaces then return end
    for _, ws in ipairs(ctx.store.snapshot.workspaces) do
      local layout = ctx.workspaces:layout(ws.id) or {}
      if self.collapsed[ws.id] ~= nil then layout.collapsed = self.collapsed[ws.id] end
      if ws.id == ctx.store.workspace_id and U.valid(self.win) then layout.width = vim.api.nvim_win_get_width(self.win) end
      local selected_agent = ctx.store:get_agent(ctx.store.selected_id)
      if selected_agent and selected_agent.workspace_id == ws.id then layout.selected_id = selected_agent.id end
      ctx.workspaces:layout(ws.id, layout)
    end
  end
  vim.api.nvim_create_autocmd("WinResized", { group = group, callback = function()
    if self:is_open() then save_layout() end
  end })
  function self:render()
    if not self:is_open() then return end
    self.rendering = true
    local old = selected()
    local wanted = ctx.store.selected_id
    local view = vim.api.nvim_win_call(self.win, vim.fn.winsaveview)
    local selection_changed = wanted ~= self.last_selected
    local width = math.max(12, vim.api.nvim_win_get_width(self.win) - 4)
    local counts = ctx.store:counts()
    local attention = #ctx.attention:list("active")
    local summary = counts.working .. " working · " .. attention .. " attention"
    if ctx.store.refreshing then summary = "Refreshing…"
    elseif ctx.store.stale then summary = "Disconnected · counts unavailable"
    elseif not ctx.store.has_snapshot then summary = "Connecting…" end
    local lines = {
      "  herde",
      "  " .. U.clip(summary, width),
      "  " .. string.rep("─", width),
      "  i inbox   / search   ? help",
      "",
    }
    local checkout = vim.t.herde_workspace_id and ctx.store:get_workspace(vim.t.herde_workspace_id)
    if checkout then lines[#lines + 1] = "  " .. U.clip("Editing: " .. U.text(checkout.name or checkout.id), width) end
    if ctx.previous_tab and vim.api.nvim_tabpage_is_valid(ctx.previous_tab) then
      lines[#lines + 1] = "  b back to previous workspace"
    end
    self.rows = {}
    local highlights = { { 0, "HerdeTitle" }, { 1, attention > 0 and "HerdeBlocked" or "HerdeMuted" },
      { 2, "HerdeSeparator" }, { 3, "HerdeHint" } }
    local function add(text, group, row)
      lines[#lines + 1] = "  " .. U.clip(text, width)
      if group then highlights[#highlights + 1] = { #lines - 1, group } end
      self.rows[#lines] = row
      return #lines - 1
    end
    if ctx.store.error then
      add("Connection failed · r to retry", "HerdeError")
      add(U.error(ctx.store.error), "HerdeMuted")
      add(":checkhealth herde for details", "HerdeHint")
    end
    local agents = ctx.store.snapshot.agents
    local unicode = not ctx.config.ui or ctx.config.ui.icons ~= false
    local icons = ctx.config.sidebar.icons or (unicode and U.symbols or U.ascii_symbols)
    local projects = require("herde.ui.projects").group(ctx.store.snapshot.workspaces, ctx.store.workspace_filter)
    for project_index, project in ipairs(projects) do
      add(tostring(project_index) .. ". " .. U.text(project.name), "HerdeTitle")
      for workspace_index, ws in ipairs(project.workspaces) do
        if self.collapsed[ws.id] == nil then
          local layout = ctx.workspaces and ctx.workspaces:layout(ws.id) or {}
          self.collapsed[ws.id] = layout.collapsed or false
        end
        local children = {}
        for _, agent in ipairs(agents) do if agent.workspace_id == ws.id then children[#children + 1] = agent end end
        local priority = { blocked = 1, done = 2, working = 3, idle = 4, unknown = 5 }
        table.sort(children, function(a, b)
          local pa, pb = priority[a.state] or 5, priority[b.state] or 5
          if pa ~= pb then return pa < pb end
          return (a.name or a.id) < (b.name or b.id)
        end)
        local marker = self.collapsed[ws.id] and (unicode and "▸" or ">") or (unicode and "▾" or "v")
        local wsrow = { type = "workspace", id = ws.id, part = "title" }
        add(U.columns("  " .. workspace_index .. ". " .. marker .. " " .. U.text(ws.name or ws.id), tostring(#children), width), "HerdeWorkspace", wsrow)
        if not self.collapsed[ws.id] then
          if ws.path then add("    " .. U.path(ws.path), "HerdeHint", { type = "workspace", id = ws.id, part = "path" }) end
          for _, agent in ipairs(children) do
            local row = { type = "agent", id = agent.id, part = "title" }
            local symbol = icons[agent.state] or "?"
            local n = add("    " .. symbol .. " " .. U.text(agent.name or agent.id), nil, row)
            highlights[#highlights + 1] = { n, "Herde" .. (agent.state or "unknown"):gsub("^%l", string.upper), 6, 6 + #symbol }
            local label = U.label(ctx, agent)
            if label and label ~= "" then add("      " .. U.text(label), "HerdeLabel", { type = "agent", id = agent.id, part = "label" }) end
            add("      " .. U.text(agent.kind or "agent") .. " · " .. (U.states[agent.state] or "Unknown") .. " · " .. U.age(agent.state_since), "HerdeMuted", { type = "agent", id = agent.id, part = "state" })
          end
        end
        lines[#lines + 1] = ""
      end
    end
    if #ctx.store.snapshot.workspaces == 0 then add("No workspaces · r to refresh", "HerdeMuted") end
    U.lines(self.buf, lines)
    U.paint(self.buf, highlights)
    local target
    if not selection_changed and old then
      for i = 1, #lines do
        local row = self.rows[i]
        if row and row.type == old.type and row.id == old.id and row.part == old.part then target = i; break end
      end
      if not target then
        -- A fold can remove a path or an agent row. Anchor to its parent
        -- workspace instead of falling through to an unrelated selected agent.
        local agent = old.type == "agent" and ctx.store:get_agent(old.id)
        local workspace_id = old.type == "workspace" and old.id or (agent and agent.workspace_id)
        for i = 1, #lines do
          local row = self.rows[i]
          if row and row.type == "workspace" and row.id == workspace_id and row.part == "title" then target = i; break end
        end
      end
    end
    if not selection_changed and not old then target = math.min(view.lnum, #lines) end
    if not target then
      for i = 1, #lines do
        local row = self.rows[i]
        if row and row.type == "agent" and row.id == wanted then target = i; break end
      end
    end
    if target then
      if not selection_changed then
        view.topline = math.max(1, view.topline + target - view.lnum)
        view.lnum = target
        view.col = math.min(view.col, math.max(0, #(lines[target] or "") - 1))
        vim.api.nvim_win_call(self.win, function() vim.fn.winrestview(view) end)
      else
        pcall(vim.api.nvim_win_set_cursor, self.win, { target, 0 })
      end
    end
    self.last_selected = wanted
    self.rendering = false
  end
  function self:close() self.enabled = false; save_layout(); U.close(self) end
  function self:open()
    self.enabled = true
    if self:is_open() then return end
    -- A Neovim split belongs to one tab. Carry the panel to the active tab
    -- rather than treating a valid window in another tab as a visible panel.
    if U.valid(self.win) then save_layout(); U.close(self) end
    local original = vim.api.nvim_get_current_win()
    local width = (ctx.config.sidebar or {}).width or 32
    local layout = ctx.workspaces and ctx.workspaces:layout(ctx.store.workspace_id) or {}
    width = layout.width or width
    local side = ctx.config.sidebar.position == "left" and "topleft" or "botright"
    vim.cmd(side .. " vertical " .. math.min(width, math.max(12, vim.o.columns - 20)) .. "split")
    self.win = vim.api.nvim_get_current_win()
    local win = self.win
    vim.api.nvim_create_autocmd("WinClosed", { group = group, pattern = tostring(win), once = true, callback = function()
      if self.win == win then save_layout(); self.win = nil; self.enabled = false end
    end })
    if not self.buf or not vim.api.nvim_buf_is_valid(self.buf) then
      self.buf = U.buf("sidebar")
      U.map(self.buf, "q", function() self:close() end, "close sidebar")
      U.map(self.buf, "<CR>", function()
        local row = selected()
        if not row then return end
        if row.type == "workspace" then self.collapsed[row.id] = not self.collapsed[row.id]; save_layout(); self:render()
        else U.action(ctx, "focus", row.id) end
      end, "focus terminal / expand workspace")
      for key, collapse in pairs({ h = true, l = false }) do
        local value = collapse
        U.map(self.buf, key, function()
          local row = selected()
          local a = row and ctx.store:get_agent(row.id)
          local id = row and (row.type == "workspace" and row.id or a and a.workspace_id)
          if id then self.collapsed[id] = value; save_layout(); self:render() end
        end, collapse and "collapse" or "expand")
      end
      for key, action in pairs({ o = "checkout", p = "compose", a = "ack", L = "label", P = "preview" }) do
        local act = action
        U.map(self.buf, key, function() local row = selected(); if row then U.action(ctx, act, row.id) end end, act)
      end
      U.map(self.buf, "i", function() U.action(ctx, "inbox") end, "attention inbox")
      U.map(self.buf, "f", function() U.action(ctx, "agents") end, "find agents")
      U.map(self.buf, "/", function() U.action(ctx, "agents") end, "search agents")
      U.map(self.buf, "r", function() U.action(ctx, "refresh") end, "refresh")
      U.map(self.buf, "b", function() U.action(ctx, "back") end, "previous workspace tab")
      U.map(self.buf, "?", function()
        vim.notify("Herde sidebar: Enter focus/expand · h/l collapse/expand · P preview · p compose · o checkout · b back · L label · a acknowledge · i inbox · f find · r refresh · q close", vim.log.levels.INFO)
      end, "help")
      vim.api.nvim_create_autocmd("CursorMoved", { group = group, buffer = self.buf, callback = function()
        if self.rendering then return end
        local row = selected()
        if row and row.type == "agent" and ctx.store.selected_id ~= row.id then
          -- The cursor move itself selected this row; don't snap to its title.
          self.last_selected = row.id
          U.action(ctx, "select", row.id)
        end
      end })
    end
    vim.api.nvim_win_set_buf(self.win, self.buf)
    U.window(self.win)
    self:render()
    if U.valid(original) then vim.api.nvim_set_current_win(original) end
  end
  function self:toggle() if self:is_open() then self:close() else self:open() end end
  function self:focus() self:open(); vim.api.nvim_set_current_win(self.win) end
  function self:stop() self.enabled = false; save_layout(); if self.unsubscribe then self.unsubscribe() end; U.delete(self); pcall(vim.api.nvim_del_augroup_by_id, group) end
  vim.api.nvim_create_autocmd("TabEnter", { group = group, callback = function()
    if self.enabled then self:open() end
  end })
  self.unsubscribe = ctx.store:subscribe(function() self:render() end)
  return self
end
return M
