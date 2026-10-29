local U = require("herde.ui.util")
local M = {}
function M.new(ctx)
  local self = { drafts = {}, busy = false }
  local group = vim.api.nvim_create_augroup("HerdeComposer" .. tostring(self):gsub("[^%w]", ""), { clear = true })
  function self:save()
    if self.agent_id and self.buf and vim.api.nvim_buf_is_valid(self.buf) then
      self.drafts[self.agent_id] = table.concat(vim.api.nvim_buf_get_lines(self.buf, 0, -1, false), "\n")
    end
  end
  function self:close() self:save(); U.delete(self) end
  function self:send()
    if self.busy or not self.agent_id then return end
    self:save()
    local id, text = self.agent_id, self.drafts[self.agent_id]
    if not text or text:match("^%s*$") then vim.notify("Write a prompt before submitting.", vim.log.levels.WARN); return end
    if not ctx.actions.submit then vim.notify("Prompt submission is unavailable.", vim.log.levels.WARN); return end
    self.busy = true
    ctx.actions.submit(id, text, function(err)
      self.busy = false
      if err then vim.notify("Prompt not confirmed; draft retained. " .. U.error(err), vim.log.levels.ERROR, { title = "Herde" }); return end
      if self.agent_id == id and self.buf and vim.api.nvim_buf_is_valid(self.buf) then
        local current = table.concat(vim.api.nvim_buf_get_lines(self.buf, 0, -1, false), "\n")
        if current == text then
          self.drafts[id] = nil
          self.discard = true
          U.delete(self)
          self.discard = false
        end
      elseif self.drafts[id] == text then self.drafts[id] = nil end
      vim.notify("Prompt submitted.", vim.log.levels.INFO, { title = "Herde" })
    end)
  end
  function self:open(id, context)
    id = id or ctx.store.selected_id
    local agent = ctx.store:get_agent(id)
    if not agent then vim.notify("Select a live agent first.", vim.log.levels.WARN); return end
    self:close()
    self.agent_id = id
    local ws = ctx.store:get_workspace(agent.workspace_id)
    self.buf = U.buf("compose", true)
    local text = self.drafts[id] or ""
    if context and context ~= "" then text = text .. (text ~= "" and "\n\n" or "") .. tostring(context) end
    U.lines(self.buf, vim.split(text, "\n", { plain = true }))
    local ui = vim.tbl_extend("force", ctx.config.ui or {}, { footer = "Ctrl-S send   q close & keep draft" })
    self.win = U.float(self.buf, "Prompt · " .. U.text(ws and ws.name or "workspace") .. " / " .. U.text(agent.name or agent.id), 94, 22, true, ui)
    vim.api.nvim_create_autocmd("WinClosed", { group = group, pattern = tostring(self.win), once = true, callback = function()
      if not self.discard then self:save() end
    end })
    vim.wo[self.win].wrap = true
    vim.bo[self.buf].filetype = "markdown"
    vim.api.nvim_win_set_cursor(self.win, { 1, 0 })
    U.map(self.buf, "q", function() self:close() end, "save draft and close")
    U.map(self.buf, "<C-s>", function() self:send() end, "submit exact prompt")
    vim.keymap.set("i", "<C-s>", function() vim.cmd("stopinsert"); self:send() end, { buffer = self.buf, silent = true })
    vim.keymap.set("i", "<C-q>", function() vim.cmd("stopinsert"); self:close() end, { buffer = self.buf, silent = true })
  end
  function self:stop() self:close(); self.drafts = {}; pcall(vim.api.nvim_del_augroup_by_id, group) end
  function self:is_open() return U.valid(self.win) or false end
  return self
end
return M
