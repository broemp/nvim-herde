-- Copy to ~/.config/nvim/lua/plugins/herde.lua for installation from GitHub.
return {
  "broemp/nvim-herde",
  name = "herde.nvim",
  main = "herde",
  cmd = "Herde",
  dependencies = {
    {
      "nvim-lualine/lualine.nvim",
      optional = true, -- Uses LazyVim's existing statusline.
      opts = function(_, opts)
        opts.sections = opts.sections or {}
        opts.sections.lualine_b = opts.sections.lualine_b or {}
        for _, component in ipairs(opts.sections.lualine_b) do
          if type(component) == "table" and component.herde_workspace then return end
        end
        table.insert(opts.sections.lualine_b, {
          function()
            local h = package.loaded.herde
            if h then return h.workspace_statusline() end
            local cwd = vim.fn.getcwd(-1, 0)
            local name = vim.fn.fnamemodify(cwd, ":t")
            return (("Workspace: " .. (name ~= "" and name or cwd)):gsub("[\n\r\t]", " "):gsub("%%", "%%%%"))
          end,
          herde_workspace = true,
        })
      end,
    },
  },
  opts = { backend = "herdr", picker = "snacks" }, -- Uses LazyVim's existing picker.
  keys = {
    { "<leader>aa", function() require("herde").toggle() end, desc = "Agent overview" },
    { "<leader>af", function() require("herde").agents() end, desc = "Find agent" },
    { "<leader>ar", function() require("herde").refresh() end, desc = "Refresh agents" },
    { "<leader>aw", function() require("herde").workspaces() end, desc = "Agent workspaces" },
    { "<leader>ai", function() require("herde").inbox() end, desc = "Agent attention inbox" },
    { "<leader>a/", function() require("herde").attention() end, desc = "Search agent attention" },
    { "<leader>an", function() require("herde").next_attention() end, desc = "Next agent needing attention" },
    { "<leader>ap", function() require("herde").previous() end, desc = "Previous agent" },
    { "<leader>ao", function() require("herde").checkout() end, desc = "Open agent checkout" },
    { "<leader>ab", function() require("herde").back() end, desc = "Back to previous workspace" },
    { "<leader>al", function() require("herde").label() end, desc = "Agent task label" },
    { "<leader>as", function() require("herde").compose() end, desc = "Compose agent prompt" },
    { "<leader>as", function() require("herde").compose({ selection = true }) end, mode = "x", desc = "Send selection to agent" },
    { "<leader>ad", function() require("herde").compose({ diagnostics = true }) end, desc = "Send diagnostics to agent" },
    { "<leader>aq", function() require("herde").quiet() end, desc = "Quiet agent notifications" },
    { "<leader>aA", function() require("herde").focus_sidebar() end, desc = "Focus agent sidebar" },
  },
}
