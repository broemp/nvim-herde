local M = {}
local uv = vim.uv or vim.loop
local defaults = { version = 1, labels = {}, layouts = {}, events = {}, muted = {}, quiet = false }

local function read(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then return nil end
  local decoded, value = pcall(vim.json.decode, table.concat(lines, "\n"))
  if decoded and type(value) == "table" and value.version == 1 then return value end
  if decoded and type(value) == "table" and value.version ~= nil then
    return nil, "Unsupported Herde metadata version: " .. tostring(value.version)
  end
  return nil, "Herde metadata is not valid versioned JSON: " .. path
end

function M.new(opts)
  opts = opts or {}
  local directory = opts.state_dir or (vim.fn.stdpath("state") .. "/herde")
  vim.fn.mkdir(directory, "p")
  local path = directory .. "/metadata.json"
  -- One writer owns metadata for its lifetime. Other Neovim instances are
  -- read-only, preventing lost updates without attempting unsafe JSON merges.
  local lock = path .. ".lock"
  local fd = uv.fs_open(lock, "wx", 384)
  if not fd then
    local owner = read(lock)
    if owner and type(owner.pid) == "number" then
      local alive, err = uv.kill(owner.pid, 0)
      if not alive and err and tostring(err):find("ESRCH", 1, true) then
        uv.fs_unlink(lock)
        fd = uv.fs_open(lock, "wx", 384)
      end
    end
  end
  if fd then uv.fs_write(fd, vim.json.encode({ version = 1, pid = vim.fn.getpid() }), 0); uv.fs_close(fd) end
  local loaded, read_error = read(path)
  local data = vim.tbl_deep_extend("force", vim.deepcopy(defaults), loaded or {})
  for _, key in ipairs({ "labels", "layouts", "events", "muted" }) do
    if type(data[key]) ~= "table" then data[key] = {} end
  end
  for id, label in pairs(data.labels) do if type(id) ~= "string" or type(label) ~= "string" then data.labels[id] = nil end end
  for id, layout in pairs(data.layouts) do if type(id) ~= "string" or type(layout) ~= "table" then data.layouts[id] = nil end end
  data.quiet = data.quiet == true
  local self = { data = data, directory = directory, path = path, writable = fd ~= nil and not read_error,
    error = read_error, closed = false }
  function self:save()
    if self.closed then return nil, "Metadata store is closed" end
    if self.error then return nil, self.error end
    if not self.writable then return nil, "Another Neovim instance owns Herde metadata; this instance is read-only" end
    local temp = path .. "." .. vim.fn.getpid() .. ".tmp"
    local ok, err = pcall(function()
      self.data.version = 1
      local out, open_err = uv.fs_open(temp, "w", 384)
      assert(out, open_err)
      local success, write_err = uv.fs_write(out, vim.json.encode(self.data), 0)
      uv.fs_close(out)
      assert(success, write_err)
      local renamed, rename_err = uv.fs_rename(temp, path)
      assert(renamed, rename_err)
    end)
    if not ok then uv.fs_unlink(temp); return nil, tostring(err) end
    return true
  end
  function self:close()
    if self.closed then return end
    if self.writable then self:save() end
    if fd then uv.fs_unlink(lock) end
    self.closed = true
  end
  return self
end

return M
