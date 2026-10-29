local M = {}

function M.valid(win)
  return win and vim.api.nvim_win_is_valid(win)
end

function M.clean(text)
  return tostring(text or ""):gsub("\27%][^\7]*\7", ""):gsub("\27%[[%d;?]*[ -/]*[@-~]", ""):gsub("[%z\1-\8\11-\31\127]", "")
end

function M.buf(name, editable)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "herde"
  vim.bo[buf].modifiable = editable or false
  pcall(vim.api.nvim_buf_set_name, buf, "herde://" .. name .. "/" .. buf)
  return buf
end

function M.lines(buf, lines)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  local editable = vim.bo[buf].modifiable
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = editable
  vim.bo[buf].modified = false
end

function M.float(buf, title, width, height, enter, opts)
  opts = opts or {}
  width = math.max(1, math.min(width or 86, vim.o.columns - 4))
  height = math.max(1, math.min(height or 22, vim.o.lines - 5))
  local win = vim.api.nvim_open_win(buf, enter ~= false, {
    relative = "editor", width = width, height = height,
    row = math.max(0, math.floor((vim.o.lines - height - 2) / 2)),
    col = math.max(0, math.floor((vim.o.columns - width - 2) / 2)),
    style = "minimal", border = opts.border or "rounded", title = { { " " .. M.clip(title, width - 2) .. " ", "HerdeTitle" } }, title_pos = "left",
    footer = opts.footer and { { " " .. M.clip(opts.footer, width - 2) .. " ", "HerdeHint" } } or nil,
    footer_pos = opts.footer and "left" or nil,
  })
  M.window(win)
  return win
end

function M.window(win)
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true
  vim.wo[win].winfixwidth = true
  vim.wo[win].winfixheight = true
  vim.wo[win].list = false
  vim.wo[win].spell = false
  vim.wo[win].foldcolumn = "0"
  -- Editor scroll context shouldn't push a tree cursor around when it folds.
  vim.wo[win].scrolloff = 0
  vim.wo[win].sidescrolloff = 0
  vim.wo[win].winhighlight = "Normal:HerdeNormal,NormalFloat:HerdeNormal,FloatBorder:HerdeBorder,CursorLine:HerdeSelected,EndOfBuffer:HerdeNormal"
end

-- Single-line text for lists. Never let a task label become another row or field.
function M.text(text) return (M.clean(text):gsub("[\n\r\t]", " ")) end

function M.clip(text, width)
  text, width = M.text(text), math.max(0, width)
  if vim.fn.strdisplaywidth(text) <= width then return text end
  if width == 0 then return "" end
  local out, size = {}, 0
  for i = 0, vim.fn.strchars(text) - 1 do
    local ch = vim.fn.strcharpart(text, i, 1)
    local cells = vim.fn.strdisplaywidth(ch)
    if size + cells > width - 1 then break end
    out[#out + 1], size = ch, size + cells
  end
  return table.concat(out) .. "…"
end

function M.columns(left, right, width)
  right = M.clip(right, math.floor(width / 2))
  left = M.clip(left, math.max(0, width - vim.fn.strdisplaywidth(right) - 1))
  return left .. string.rep(" ", math.max(1, width - vim.fn.strdisplaywidth(left .. right))) .. right
end

function M.path(path)
  path = M.text(path)
  local home = (vim.uv or vim.loop).os_homedir()
  if path == home then return "~" end
  if path:sub(1, #home + 1) == home .. "/" then return "~" .. path:sub(#home + 1) end
  return path
end

function M.paint(buf, spans)
  local ns = vim.api.nvim_create_namespace("herde.decoration")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, span in ipairs(spans) do
    vim.api.nvim_buf_add_highlight(buf, ns, span[2], span[1], span[3] or 0, span[4] or -1)
  end
end

function M.map(buf, key, fn, desc)
  vim.keymap.set("n", key, fn, { buffer = buf, silent = true, nowait = true, desc = "Herde: " .. desc })
end

function M.close(self)
  local win = self.win
  self.win = nil
  if M.valid(win) then pcall(vim.api.nvim_win_close, win, true) end
end

function M.delete(self)
  M.close(self)
  if self.buf and vim.api.nvim_buf_is_valid(self.buf) then
    pcall(vim.api.nvim_buf_delete, self.buf, { force = true })
  end
  self.buf = nil
end

function M.label(ctx, agent)
  return ctx.workspaces and ctx.workspaces:label(agent.id) or nil
end

function M.error(err)
  if type(err) == "table" then return tostring(err.message or err.code or vim.inspect(err)) end
  return tostring(err)
end

function M.action(ctx, action, ...)
  if ctx.actions and ctx.actions[action] then return ctx.actions[action](...) end
end

function M.age(timestamp)
  local seconds = math.max(0, os.time() - (tonumber(timestamp) or os.time()))
  if seconds < 60 then return seconds .. "s" end
  if seconds < 3600 then return math.floor(seconds / 60) .. "m" end
  return math.floor(seconds / 3600) .. "h"
end

M.symbols = { working = "●", blocked = "!", done = "✓", idle = "○", unknown = "?" }
M.ascii_symbols = { working = "*", blocked = "!", done = "+", idle = "-", unknown = "?" }
M.states = { working = "Working", blocked = "Needs input", done = "Completed", idle = "Idle", unknown = "Unknown" }
return M
