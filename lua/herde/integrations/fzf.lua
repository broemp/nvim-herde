local U = require("herde.ui.util")
local M = {}

function M.available()
  local ok, fzf = pcall(require, "fzf-lua")
  return ok and type(fzf.fzf_exec) == "function" and vim.fn.executable("fzf") == 1
end

-- Index tokens are private to one picker. Display names are never action targets.
function M.select(items, opts, callback, ctx)
  local fzf = require("fzf-lua")
  local entries, by_index = {}, {}
  for i, item in ipairs(items) do
    entries[i] = tostring(i) .. "\t" .. U.text(opts.format_item(item))
    by_index[i] = item
  end
  local function resolve(entry)
    local index = type(entry) == "string" and tonumber(entry:match("^(%d+)\t"))
    return index and by_index[index] or nil
  end
  local function agent_for(item)
    return item and (opts.agents and item or item.agent_id and ctx.store:get_agent(item.agent_id))
  end
  local alive, picker_buf, picker_win = true
  local base = require("fzf-lua.previewer.builtin").base
  local Preview = base:extend()
  function Preview:new(o, options, win)
    Preview.super.new(self, o, options, win)
    setmetatable(self, Preview)
    self.sequence, self.pending, self.busy = 0, nil, false
    return self
  end
  function Preview:gen_winopts()
    return vim.tbl_extend("force", self.winopts or {}, { wrap = false, number = false, relativenumber = false, signcolumn = "no" })
  end
  local function valid(self, req)
    return alive and ctx.alive ~= false and req.sequence == self.sequence and vim.api.nvim_buf_is_valid(req.buf)
      and self.win and self.win:validate_preview()
  end
  local function pump(self)
    if self.busy or not self.pending or not alive then return end
    local req = self.pending
    self.pending, self.busy = nil, true
    ctx.backend:read(req.agent, function(err, output)
      vim.schedule(function()
        self.busy = false
        if valid(self, req) then
          local body = err and ("Preview unavailable: " .. U.error(err)) or tostring(output or "")
          body = body:sub(-ctx.config.preview.max_bytes)
          local lines = vim.split(U.clean(body), "\n", { plain = true })
          if #lines > ctx.config.preview.lines then lines = vim.list_slice(lines, #lines - ctx.config.preview.lines + 1) end
          U.lines(req.buf, vim.list_extend(vim.deepcopy(req.header), lines))
          U.paint(req.buf, { { 0, "HerdeTitle" }, { 1, "HerdeMuted" } })
          self.win:update_preview_scrollbar()
        end
        pump(self)
      end)
    end)
  end
  function Preview:populate_preview_buf(entry)
    self.sequence = self.sequence + 1
    self.pending = nil
    local item = resolve(entry)
    if not item then return end
    local buf = self:get_tmp_buffer()
    vim.bo[buf].modeline = false
    local agent = agent_for(item)
    local header
    if agent then
      local ws = ctx.store:get_workspace(agent.workspace_id)
      header = { U.text(agent.name or agent.id),
        U.text(ws and ws.name or "workspace") .. " · " .. U.text(agent.kind) .. " · " .. (U.states[agent.state] or "Unknown"),
        U.text(U.label(ctx, agent) or ""), "Terminal snapshot · read-only", "" }
    else
      header = { U.text(item.name or "Agent unavailable"), U.path(item.path or ""), "" }
      if item.agent_id then header[2] = "This agent is no longer available." end
    end
    U.lines(buf, vim.list_extend(vim.deepcopy(header), agent and { "Loading recent output…" } or {}))
    self:set_preview_buf(buf, true)
    U.paint(buf, { { 0, "HerdeTitle" }, { 1, "HerdeMuted" } })
    if agent then
      if ctx.backend.capabilities and ctx.backend.capabilities.read == false then
        U.lines(buf, vim.list_extend(header, { "Backend does not support previews." }))
      else
        self.pending = { agent = agent, sequence = self.sequence, buf = buf, header = header }
        pump(self)
      end
    elseif not item.agent_id then
      local lines = vim.deepcopy(header)
      for _, a in ipairs(ctx.store.snapshot.agents) do
        if not item.id or a.workspace_id == item.id then
          lines[#lines + 1] = U.text(a.name or a.id) .. " · " .. (U.states[a.state] or "Unknown")
        end
      end
      U.lines(buf, lines)
    end
  end
  function Preview:close(...)
    self.sequence, self.pending = self.sequence + 1, nil
    return Preview.super.close(self, ...)
  end
  local function choose(action)
    return function(selected)
      local item = selected and resolve(selected[1])
      if not item then return end
      -- fzf-lua closes its terminal before running normal action handlers.
      vim.schedule(function()
        if ctx.alive == false then return end
        if action then
          local agent = agent_for(item)
          if agent then
            U.action(ctx, "select", agent.id)
            U.action(ctx, action, agent.id)
          elseif action == "checkout" and item.id and not item.agent_id then U.action(ctx, action, item.id) end
        else callback(item) end
      end)
    end
  end
  local settings = vim.tbl_deep_extend("force", {
    prompt = "Search › ",
    fzf_colors = true,
    winopts = {
      title = " herde / " .. (opts.title or "agents") .. " ",
      title_pos = "left", border = (ctx.config.ui or {}).border or "rounded",
      width = 0.88, height = 0.78,
      preview = { layout = "flex", flip_columns = 100, horizontal = "right:52%", vertical = "down:48%" },
    },
    hls = { normal = "HerdeNormal", border = "HerdeBorder", title = "HerdeTitle",
      preview_normal = "HerdeNormal", preview_border = "HerdeBorder", preview_title = "HerdeTitle" },
  }, ctx.config.fzf or {})
  -- Keep identity parsing and actions invariant even when appearance is customized.
  settings.previewer = Preview
  settings.fzf_opts = vim.tbl_extend("force", settings.fzf_opts or {}, {
    ["--delimiter"] = "\t", ["--with-nth"] = "2..", ["--nth"] = "1..", ["--accept-nth"] = false, ["--no-multi"] = true,
    ["--header"] = opts.title == "workspaces" and "enter filter workspace · ctrl-o checkout"
      or (opts.agents and "enter focus · alt-o snapshot · ctrl-o checkout · ctrl-p prompt" or "enter preview · alt-enter focus · ctrl-o checkout · ctrl-p prompt"),
  })
  settings.actions = {
    ["default"] = choose(), ["alt-enter"] = choose("focus"),
    ["ctrl-o"] = choose("checkout"), ["ctrl-p"] = choose("compose"), ["ctrl-a"] = choose("ack"),
    ["alt-o"] = choose("preview"),
  }
  local on_create = settings.winopts.on_create
  settings.winopts.on_create = function(...)
    picker_win, picker_buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
    if on_create then on_create(...) end
  end
  fzf.fzf_exec(entries, settings)
  return { close = function()
    alive = false
    if U.valid(picker_win) and vim.api.nvim_win_get_buf(picker_win) == picker_buf then
      pcall(vim.api.nvim_win_close, picker_win, true)
    end
  end }
end
return M
