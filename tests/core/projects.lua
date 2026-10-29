local projects = require("herde.ui.projects")
local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/cruised/.git/worktrees/feature", "p")
vim.fn.mkdir(root .. "/cruised/internal/booking", "p")
vim.fn.mkdir(root .. "/feature-worktree/subdir", "p")
vim.fn.writefile({ "gitdir: ../cruised/.git/worktrees/feature" }, root .. "/feature-worktree/.git")
vim.fn.writefile({ "../.." }, root .. "/cruised/.git/worktrees/feature/commondir")
local inventory = {
  { id = "main", name = "Main", path = root .. "/cruised" },
  { id = "nested", name = "Booking", path = root .. "/cruised/internal/booking" },
  { id = "feature", name = "Feature", path = root .. "/feature-worktree/subdir" },
  { id = "metadata", name = "Metadata", project_id = "repo-key", project_name = "cruised", project_path = root .. "/cruised", path = root .. "/missing-checkout" },
  { id = "named-only", name = "cruised" },
}
local ok, err = xpcall(function()
  local grouped = projects.group(inventory)
  assert(#grouped == 1 and #grouped[1].workspaces == 5, "main, nested cwd, linked worktree, metadata, and unambiguous label must share one project")
  assert(grouped[1].name == "cruised")
  local reversed = {}
  for i = #inventory, 1, -1 do reversed[#reversed + 1] = inventory[i] end
  local reverse_groups = projects.group(reversed)
  assert(#reverse_groups == 1 and reverse_groups[1].id == grouped[1].id, "project identity must be independent of backend row order")
  local filtered = projects.group(inventory, "feature")
  assert(#filtered == 1 and filtered[1].name == "cruised" and #filtered[1].workspaces == 1, "workspace filtering must preserve its parent project")
  local aliases = projects.group({
    { id = "explicit", name = "One", project_id = "repo", project_name = "cruised", project_path = "/offline/cruised" },
    { id = "plain", name = "Two", path = "/offline/cruised/" },
  })
  assert(#aliases == 1, "metadata and matching path must merge even when the repository is unavailable")
  local ambiguous = projects.group({
    { id = "a", name = "A", path = "/one/cruised" },
    { id = "b", name = "B", path = "/two/cruised" },
    { id = "c", name = "cruised" },
  })
  assert(#ambiguous == 3, "equal names cannot merge distinct repositories or an ambiguous orphan")
end, debug.traceback)
vim.fn.delete(root, "rf")
assert(ok, err)
print("Canonical project identity and linked worktree grouping passed")
