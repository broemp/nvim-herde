local M = {}
function M.setup()
  local groups = {
    HerdeTitle = "Title", HerdeWorkspace = "Directory", HerdeWorking = "DiagnosticInfo",
    HerdeBlocked = "DiagnosticWarn", HerdeDone = "DiagnosticOk", HerdeIdle = "Comment",
    HerdeUnknown = "Comment", HerdeMuted = "Comment", HerdeError = "DiagnosticError",
    HerdeNormal = "NormalFloat", HerdeBorder = "FloatBorder", HerdeSeparator = "WinSeparator",
    HerdeHint = "NonText", HerdeLabel = "NormalFloat", HerdeSelected = "CursorLine",
    HerdeAccent = "Special", HerdeTab = "TabLineSel",
  }
  for name, link in pairs(groups) do
    vim.api.nvim_set_hl(0, name, { default = true, link = link })
  end
end
return M
