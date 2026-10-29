local M = {}
local U = require("herde.ui.util")

function M.workspace(ctx)
  local id = vim.t.herde_workspace_id
  local store = ctx and ctx.store
  local workspace = id and store and store:get_workspace(id)
  local name = workspace and (workspace.name or workspace.id) or (id and vim.t.herde_workspace_name)
  local cwd = vim.fn.getcwd(-1, 0)
  -- A selected sidebar row is not the workspace currently open in the editor.
  if not id and store then
    if ctx.workspace_snapshot ~= store.snapshot then
      ctx.workspace_snapshot, ctx.workspace_paths = store.snapshot, {}
    end
    local longest = 0
    for _, candidate in ipairs(store.snapshot.workspaces) do
      local path = candidate.path
      if not candidate.remote and type(path) == "string" then
        if not ctx.workspace_paths[path] then ctx.workspace_paths[path] = (vim.uv or vim.loop).fs_realpath(path) or path end
        path = ctx.workspace_paths[path]
        path = path:gsub("/$", "")
        if #path >= longest and (cwd == path or cwd:sub(1, #path + 1) == path .. "/") then
          name, longest = candidate.name or candidate.id, #path
        end
      end
    end
  end
  if not name or name == "" then name = vim.fn.fnamemodify(cwd, ":t"); if name == "" then name = cwd end end
  -- Statusline expressions treat '%' specially; workspace names are plain text.
  return (("Workspace: " .. U.text(name)):gsub("%%", "%%%%"))
end

function M.refresh()
  local lualine = package.loaded.lualine
  if type(lualine) == "table" and type(lualine.refresh) == "function" then
    pcall(lualine.refresh, { place = { "statusline" } })
  end
end

function M.get(ctx)
  if not ctx or not ctx.store then return "" end
  if ctx.store.stale then return "Agents: disconnected" end
  if not ctx.store.has_snapshot then return "Agents: connecting" end
  local counts = ctx.store:counts()
  local working = counts.working or 0
  local attention = ctx.attention and #ctx.attention:list("active") or counts.blocked or 0
  return (ctx.store.stale and "Agents! " or "Agents: ") .. working .. " running / " .. attention .. " attention"
end
return M
