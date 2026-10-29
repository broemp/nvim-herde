local root = vim.fn.getcwd()
vim.opt.rtp:prepend(root)
local files = vim.fn.glob("tests/core/*.lua", false, true)
vim.list_extend(files, vim.fn.glob("tests/backends/*.lua", false, true))
vim.list_extend(files, { "tests/refresh.lua", "tests/smoke.lua", "tests/ui.lua", "tests/integration.lua", "tests/fzf.lua", "tests/theme.lua", "tests/keymaps.lua", "tests/sidebar.lua", "tests/workspace-ui.lua", "tests/statusline.lua" })
local failures = 0
for _, file in ipairs(files) do
  vim.cmd("cd " .. vim.fn.fnameescape(root))
  local ok, err = xpcall(function() dofile(root .. "/" .. file) end, debug.traceback)
  if ok then print("PASS " .. file) else failures = failures + 1; print("FAIL " .. file .. "\n" .. err) end
end
pcall(function() require("herde").teardown() end)
if failures > 0 then vim.cmd("cquit " .. failures) else vim.cmd("qa!") end
