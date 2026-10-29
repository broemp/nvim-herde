local herde = require("herde")
local dir = vim.fn.tempname()
local original = vim.api.nvim_get_current_win()
herde.setup({ backend = "demo", state_dir = dir, notifications = { enabled = false } })
local ctx = herde.get_context()
assert(vim.wait(1000, function() return ctx.store.has_snapshot end))
herde.toggle()
local sidebar = ctx.sidebar
local editor_pos = vim.api.nvim_win_get_position(original)
local sidebar_pos = vim.api.nvim_win_get_position(sidebar.win)
assert(sidebar_pos[2] > editor_pos[2], "sidebar must open on the right")
vim.api.nvim_set_current_win(sidebar.win)
local function row(kind, part, id)
  for n = 1, vim.api.nvim_buf_line_count(sidebar.buf) do
    local value = sidebar.rows[n]
    if value and value.type == kind and value.part == part and (not id or value.id == id) then return n, value.id end
  end
  error("row not found: " .. kind .. ":" .. part)
end
local heading = row("workspace", "title")
vim.api.nvim_win_set_cursor(sidebar.win, { heading, 4 })
local before = vim.api.nvim_win_get_cursor(sidebar.win)
ctx.store:update(vim.deepcopy(ctx.store.snapshot))
assert(vim.deep_equal(before, vim.api.nvim_win_get_cursor(sidebar.win)), "polling must preserve workspace row and column")
local workspace_id = sidebar.rows[heading].id
local enter = vim.fn.maparg("<CR>", "n", false, true).callback
assert(type(enter) == "function")
enter()
assert(sidebar.collapsed[workspace_id], "Enter on a workspace must collapse it")
assert(vim.api.nvim_win_get_cursor(sidebar.win)[1] == row("workspace", "title", workspace_id), "collapse must keep the workspace heading selected")
enter()
assert(not sidebar.collapsed[workspace_id], "Enter again must expand it")
local path_row = row("workspace", "path", workspace_id)
vim.api.nvim_win_set_cursor(sidebar.win, { path_row, 4 })
enter()
assert(sidebar.collapsed[workspace_id] and vim.api.nvim_win_get_cursor(sidebar.win)[1] == row("workspace", "title", workspace_id), "collapsing from a hidden path must anchor to its workspace heading")
enter()
local metadata, id = row("agent", "state", ctx.store.selected_id)
vim.api.nvim_win_set_cursor(sidebar.win, { metadata, 5 })
before = vim.api.nvim_win_get_cursor(sidebar.win)
for _ = 1, 3 do ctx.store:update(vim.deepcopy(ctx.store.snapshot)) end
assert(vim.deep_equal(before, vim.api.nvim_win_get_cursor(sidebar.win)), "polling must preserve the metadata row")
local other = ctx.store.snapshot.agents[2]
if other.id == id then other = ctx.store.snapshot.agents[1] end
ctx.actions.select(other.id)
assert(vim.api.nvim_win_get_cursor(sidebar.win)[1] == row("agent", "title", other.id), "explicit selection must still navigate")
ctx.inbox:open()
local inbox = ctx.inbox
local first
for n = 1, vim.api.nvim_buf_line_count(inbox.buf) do if inbox.rows[n] then first = n; break end end
assert(first)
vim.api.nvim_win_set_cursor(inbox.win, { first + 1, 4 })
before = vim.api.nvim_win_get_cursor(inbox.win)
ctx.store:emit()
assert(vim.deep_equal(before, vim.api.nvim_win_get_cursor(inbox.win)), "inbox refresh must preserve the detail row")
inbox:close()
local projects = require("herde.ui.projects")
local workspaces = {
  { id = "beta", name = "Review", project_id = "repo-b", project_name = "beta" },
  { id = "alpha-feature", name = "Feature", project_id = "repo-a", project_name = "Alpha" },
  { id = "alpha-main", name = "Main", project_id = "repo-a", project_name = "Alpha" },
  { id = "same-name-one", name = "One", path = "/projects/one/shared" },
  { id = "same-name-two", name = "Two", path = "/projects/two/shared" },
}
local groups = projects.group(workspaces)
assert(#groups == 4 and groups[1].name == "Alpha" and groups[2].name == "beta", "projects must be alphabetical without merging unrelated directory basenames")
assert(#groups[1].workspaces == 2 and groups[1].workspaces[1].id == "alpha-feature", "worktrees of one project must group together and sort by workspace")
assert(workspaces[1].id == "beta", "rendering order must not mutate the backend inventory")
local filtered = projects.group(workspaces, "alpha-main")
assert(#filtered == 1 and #filtered[1].workspaces == 1 and filtered[1].workspaces[1].id == "alpha-main")
ctx.store:update({ workspaces = workspaces, agents = {} })
local contents = table.concat(vim.api.nvim_buf_get_lines(sidebar.buf, 0, -1, false), "\n")
local alpha, beta = contents:find("1. Alpha", 1, true), contents:find("2. beta", 1, true)
assert(alpha and beta and alpha < beta, "sidebar must render numbered project headings in order")
assert(row("workspace", "title", "alpha-feature") < row("workspace", "title", "alpha-main"))
local many = {}
for n = 1, 60 do many[n] = { id = "demo/" .. n, workspace_id = "demo/main", name = string.format("agent%03d", n), kind = "pi", state = "idle" } end
ctx.store:update({ workspaces = { { id = "demo/main", name = "Many agents" } }, agents = many })
vim.api.nvim_set_current_win(sidebar.win)
local middle = row("agent", "state", "demo/30")
vim.api.nvim_win_set_cursor(sidebar.win, { middle, 5 })
vim.api.nvim_exec_autocmds("CursorMoved", { buffer = sidebar.buf })
assert(vim.api.nvim_win_get_cursor(sidebar.win)[1] == middle, "cursor-driven selection must preserve the clicked metadata row")
vim.api.nvim_win_call(sidebar.win, function() vim.fn.winrestview({ lnum = middle, col = 5, topline = middle - 6 }) end)
local view_before = vim.api.nvim_win_call(sidebar.win, vim.fn.winsaveview)
ctx.store:update(vim.deepcopy(ctx.store.snapshot))
local view_after = vim.api.nvim_win_call(sidebar.win, vim.fn.winsaveview)
assert(view_before.topline == view_after.topline and view_before.lnum == view_after.lnum, "polling must preserve scroll position in large inventories")
herde.teardown()
vim.fn.delete(dir, "rf")
print("Right sidebar and stable cursor checks passed")
