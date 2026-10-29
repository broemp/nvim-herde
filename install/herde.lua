-- Local LazyVim installation. Herde owns <leader>a; Herdr comments use aR.
local source = debug.getinfo(1, "S").source:sub(2)
local repo = vim.fn.fnamemodify(source, ":p:h:h")
local spec = dofile(repo .. "/examples/lazyvim.lua")
spec.dir = repo
spec.specs = {
  {
    "folke/which-key.nvim",
    optional = true,
    opts = function(_, opts)
      opts.spec = opts.spec or {}
      vim.list_extend(opts.spec, {
        { "<leader>a", group = "agents", mode = { "n", "x" } },
        { "<leader>aR", group = "Herdr comments", mode = { "n", "x" } },
      })
    end,
  },
}
return {
  spec,
  { "coder/claudecode.nvim", enabled = false },
  -- Keep Herdr's comment/reference functionality without overlapping Herde.
  { "ChmaraX/herdr-nvim", opts = { prefix = "<leader>aR" } },
}
