-- Read-only repository identity discovery. No Git processes run during rendering.
local M = {}
local uv = vim.uv or vim.loop
local cache, cache_size = {}, 0

function M.canonical(path)
  if type(path) ~= "string" or path == "" then return nil end
  local normalized = vim.fs.normalize(uv.fs_realpath(path) or path)
  return normalized == "/" and normalized or normalized:gsub("/$", "")
end

local function first_line(path)
  local fd = uv.fs_open(path, "r", 0)
  if not fd then return nil end
  local value = uv.fs_read(fd, 4096, 0)
  uv.fs_close(fd)
  return value and value:match("([^\r\n]+)")
end

local function relative(base, path)
  if path:sub(1, 1) == "/" or path:match("^%a:[/\\]") then return M.canonical(path) end
  return M.canonical(base .. "/" .. path)
end

local function discover(path)
  local stat = uv.fs_stat(path)
  if not stat then return end
  local dir = stat.type == "directory" and path or vim.fs.dirname(path)
  while dir do
    local marker = dir .. "/.git"
    local git_stat = uv.fs_stat(marker)
    local git_dir
    if git_stat and git_stat.type == "directory" then git_dir = M.canonical(marker)
    elseif git_stat and git_stat.type == "file" then
      local line = first_line(marker)
      local target = line and line:match("^gitdir:%s*(.-)%s*$")
      if target and target ~= "" then git_dir = relative(dir, target) end
    end
    if git_dir then
      local common = first_line(git_dir .. "/commondir")
      local common_dir = common and relative(git_dir, common) or git_dir
      local common_stat = common_dir and uv.fs_stat(common_dir)
      if common_stat and common_stat.type == "directory" then
        local root = vim.fs.basename(common_dir) == ".git" and vim.fs.dirname(common_dir) or dir
        return { id = common_dir, root = root, name = vim.fs.basename(root) }
      end
    end
    local parent = vim.fs.dirname(dir)
    if not parent or parent == dir then return end
    dir = parent
  end
end

function M.find(path)
  path = M.canonical(path)
  if not path then return end
  local now = uv.hrtime()
  local hit = cache[path]
  if hit and now - hit.time < 5000000000 then return hit.value or nil end
  local value = discover(path)
  if cache_size >= 512 then cache, cache_size = {}, 0 end
  if not cache[path] then cache_size = cache_size + 1 end
  cache[path] = { time = now, value = value or false }
  return value
end

return M
