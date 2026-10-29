-- Contract checks against the documented fzf_exec/custom previewer interface.
-- The real fzf binary checks candidate filtering; fzf-lua itself is stubbed.
local old_fzf = package.loaded["fzf-lua"]
local old_base = package.loaded["fzf-lua.previewer.builtin"]
local entries, options, preview, selected
local requests, actions = {}, {}
local Base = {}
function Base:extend()
  local class = { super = self }
  class.__index = class
  return setmetatable(class, { __index = self })
end
function Base:new(_, opts) self.opts, self.winopts = opts, {} end
function Base:get_tmp_buffer() return vim.api.nvim_create_buf(false, true) end
function Base:set_preview_buf(buf) self.preview_bufnr = buf end
function Base:close() if self.preview_bufnr then pcall(vim.api.nvim_buf_delete, self.preview_bufnr, { force = true }) end end
package.loaded["fzf-lua.previewer.builtin"] = { base = Base }
package.loaded["fzf-lua"] = { fzf_exec = function(e, o) entries, options = e, o end }
local store = require("herde.core.store").new()
local agents = {
  { id = "a:1", name = "same", kind = "pi", state = "working", workspace_id = "w" },
  { id = "a:2", name = "same", kind = "codex", state = "blocked", workspace_id = "w" },
}
store:update({ workspaces = { { id = "w", name = "project", path = "/tmp" } }, agents = agents })
local ctx = {
  alive = true, store = store, config = require("herde.config").resolve({ backend = "demo", picker = "fzf-lua" }),
  backend = { capabilities = { read = true }, read = function(_, agent, cb) requests[#requests + 1] = { agent = agent, cb = cb } end },
  workspaces = { label = function() return "task\tlabel\nextra" end },
  actions = { select = function(id) actions[#actions + 1] = "select:" .. id end,
    focus = function(id) actions[#actions + 1] = "focus:" .. id end },
}
local handle
local ok, err = xpcall(function()
  local fzf = require("herde.integrations.fzf")
  handle = fzf.select(agents, { agents = true, format_item = function() return "same\t$(literal)\nnext" end }, function(item) selected = item end, ctx)
  assert(#entries == 2 and entries[1]:match("^1\t") and not entries[1]:find("\n"))
  assert(select(2, entries[1]:gsub("\t", "")) == 1, "only the private token may introduce a field")
  assert(options.fzf_colors == true, "fzf must derive colors from Neovim")
  assert(options.hls.border == "HerdeBorder")
  options.actions.default({ entries[2] })
  assert(vim.wait(200, function() return selected ~= nil end) and selected.id == "a:2", "duplicate names must resolve by token")
  options.actions["alt-enter"]({ entries[1] })
  assert(vim.wait(200, function() return #actions == 2 end))
  assert(actions[1] == "select:a:1" and actions[2] == "focus:a:1")
  options.actions.default({ "999\tmissing" })
  vim.wait(10)
  assert(selected.id == "a:2")

  preview = setmetatable({}, options.previewer)
  preview:new({}, options)
  preview.win = { validate_preview = function() return true end, update_preview_scrollbar = function() end }
  preview:populate_preview_buf(entries[1])
  preview:populate_preview_buf(entries[2])
  assert(#requests == 1, "preview reads must coalesce")
  requests[1].cb(nil, "wrong agent output")
  assert(vim.wait(200, function() return #requests == 2 end))
  assert(requests[2].agent.id == "a:2")
  requests[2].cb(nil, "correct output")
  assert(vim.wait(200, function() return table.concat(vim.api.nvim_buf_get_lines(preview.preview_bufnr, 0, -1, false), "\n"):find("correct output") ~= nil end))
  local body = table.concat(vim.api.nvim_buf_get_lines(preview.preview_bufnr, 0, -1, false), "\n")
  assert(not body:find("wrong agent"))
  preview:populate_preview_buf(entries[1])
  preview:close()
  requests[3].cb(nil, "late after close")
  vim.wait(20)

  -- Verify --with-nth filtering semantics with the installed fzf executable.
  if vim.fn.executable("fzf") == 1 then
    local filtered = vim.system({ "fzf", "--delimiter=\t", "--with-nth=2..", "--nth=1..", "--filter=literal" },
      { stdin = table.concat(entries, "\n"), text = true }):wait()
    assert(filtered.code == 0 and filtered.stdout:find("1\t"), "filtering must return the original identity token")
  end

  local pick = require("herde.ui.picker").new(vim.tbl_extend("force", ctx, {
    attention = { list = function() return { { id = "e", agent_id = "a:2", workspace_id = "w", kind = "blocked" } } end },
  }))
  pick:attention()
  assert(options.winopts.title:find("attention") and entries[1]:find("Needs input"))
  pick:workspaces()
  assert(#entries == 2 and entries[1]:find("All workspaces"))
  pick:stop()
end, debug.traceback)
if handle then handle.close() end
if preview then pcall(preview.close, preview) end
package.loaded["fzf-lua"], package.loaded["fzf-lua.previewer.builtin"] = old_fzf, old_base
assert(ok, err)
print("fzf picker contracts passed")
