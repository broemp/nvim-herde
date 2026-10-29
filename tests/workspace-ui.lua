local herde = require("herde")
local root = vim.fn.tempname()
local source_cwd = vim.fn.getcwd()
for _, path in ipairs({ "/one", "/two", "/state" }) do vim.fn.mkdir(root .. path, "p") end
vim.fn.writefile({ "original" }, root .. "/source.lua")
vim.cmd("edit " .. vim.fn.fnameescape(root .. "/source.lua"))
local source_tab, source_buf = vim.api.nvim_get_current_tabpage(), vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, { "unsaved source" })
local inventory = {
  namespace = "workspace-test",
  workspaces = { { id = "one", name = "First workspace", path = root .. "/one" }, { id = "two", name = "Second workspace", path = root .. "/two" } },
  agents = { { id = "builder", name = "builder", kind = "pi", state = "idle", workspace_id = "one" } },
}
local backend = {
  namespace = "workspace-test", capabilities = { read = false, focus = false, prompt = false },
  snapshot = function(_, cb) cb(nil, vim.deepcopy(inventory)) end,
  read = function(_, _, cb) cb(nil, "") end,
  focus = function(_, _, cb) cb("unsupported") end,
  prompt = function(_, _, _, cb) cb("unsupported") end,
  stop = function() end,
}
local original_notify, notices = vim.notify, {}
vim.notify = function(msg) notices[#notices + 1] = msg end
local created = {}
local ok, err = xpcall(function()
  herde.setup({ backend = backend, state_dir = root .. "/state", picker = "native", notifications = { enabled = false } })
  local ctx = herde.get_context()
  assert(vim.wait(1000, function() return ctx.store.has_snapshot end))
  herde.focus_sidebar()
  local panel_buf = ctx.sidebar.buf
  herde.checkout("one")
  local first = vim.api.nvim_get_current_tabpage()
  created[#created + 1] = first
  assert(first ~= source_tab and ctx.sidebar:is_open(), "sidebar must follow a newly opened checkout")
  assert(vim.api.nvim_win_get_tabpage(ctx.sidebar.win) == first)
  assert(vim.api.nvim_get_current_win() ~= ctx.sidebar.win, "checkout must keep focus in the workspace editor")
  assert(ctx.sidebar.buf == panel_buf, "tab switches should reuse the overview buffer")
  assert(herde.workspace_statusline() == "Workspace: First workspace", "bottom bar must show the open checkout")
  assert(vim.bo[source_buf].modified, "source edits must survive checkout")
  local text = table.concat(vim.api.nvim_buf_get_lines(panel_buf, 0, -1, false), "\n")
  assert(text:find("Editing: First workspace", 1, true) and text:find("b back", 1, true), "panel must identify the checkout and return action")
  assert(notices[#notices]:find("<leader>ab back", 1, true), "checkout should explain the return key")
  vim.cmd("Herde back")
  assert(vim.api.nvim_get_current_tabpage() == source_tab and ctx.sidebar:is_open(), "back must return to source with overview visible")
  assert(vim.api.nvim_get_current_buf() == source_buf and vim.bo[source_buf].modified)
  herde.back()
  assert(vim.api.nvim_get_current_tabpage() == first and ctx.sidebar:is_open(), "back should toggle between the last tabs")
  local tabs = #vim.api.nvim_list_tabpages()
  herde.checkout("one")
  assert(#vim.api.nvim_list_tabpages() == tabs, "existing checkout must reuse its tab")
  herde.checkout("two")
  local second = vim.api.nvim_get_current_tabpage()
  created[#created + 1] = second
  assert(ctx.sidebar:is_open(), "sidebar must follow a second checkout")
  assert(herde.workspace_statusline() == "Workspace: Second workspace")
  herde.back()
  assert(vim.api.nvim_get_current_tabpage() == first and ctx.sidebar:is_open())
  assert(herde.workspace_statusline() == "Workspace: First workspace", "returning must update the bottom bar")
  vim.api.nvim_set_current_tabpage(source_tab)
  assert(ctx.sidebar:is_open(), "ordinary Neovim tab switches must carry the panel too")
  local count = 0
  for _, win in ipairs(vim.api.nvim_list_wins()) do if vim.api.nvim_win_get_buf(win) == panel_buf then count = count + 1 end end
  assert(count == 1, "switching tabs must not leave duplicate sidebar windows")
  ctx.sidebar:close()
  herde.checkout("two")
  assert(not ctx.sidebar:is_open(), "an intentionally closed sidebar must remain closed")
  herde.back()
  assert(vim.api.nvim_get_current_tabpage() == source_tab)
  herde.toggle()
  assert(ctx.sidebar:is_open(), "overview shortcut must reopen it in the current tab on the first try")
end, debug.traceback)
herde.teardown()
vim.notify = original_notify
if vim.api.nvim_buf_is_valid(source_buf) then vim.bo[source_buf].modified = false end
for _, tab in ipairs(created) do
  if vim.api.nvim_tabpage_is_valid(tab) then vim.api.nvim_set_current_tabpage(tab); vim.cmd("tabclose") end
end
if vim.api.nvim_tabpage_is_valid(source_tab) then vim.api.nvim_set_current_tabpage(source_tab) end
vim.cmd("cd " .. vim.fn.fnameescape(source_cwd))
vim.fn.delete(root, "rf")
assert(ok, err)
print("Workspace overview continuity and return navigation passed")
