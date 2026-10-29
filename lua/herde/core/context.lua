local M = {}
function M.capture(opts)
  opts = opts or {}
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].buftype ~= "" then return "" end
  local path = vim.api.nvim_buf_get_name(buf)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local lines = { string.format("File: %s:%d", path ~= "" and path or "[unnamed]", cursor[1]) }
  if opts.selection then
    local mode = vim.fn.mode()
    local first, last
    if mode:match("[vV\022]") then
      first = vim.fn.getpos("v")
      last = { 0, cursor[1], cursor[2] + 1, 0 }
    else
      first, last = vim.fn.getpos("'<"), vim.fn.getpos("'>")
    end
    if first[2] > last[2] or (first[2] == last[2] and first[3] > last[3]) then first, last = last, first end
    if first[2] > 0 then
      local selected = vim.api.nvim_buf_get_lines(buf, first[2] - 1, last[2], false)
      -- Linewise context includes complete lines so the agent sees surrounding syntax.
      table.insert(lines, string.format("Selection (complete lines %d-%d):", first[2], last[2]))
      table.insert(lines, table.concat(selected, "\n"))
    end
  end
  if opts.diagnostics then
    table.insert(lines, "Diagnostics:")
    for _, d in ipairs(vim.diagnostic.get(buf)) do
      table.insert(lines, string.format("%d:%d %s", d.lnum + 1, d.col + 1, d.message))
    end
  end
  return table.concat(lines, "\n")
end
return M
