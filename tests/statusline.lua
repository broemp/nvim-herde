local S = require("herde.ui.statusline")
local repo = vim.fn.getcwd()
local root = vim.fn.tempname()
for _, dir in ipairs({ "/one/sub", "/two", "/outside" }) do vim.fn.mkdir(root .. dir, "p") end
local source = vim.api.nvim_get_current_tabpage()
vim.cmd("tabnew")
local store = require("herde.core.store").new()
store:update({
  workspaces = { { id = "one", name = "Booking", path = root .. "/one" }, { id = "two", name = "Design", path = root .. "/two" } },
  agents = { { id = "designer", workspace_id = "two", name = "designer", state = "idle" } },
})
local ctx = { store = store }
local ok, err = xpcall(function()
  vim.cmd("tcd " .. vim.fn.fnameescape(root .. "/one/sub"))
  store:select("designer")
  assert(S.workspace(ctx) == "Workspace: Booking", "a selected agent must not replace the editor's actual workspace")
  vim.t.herde_workspace_id, vim.t.herde_workspace_name = "two", "Saved Design"
  assert(S.workspace(ctx) == "Workspace: Design", "an explicit checkout must identify its own tab")
  store.snapshot.workspaces = {}
  store.stale = true
  assert(S.workspace(ctx) == "Workspace: Saved Design", "workspace label must survive backend disconnection")
  vim.t.herde_workspace_id, vim.t.herde_workspace_name = nil, nil
  vim.cmd("tcd " .. vim.fn.fnameescape(root .. "/outside"))
  assert(S.workspace(nil) == "Workspace: outside", "untracked tabs should show their project directory")
  vim.t.herde_workspace_id, vim.t.herde_workspace_name = "two", "60% ready"
  local evaluated = vim.api.nvim_eval_statusline(S.workspace(ctx), {})
  assert(evaluated.str == "Workspace: 60% ready", "workspace text must not be interpreted as statusline codes")

  local spec = dofile(repo .. "/examples/lazyvim.lua")
  local opts = { sections = { lualine_b = { "branch" }, lualine_c = { { "filename", path = 1 } } } }
  local configure = spec.dependencies[1].opts
  configure(nil, opts)
  configure(nil, opts)
  assert(#opts.sections.lualine_b == 2 and opts.sections.lualine_b[1] == "branch", "workspace field must append once without replacing branch")
  assert(opts.sections.lualine_c[1][1] == "filename", "user filename configuration must remain intact")
  local h = package.loaded.herde
  package.loaded.herde = nil
  local cold = opts.sections.lualine_b[2][1]()
  local loaded = package.loaded.herde
  package.loaded.herde = h
  assert(cold == "Workspace: outside" and loaded == nil, "statusline must not lazy-load the agent backend")
end, debug.traceback)
vim.cmd("tabclose")
vim.api.nvim_set_current_tabpage(source)
vim.fn.delete(root, "rf")
assert(ok, err)
print("Current workspace statusline checks passed")
