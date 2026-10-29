local M = {}
M.defaults = {
  backend = "herdr",
  herdr = { command = "herdr" },
  timeout = 10000,
  poll = { visible = 2000, hidden = 10000, max_backoff = 60000 },
  sidebar = { width = 38, position = "right" },
  ui = { border = "rounded", icons = true },
  preview = { lines = 120, max_bytes = 131072, height = 12, follow = false },
  notifications = { enabled = true, blocked = true, completed = true, quiet = false },
  picker = "auto",
  fzf = {}, -- Per-picker fzf-lua options; leaves global setup untouched.
  history_limit = 200,
}
function M.resolve(opts)
  assert(opts == nil or type(opts) == "table", "herde: options must be a table")
  local c = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  assert(c.backend == "herdr" or c.backend == "demo" or type(c.backend) == "table", "herde: invalid backend")
  if type(c.backend) == "table" then
    for _, method in ipairs({ "snapshot", "read", "focus", "prompt", "stop" }) do
      assert(type(c.backend[method]) == "function", "herde: backend must implement " .. method)
    end
    assert(type(c.backend.capabilities) == "table", "herde: backend capabilities must be a table")
  end
  for _, key in ipairs({ "poll", "preview", "sidebar", "notifications", "herdr", "ui", "fzf" }) do
    assert(type(c[key]) == "table", "herde: " .. key .. " must be a table")
  end
  for _, key in ipairs({ "timeout", "history_limit" }) do
    assert(type(c[key]) == "number" and c[key] > 0, "herde: " .. key .. " must be positive")
  end
  for _, key in ipairs({ "visible", "hidden", "max_backoff" }) do
    assert(type(c.poll[key]) == "number" and c.poll[key] >= 100, "herde: invalid poll." .. key)
  end
  for _, key in ipairs({ "lines", "max_bytes", "height" }) do
    assert(type(c.preview[key]) == "number" and c.preview[key] >= 1, "herde: invalid preview." .. key)
  end
  assert(type(c.sidebar.width) == "number" and c.sidebar.width >= 16, "herde: sidebar.width must be >= 16")
  assert(c.sidebar.position == "left" or c.sidebar.position == "right", "herde: sidebar.position must be left or right")
  assert(vim.tbl_contains({ "auto", "native", "fzf-lua", "snacks" }, c.picker), "herde: invalid picker")
  assert(type(c.ui.icons) == "boolean", "herde: ui.icons must be boolean")
  assert(type(c.ui.border) == "string" or type(c.ui.border) == "table", "herde: invalid ui.border")
  assert(not (c.herdr.machine and c.herdr.session), "herde: machine and session are mutually exclusive")
  for _, key in ipairs({ "command", "machine", "session" }) do
    if c.herdr[key] ~= nil then assert(type(c.herdr[key]) == "string" and c.herdr[key] ~= "", "herde: invalid herdr." .. key) end
  end
  for _, key in ipairs({ "enabled", "blocked", "completed", "quiet" }) do
    assert(type(c.notifications[key]) == "boolean", "herde: invalid notifications." .. key)
  end
  assert(type(c.preview.follow) == "boolean", "herde: invalid preview.follow")
  if c.state_dir then assert(type(c.state_dir) == "string", "herde: invalid state_dir") end
  return c
end
return M
