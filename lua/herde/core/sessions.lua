local M = {}
local uv = vim.uv or vim.loop

local function eligible(win)
  local buf = vim.api.nvim_win_get_buf(win)
  return vim.bo[buf].buftype == "" and not vim.bo[buf].filetype:match("^herde")
end

local function capture_node(node)
  if node[1] == "leaf" then
    local win = node[2]
    if not eligible(win) then return nil end
    local file = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
    if file == "" then return nil end
    return { kind = "leaf", file = file, cursor = vim.api.nvim_win_get_cursor(win),
      view = vim.api.nvim_win_call(win, vim.fn.winsaveview) }
  end
  local children = {}
  for _, child in ipairs(node[2]) do
    local captured = capture_node(child)
    if captured then children[#children + 1] = captured end
  end
  if #children == 0 then return nil end
  if #children == 1 then return children[1] end
  return { kind = node[1], children = children }
end

local function session_dir(opts)
  local dir = (opts.state_dir or (vim.fn.stdpath("state") .. "/herde")) .. "/sessions"
  vim.fn.mkdir(dir, "p")
  return dir
end

function M.capture(tab)
  tab = tab or vim.api.nvim_get_current_tabpage()
  return vim.api.nvim_win_call(vim.api.nvim_tabpage_get_win(tab), function()
    return { version = 1, cwd = vim.fn.getcwd(), tree = capture_node(vim.fn.winlayout()) }
  end)
end

function M.save(key, opts, tab)
  opts = opts or {}
  local data = M.capture(tab)
  data.key = key
  -- Per-process files prevent competing Neovim instances from overwriting
  -- each other's sessions. Restoration chooses the newest complete snapshot.
  local file = session_dir(opts) .. "/" .. vim.fn.sha256(key) .. "-" .. vim.fn.getpid() .. ".json"
  local temp = file .. ".tmp"
  local ok, err = pcall(function()
    assert(vim.fn.writefile({ vim.json.encode(data) }, temp) == 0, "Could not write editor session")
    assert(uv.fs_rename(temp, file))
  end)
  if not ok then uv.fs_unlink(temp); return nil, tostring(err) end
  return true
end

function M.load(key, opts)
  opts = opts or {}
  local files = vim.fn.glob(session_dir(opts) .. "/" .. vim.fn.sha256(key) .. "-*.json", false, true)
  table.sort(files, function(a, b)
    local sa, sb = uv.fs_stat(a), uv.fs_stat(b)
    if sa.mtime.sec == sb.mtime.sec then return sa.mtime.nsec > sb.mtime.nsec end
    return sa.mtime.sec > sb.mtime.sec
  end)
  for _, path in ipairs(files) do
    local ok, data = pcall(function() return vim.json.decode(table.concat(vim.fn.readfile(path), "\n")) end)
    if ok and data.version == 1 and data.key == key then return data end
  end
end

local function restore_node(node, win)
  if not node then return end
  if node.kind == "leaf" then
    if type(node.file) ~= "string" or vim.fn.filereadable(node.file) ~= 1 then return end
    local buf = vim.fn.bufadd(node.file)
    vim.fn.bufload(buf)
    vim.api.nvim_win_set_buf(win, buf)
    if type(node.view) == "table" then vim.api.nvim_win_call(win, function() pcall(vim.fn.winrestview, node.view) end) end
    if type(node.cursor) == "table" then pcall(vim.api.nvim_win_set_cursor, win, node.cursor) end
    return
  end
  if node.kind ~= "row" and node.kind ~= "col" then return end
  local windows = { win }
  for _ = 2, #(node.children or {}) do
    vim.api.nvim_set_current_win(windows[#windows])
    vim.cmd(node.kind == "row" and "belowright vsplit" or "belowright split")
    windows[#windows + 1] = vim.api.nvim_get_current_win()
  end
  for i, child in ipairs(node.children or {}) do restore_node(child, windows[i]) end
end

function M.restore(data, tab)
  if not data or data.version ~= 1 then return end
  vim.api.nvim_win_call(vim.api.nvim_tabpage_get_win(tab or vim.api.nvim_get_current_tabpage()), function()
    restore_node(data.tree, vim.api.nvim_get_current_win())
  end)
end

return M
