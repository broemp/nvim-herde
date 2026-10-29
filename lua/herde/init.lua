local M = {}
local current
local function message(err)
  if type(err) == "table" then return err.message or vim.inspect(err) end
  return tostring(err)
end
local function warn(err)
  if err then vim.notify(message(err), vim.log.levels.WARN, { title = "Herde" }) end
end
local function ensure()
  if not current then M.setup() end
  return current
end

function M.setup(opts)
  local config = require("herde.config").resolve(opts)
  if vim.fn.has("nvim-0.10") ~= 1 then error("herde requires Neovim 0.10+") end
  M.teardown()
  local ctx = { config = config, actions = {}, alive = true }
  -- Construct and validate the backend before acquiring the metadata lock.
  ctx.backend = require("herde.backends").create(config)
  ctx.store = require("herde.core.store").new()
  ctx.persistence = require("herde.core.persistence").new(config)
  local attention_opts = vim.tbl_extend("force", config, { namespace = ctx.backend.namespace })
  ctx.attention = require("herde.core.attention").new(attention_opts, ctx.persistence.data.events)
  ctx.workspaces = require("herde.core.workspaces").new(ctx.store, ctx.persistence)
  ctx.navigation = require("herde.core.navigation").new(ctx.store, ctx.backend, ctx.attention)
  local a = ctx.actions
  a.select = function(id)
    local agent, err = ctx.navigation:select(id)
    if err then warn(err) elseif ctx.preview:is_open() then ctx.preview:open(agent.id) end
  end
  a.focus = function(id)
    ctx.navigation:focus(id, function(err)
      if err then warn(err); return end
      ctx.preview:close(true)
      local agent = ctx.store:get_agent(id)
      local text = "Focused " .. (agent and agent.name or "agent") .. " in Herdr"
      if vim.env.HERDR_ENV ~= "1" then text = text .. "\nUse the Herdr window to interact with the agent." end
      vim.notify(text, vim.log.levels.INFO, { title = "Herde" })
    end)
  end
  a.workspace = function(id)
    id = id or nil -- The picker uses false for its all-workspaces entry.
    if id and not ctx.store:get_workspace(id) then warn("Workspace is no longer available"); return end
    local old_agent = ctx.store:get_agent()
    local old_id = ctx.store.workspace_id or (old_agent and old_agent.workspace_id)
    if old_id then
      local previous = { preview_visible = ctx.preview:is_open() }
      if old_agent and old_agent.workspace_id == old_id then previous.selected_id = old_agent.id end
      if ctx.sidebar:is_open() then previous.width = vim.api.nvim_win_get_width(ctx.sidebar.win) end
      ctx.workspaces:layout(old_id, previous)
    end
    if ctx.preview:is_open() then ctx.preview:close(true) end
    ctx.store.workspace_id = id
    ctx.store.workspace_filter = id
    local layout = ctx.workspaces:layout(id) or {}
    ctx.store.selected_id = nil
    local restored = layout.selected_id and ctx.store:get_agent(layout.selected_id)
    if restored and (not id or restored.workspace_id == id) then
      ctx.store.selected_id = layout.selected_id
    else
      for _, agent in ipairs(ctx.store.snapshot.agents) do
        if not id or agent.workspace_id == id then ctx.store.selected_id = agent.id; break end
      end
    end
    ctx.store:emit()
    if ctx.sidebar:is_open() and type(layout.width) == "number" and layout.width >= 12 then
      pcall(vim.api.nvim_win_set_width, ctx.sidebar.win, math.min(layout.width, math.max(12, vim.o.columns - 20)))
    end
    if layout.preview_visible and ctx.store.selected_id then ctx.preview:open(ctx.store.selected_id)
    end
  end
  a.checkout = function(id)
    local agent = ctx.store:get_agent(id)
    local workspace = ctx.store:get_workspace(agent and agent.workspace_id or id or ctx.store.workspace_id)
    if not workspace then warn("Select a workspace first"); return end
    workspace = vim.deepcopy(workspace)
    if not workspace.path and agent and agent.path then workspace.path = agent.path end
    local source = vim.api.nvim_get_current_tabpage()
    require("herde.core.worktrees").open(workspace, config, function(err, tab)
      if err then warn(err); return end
      require("herde.ui.statusline").refresh()
      if tab ~= source then
        ctx.sidebar:render()
        vim.notify("Opened " .. (workspace.name or "workspace") .. "\n<leader>ab back · <leader>aa overview", vim.log.levels.INFO, { title = "Herde" })
      end
    end)
  end
  a.back = function()
    local tab = ctx.previous_tab
    if not tab or not vim.api.nvim_tabpage_is_valid(tab) or tab == vim.api.nvim_get_current_tabpage() then
      warn("No previous workspace tab is available"); return
    end
    vim.api.nvim_set_current_tabpage(tab)
  end
  a.ack = function(id)
    id = id or ctx.store.selected_id
    if id then ctx.attention:ack(id); ctx.store:emit() end
  end
  a.label = function(id)
    id = id or ctx.store.selected_id
    local agent = ctx.store:get_agent(id)
    if not agent then warn("Select an agent first"); return end
    vim.ui.input({ prompt = "Task label: ", default = ctx.workspaces:label(id) or "" }, function(value)
      if value ~= nil and ctx.alive then ctx.workspaces:label(id, value); ctx.store:emit() end
    end)
  end
  a.compose = function(id, context)
    id = id or ctx.store.selected_id
    if not ctx.store:get_agent(id) then warn("Select an agent first"); return end
    ctx.composer:open(id, context)
  end
  a.preview = function(id) ctx.preview:open(id or ctx.store.selected_id) end
  a.inbox = function() ctx.inbox:open() end
  a.agents = function() ctx.picker:agents() end
  a.attention = function() ctx.picker:attention() end
  a.mute = function(id) return ctx.notifications:mute(id or ctx.store.workspace_id) end
  a.toggle = function() ctx.sidebar:toggle() end
  a.refresh = function()
    ctx.refresh:request(function(err)
      if err then warn("Herdr refresh failed: " .. message(err))
      else vim.notify(string.format("Refreshed %d workspaces and %d agents", #ctx.store.snapshot.workspaces, #ctx.store.snapshot.agents), vim.log.levels.INFO, { title = "Herde" }) end
    end)
  end
  a.submit = function(id, text, cb)
    if not ctx.alive then cb("Herde is stopped"); return end
    if not text:match("%S") then cb("Prompt is empty"); return end
    if ctx.submitting then cb("Another prompt submission is pending"); return end
    ctx.submitting = true
    ctx.refresh:request(function(err)
      local function done(e, result)
        ctx.submitting = false
        if ctx.alive then cb(e, result) end
      end
      if err then done("Cannot validate target: " .. message(err)); return end
      local agent = ctx.store:get_agent(id)
      if not agent then done("Agent disappeared or was replaced; select the target again"); return end
      if agent.state == "blocked" then done("Agent needs input in its terminal; focus it to respond"); return end
      if not ctx.backend.capabilities.prompt then done("Backend does not support prompt submission"); return end
      ctx.backend:prompt(agent, text, done)
    end)
  end
  require("herde.ui.highlights").setup()
  for _, name in ipairs({ "sidebar", "inbox", "preview", "composer", "picker" }) do
    ctx[name] = require("herde.ui." .. name).new(ctx)
  end
  ctx.notifications = require("herde.ui.notify").new(ctx)
  ctx.refresh = require("herde.core.refresh").new({
    config = config, store = ctx.store, backend = ctx.backend, attention = ctx.attention,
    visible = function() return ctx.sidebar:is_open() or ctx.inbox:is_open() or ctx.preview:is_open() end,
    notify = function(events) ctx.notifications:deliver(events) end,
  })
  ctx.unsubscribe = ctx.store:subscribe(function()
    ctx.persistence.data.events = ctx.attention:serialize()
    ctx.persistence:save()
    require("herde.ui.statusline").refresh()
  end)
  ctx.augroup = vim.api.nvim_create_augroup("Herde", { clear = true })
  ctx.last_tab = vim.api.nvim_get_current_tabpage()
  vim.api.nvim_create_autocmd("TabEnter", { group = ctx.augroup, callback = function()
    local tab = vim.api.nvim_get_current_tabpage()
    if tab ~= ctx.last_tab then
      if vim.api.nvim_tabpage_is_valid(ctx.last_tab) then ctx.previous_tab = ctx.last_tab end
      ctx.last_tab = tab
      ctx.sidebar:render()
      require("herde.ui.statusline").refresh()
    end
  end })
  vim.api.nvim_create_autocmd("VimLeavePre", { group = ctx.augroup, callback = M.teardown })
  vim.api.nvim_create_autocmd("ColorScheme", { group = ctx.augroup, callback = function() require("herde.ui.highlights").setup() end })
  current = ctx
  M.register_command()
  ctx.refresh:request()
  return M
end

function M.teardown()
  local ctx = current
  current = nil
  if not ctx then return end
  ctx.alive = false
  -- A failed session write or backend stop must not leak the other resources.
  local function cleanup(fn)
    local ok, err = pcall(fn)
    if not ok then warn(err) end
  end
  cleanup(function() require("herde.core.worktrees").save_current(ctx.config) end)
  cleanup(function() ctx.refresh:stop() end)
  cleanup(function() ctx.backend:stop() end)
  if ctx.unsubscribe then ctx.unsubscribe() end
  for _, name in ipairs({ "sidebar", "inbox", "preview", "composer", "picker" }) do cleanup(function() ctx[name]:stop() end) end
  ctx.persistence.data.events = ctx.attention:serialize()
  cleanup(function() ctx.persistence:close() end)
  if ctx.augroup then pcall(vim.api.nvim_del_augroup_by_id, ctx.augroup) end
end

function M.toggle() ensure().sidebar:toggle() end
function M.focus_sidebar() ensure().sidebar:focus() end
function M.agents() ensure().picker:agents() end
function M.workspaces() ensure().picker:workspaces() end
function M.inbox() ensure().inbox:open() end
function M.attention() ensure().picker:attention() end
function M.refresh() ensure().actions.refresh() end
local function navigate(method, ...)
  local ctx = ensure()
  local agent, err = ctx.navigation[method](ctx.navigation, ...)
  if err then warn(err) elseif agent and ctx.preview:is_open() then ctx.preview:open(agent.id) end
end
function M.previous() navigate("previous") end
function M.cycle(delta) navigate("cycle", delta or 1) end
function M.next_attention() navigate("next_attention") end
function M.checkout(id) ensure().actions.checkout(id) end
function M.back() ensure().actions.back() end
function M.label(id) ensure().actions.label(id) end
function M.ack(id) ensure().actions.ack(id) end
function M.focus(id) ensure().actions.focus(id) end
function M.preview(id) ensure().actions.preview(id) end
function M.compose(opts)
  opts = opts or {}
  local context = require("herde.core.context").capture(opts)
  ensure().actions.compose(opts.id, context)
end
function M.quiet() return ensure().notifications:quiet() end
function M.mute() local c = ensure(); return c.notifications:mute(c.store.workspace_id) end
function M.statusline() return current and require("herde.ui.statusline").get(current) or "" end
function M.workspace_statusline() return require("herde.ui.statusline").workspace(current) end
function M.get_context() return current end

local commands = {
  toggle = "toggle", agents = "agents", workspaces = "workspaces", inbox = "inbox", attention = "attention",
  refresh = "refresh", previous = "previous", ["next-attention"] = "next_attention",
  checkout = "checkout", back = "back", label = "label", compose = "compose", quiet = "quiet",
  mute = "mute", focus = "focus", preview = "preview", acknowledge = "ack",
  ["focus-sidebar"] = "focus_sidebar", next = "cycle",
}
function M.register_command()
  vim.api.nvim_create_user_command("Herde", function(args)
    local action = args.fargs[1] or "toggle"
    if commands[action] then M[commands[action]]()
    elseif action == "stop" then M.teardown()
    else warn("Unknown Herde command: " .. action) end
  end, { nargs = "?", force = true, desc = "Agent workspace harness", complete = function(prefix)
    local result = { "stop" }
    for key in pairs(commands) do if key:find(prefix, 1, true) == 1 then table.insert(result, key) end end
    table.sort(result)
    return result
  end })
end
return M
