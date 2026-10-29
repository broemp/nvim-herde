local U = require("herde.ui.util")
local roots = require("herde.core.project_root")
local M = {}

local function text(value)
  return type(value) == "string" and value ~= "" and value or nil
end

local function less(a, b)
  local an, bn = vim.fn.tolower(U.text(a.name)), vim.fn.tolower(U.text(b.name))
  if an ~= bn then return an < bn end
  if a.name ~= b.name then return a.name < b.name end
  return a.id < b.id
end

local function describe(workspace)
  local aliases = {}
  local scope = workspace.remote and "remote:" or "local:"
  local function alias(kind, value)
    if text(value) then aliases[#aliases + 1] = scope .. kind .. ":" .. value end
  end
  local function canonical(path)
    if not text(path) then return end
    if workspace.remote then return vim.fs.normalize(path):gsub("/$", "") end
    return roots.canonical(path)
  end
  local path = canonical(workspace.path)
  local project_path = canonical(workspace.project_path)
  local repo = not workspace.remote and roots.find(path or project_path) or nil
  alias("repo", workspace.project_id)
  alias("path", project_path)
  alias("path", path)
  if repo then alias("git", repo.id); alias("path", repo.root) end
  local name, rank = text(workspace.project_name), 3
  if not name and repo then name, rank = repo.name, 2 end
  if not name and (project_path or path) then name, rank = vim.fs.basename(project_path or path), 1 end
  if not name then name, rank = workspace.name or workspace.id, 0 end
  local weak = #aliases == 0
  alias("workspace", workspace.id)
  table.sort(aliases)
  return { id = aliases[1], aliases = aliases, name = name, rank = rank, weak = weak, workspace = workspace }
end

function M.group(workspaces, filter)
  local descriptions, parents, seen = {}, {}, {}
  local function find(i)
    local root = i
    while parents[root] ~= root do root = parents[root] end
    while parents[i] ~= i do local next_i = parents[i]; parents[i] = root; i = next_i end
    return root
  end
  for i, workspace in ipairs(workspaces) do
    parents[i] = i
    descriptions[i] = describe(workspace)
    for _, alias in ipairs(descriptions[i].aliases) do
      if seen[alias] then
        local a, b = find(i), find(seen[alias])
        parents[math.max(a, b)] = math.min(a, b)
      else seen[alias] = i end
    end
  end
  local lookup, grouped = {}, {}
  for i, desc in ipairs(descriptions) do
    local id = find(i)
    local project = lookup[id]
    if not project then
      project = { id = desc.id, name = desc.name, rank = desc.rank, weak = desc.weak, workspaces = {} }
      lookup[id], grouped[#grouped + 1] = project, project
    else
      local project_id = desc.id < project.id and desc.id or project.id
      if desc.rank > project.rank or (desc.rank == project.rank and less(desc, project)) then
        project.name, project.rank = desc.name, desc.rank
      end
      project.id, project.weak = project_id, project.weak and desc.weak
    end
    project.workspaces[#project.workspaces + 1] = desc.workspace
  end
  -- A workspace with no path can adopt an unambiguous known project name.
  -- Concrete repositories with equal basenames stay distinct.
  local names = {}
  for _, project in ipairs(grouped) do
    if not project.weak then
      local name = vim.fn.tolower(U.text(project.name))
      names[name] = names[name] or {}
      names[name][#names[name] + 1] = project
    end
  end
  table.sort(grouped, less)
  local projects, weak_names = {}, {}
  for _, project in ipairs(grouped) do
    local name = vim.fn.tolower(U.text(project.name))
    local matches = names[name] or {}
    local target = project.weak and (#matches == 1 and matches[1] or (#matches == 0 and weak_names[name])) or nil
    if target then vim.list_extend(target.workspaces, project.workspaces)
    else
      projects[#projects + 1] = project
      if project.weak and #matches == 0 then weak_names[name] = project end
    end
  end
  local visible = {}
  for _, project in ipairs(projects) do
    local children = {}
    for _, workspace in ipairs(project.workspaces) do
      if not filter or workspace.id == filter then children[#children + 1] = workspace end
    end
    if #children > 0 then
      project.workspaces = children
      table.sort(project.workspaces, less)
      visible[#visible + 1] = project
    end
  end
  table.sort(visible, less)
  return visible
end

return M
