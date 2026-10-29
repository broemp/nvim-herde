local M = {}
local sessions = require("herde.core.sessions")
local uv = vim.uv or vim.loop

function M.open(workspace, opts, cb)
  opts = opts or {}
  cb = cb or function(err) if err then vim.notify(tostring(err), vim.log.levels.WARN) end end
  if not workspace then cb("Select a workspace or agent first"); return end
  if workspace.remote then cb("This checkout is remote and cannot be opened as a local directory"); return end
  if type(workspace.path) ~= "string" or workspace.path == "" then cb("The backend did not provide a checkout path"); return end
  -- Treat backend paths as literal paths; expand() also evaluates backtick
  -- expressions and wildcard syntax, which are not checkout navigation.
  local path = workspace.path
  if path == "~" or path:sub(1, 2) == "~/" then path = uv.os_homedir() .. path:sub(2) end
  if path:sub(1, 1) ~= "/" and not path:match("^%a:[/\\]") then cb("The backend checkout path must be absolute"); return end
  local stat = uv.fs_stat(path)
  if not stat or stat.type ~= "directory" then cb("Checkout directory does not exist locally: " .. path); return end
  local id = assert(workspace.id, "workspace.id required")
  local source = vim.api.nvim_get_current_tabpage()
  local source_key = vim.t.herde_workspace_id or ("cwd:" .. vim.fn.getcwd())
  local saved, err = sessions.save(source_key, opts, source)
  if not saved then cb("Could not save current editor session: " .. tostring(err)); return end
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    local ok, key = pcall(vim.api.nvim_tabpage_get_var, tab, "herde_workspace_id")
    if ok and key == id then
      vim.api.nvim_tabpage_set_var(tab, "herde_workspace_name", workspace.name or id)
      vim.api.nvim_set_current_tabpage(tab); cb(nil, tab); return tab
    end
  end
  local data = sessions.load(id, opts)
  vim.cmd("tabnew")
  local tab = vim.api.nvim_get_current_tabpage()
  vim.t.herde_workspace_id = id
  vim.t.herde_workspace_name = workspace.name or id
  local ok, restore_err = pcall(function()
    vim.cmd("tcd " .. vim.fn.fnameescape(path))
    if data and data.tree then sessions.restore(data, tab)
    else vim.cmd("edit " .. vim.fn.fnameescape(path)) end
  end)
  if not ok then
    -- Keep both tabs and every buffer, including any buffers opened before the
    -- failure. The caller can inspect the partial restoration safely.
    cb("Checkout opened but its editor session could not be restored: " .. tostring(restore_err))
    return tab
  end
  cb(nil, tab)
  return tab
end

function M.save_current(opts)
  local key = vim.t.herde_workspace_id
  if key then return sessions.save(key, opts or {}) end
  return true
end

return M
