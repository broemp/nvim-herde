-- Optional integration check: put an installed lazy.nvim on runtimepath first.
local root, state = vim.fn.getcwd(), vim.fn.tempname()
vim.go.loadplugins = true -- -u NONE disables plugin loading.
local installation = dofile(root .. "/install/herde.lua")
local spec = installation[1]
spec.dir = root
-- Optional installed lualine enables a full statusline spec-merging check.
local lualine_path = vim.api.nvim_get_runtime_file("lua/lualine.lua", false)[1]
if not lualine_path then spec.dependencies = {} end
spec.opts = { backend = "demo", state_dir = state, notifications = { enabled = false } }
vim.fn.mkdir(state .. "/legacy", "p")
vim.fn.mkdir(state .. "/claude", "p")
local specs = {
  { "ChmaraX/herdr-nvim", dir = state .. "/legacy", lazy = true, opts = {} },
  { "coder/claudecode.nvim", dir = state .. "/claude", lazy = true, keys = { "<leader>aa" } },
}
vim.list_extend(specs, installation)
if lualine_path then
  table.insert(specs, 1, {
    "nvim-lualine/lualine.nvim", dir = vim.fn.fnamemodify(lualine_path, ":h:h"), lazy = true,
    opts = { options = { theme = "auto", icons_enabled = false }, sections = { lualine_b = { "branch" } } },
  })
  -- Mirrors the existing user override applied after Herde's spec.
  specs[#specs + 1] = { "nvim-lualine/lualine.nvim", opts = function(_, opts)
    opts.sections.lualine_c = { { "filename", path = 1 } }
  end }
end
require("lazy").setup(specs, {
  root = state .. "/plugins",
  lockfile = state .. "/lazy-lock.json",
  state = state .. "/lazy-state.json",
  readme = { enabled = false },
  checker = { enabled = false },
  change_detection = { enabled = false },
  install = { missing = false },
  performance = { rtp = { reset = false }, cache = { enabled = false } },
})
assert(package.loaded.herde == nil, "spec must lazy load")
local plugins = require("lazy.core.config").plugins
assert(not plugins["claudecode.nvim"], "Claude Code must be excluded from the active specs")
local legacy = require("lazy.core.plugin").values(plugins["herdr-nvim"], "opts", false)
assert(legacy.prefix == "<leader>aR", "legacy prefix must survive spec merging")
vim.cmd("Herde toggle")
local ctx = assert(require("herde").get_context(), "command must run setup through lazy")
assert(vim.wait(2000, function() return #ctx.store.snapshot.agents > 0 end))
assert(ctx.sidebar:is_open())
if lualine_path then
  local config = require("lazy.core.plugin").values(plugins["lualine.nvim"], "opts", false)
  assert(config.sections.lualine_b[1] == "branch" and #config.sections.lualine_b == 2)
  assert(config.sections.lualine_c[1][1] == "filename")
  local rendered = vim.api.nvim_eval_statusline(require("lualine").statusline(true), {})
  assert(rendered.str:find("Workspace:", 1, true), "installed dependency spec must actually render the workspace field")
end
assert(vim.fn.maparg("<leader>aa", "n") ~= "", "example mappings must load")
require("herde").teardown()
vim.fn.delete(state, "rf")
print("lazy.nvim installation and keymap merging passed")
vim.cmd("qa!")
