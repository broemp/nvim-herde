local U = require("herde.ui.util")
local M = {}
function M.new(ctx)
  local self = { generation = 0, follow = ctx.config.preview.follow or false }
  local group = vim.api.nvim_create_augroup("HerdePreview" .. tostring(self):gsub("[^%w]", ""), { clear = true })
  function self:is_open() return U.valid(self.win) or false end
  function self:refresh()
    if not self:is_open() then return end
    local agent = ctx.store:get_agent(self.agent_id)
    if self.request then self.pending = true; return end
    self.generation = self.generation + 1
    local generation = self.generation
    if not agent then U.lines(self.buf, { "Agent unavailable." }); return end
    if ctx.backend.capabilities and ctx.backend.capabilities.read == false then U.lines(self.buf, { "Backend does not support output previews." }); return end
    if not self.loaded then U.lines(self.buf, { "Loading recent output..." }) end
    local request = {}
    self.request = request
    ctx.backend:read(agent, function(err, output)
      if self.request ~= request then return end
      self.request = nil
      local pending = self.pending
      self.pending = false
      if generation ~= self.generation or not self:is_open() then
        if pending and self:is_open() then self:refresh() end
        return
      end
      local lines
      if err then lines = { "Preview unavailable: " .. U.error(err) }
      else
        if type(output) == "table" then output = output.text or output.output or table.concat(output, "\n") end
        output = tostring(output or "")
        local max_bytes = ctx.config.preview.max_bytes
        if #output > max_bytes then output = "[older output truncated]\n" .. output:sub(-max_bytes) end
        lines = vim.split(U.clean(output), "\n", { plain = true })
        while #lines > ctx.config.preview.lines do table.remove(lines, 1) end
        if #lines == 0 then lines = { "No recent output available." } end
      end
      table.insert(lines, 1, "Snapshot · " .. U.text(agent.name or agent.id) .. " · " .. (U.states[agent.state] or "Unknown") .. (ctx.store.stale and " · stale" or ""))
      table.insert(lines, 2, "Read-only · r refresh   f follow " .. (self.follow and "on" or "off") .. "   ↵ focus   q close")
      table.insert(lines, 3, "")
      U.lines(self.buf, lines)
      U.paint(self.buf, { { 0, "HerdeTitle" }, { 1, "HerdeHint" } })
      self.loaded = true
      if self.follow and U.valid(self.win) then pcall(vim.api.nvim_win_set_cursor, self.win, { #lines, 0 }) end
      if pending then self:refresh() end
    end)
  end
  function self:open(id)
    local changed = self.agent_id ~= id
    if changed then self.generation = self.generation + 1 end
    self.agent_id = id or ctx.store.selected_id
    self.loaded = self.loaded and not changed
    if not self:is_open() then
      self.buf = U.buf("preview")
      local original = vim.api.nvim_get_current_win()
      if vim.o.columns < 90 or vim.o.lines < 28 then
        self.win = U.float(self.buf, " herde / output ", 84, ctx.config.preview.height, false, ctx.config.ui)
      else
        vim.cmd("botright " .. math.max(3, ctx.config.preview.height) .. "split")
        self.win = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_buf(self.win, self.buf)
        U.window(self.win)
        if U.valid(original) then vim.api.nvim_set_current_win(original) end
      end
      local win = self.win
      vim.api.nvim_create_autocmd("WinClosed", { group = group, pattern = tostring(win), once = true, callback = function()
        if self.win == win then self:close() end
      end })
      U.map(self.buf, "q", function() self:close() end, "close preview")
      U.map(self.buf, "r", function() self:refresh() end, "refresh output")
      U.map(self.buf, "f", function() self:toggle_follow() end, "toggle follow")
      U.map(self.buf, "<CR>", function() U.action(ctx, "focus", self.agent_id) end, "focus terminal")
      U.map(self.buf, "p", function() U.action(ctx, "compose", self.agent_id) end, "compose")
      self.timer = (vim.uv or vim.loop).new_timer()
      self.timer:start(ctx.config.poll.visible, ctx.config.poll.visible, vim.schedule_wrap(function()
        if self.follow and self:is_open() then self:refresh() end
      end))
    end
    local agent = ctx.store:get_agent(self.agent_id)
    if agent and ctx.workspaces then
      local layout = ctx.workspaces:layout(agent.workspace_id) or {}; layout.preview_visible = true; ctx.workspaces:layout(agent.workspace_id, layout)
    end
    self:refresh()
  end
  function self:toggle_follow() self.follow = not self.follow; self:refresh() end
  function self:close(preserve_layout)
    local agent = ctx.store:get_agent(self.agent_id)
    if not preserve_layout and agent and ctx.workspaces then
      local layout = ctx.workspaces:layout(agent.workspace_id) or {}; layout.preview_visible = false; ctx.workspaces:layout(agent.workspace_id, layout)
    end
    self.request = nil
    self.pending = false
    self.generation = self.generation + 1
    if self.timer then self.timer:stop(); self.timer:close(); self.timer = nil end
    U.delete(self)
    self.loaded = false
  end
  function self:focus() if self:is_open() then vim.api.nvim_set_current_win(self.win) end end
  function self:stop() self:close(true); pcall(vim.api.nvim_del_augroup_by_id, group) end
  return self
end
return M
