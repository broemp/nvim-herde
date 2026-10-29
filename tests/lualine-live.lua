-- Optional: put installed lualine.nvim on runtimepath first.
vim.opt.rtp:prepend(vim.fn.getcwd())
local opts = {
  options = { theme = "auto", icons_enabled = false, globalstatus = true },
  sections = { lualine_b = { "branch" }, lualine_c = { { "filename", path = 1 } } },
}
local spec = dofile("examples/lazyvim.lua")
spec.dependencies[1].opts(nil, opts)
local lualine = require("lualine")
lualine.setup(opts)
local rendered = vim.api.nvim_eval_statusline(lualine.statusline(true), {})
assert(rendered.str:find("Workspace:", 1, true), "workspace field must render in real lualine")
local h = require("herde")
local state = vim.fn.tempname()
h.setup({ backend = "demo", state_dir = state, notifications = { enabled = false } })
assert(vim.wait(1000, function() return h.get_context().store.has_snapshot end))
local source = vim.api.nvim_get_current_tabpage()
h.checkout("demo/main")
local target = vim.api.nvim_get_current_tabpage()
rendered = vim.api.nvim_eval_statusline(lualine.statusline(true), {})
assert(rendered.str:find("Workspace: Current project", 1, true), "real lualine must show the opened checkout label")
h.back()
assert(vim.api.nvim_get_current_tabpage() == source)
assert(h.workspace_statusline():find("Workspace:", 1, true))
h.teardown()
if vim.api.nvim_tabpage_is_valid(target) then vim.api.nvim_set_current_tabpage(target); vim.cmd("tabclose") end
vim.fn.delete(state, "rf")
print("Real lualine workspace field passed")
vim.cmd("qa!")
