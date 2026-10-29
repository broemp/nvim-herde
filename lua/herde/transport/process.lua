local M = {}

---Run an argv without a shell. All completions are scheduled onto Neovim's main loop.
---@return table handle with cancel()
function M.run(argv, opts, callback)
  opts = opts or {}
  local output, errors, bytes = {}, {}, 0
  local finished, stopped, job, reason = false, false, nil, nil
  local limit = opts.max_bytes or 2097152
  local function finish(err, result)
    if finished then return end
    finished = true
    vim.schedule(function() callback(err, result) end)
  end
  local function cancel(why)
    if finished then return end
    stopped, reason = true, why or "cancelled"
    if job then job:kill(9) end
  end
  local function collect(target)
    return function(err, data)
      if err then reason = tostring(err) end
      if not data or stopped then return end
      bytes = bytes + #data
      if bytes > limit then cancel("output limit exceeded (" .. limit .. " bytes)"); return end
      target[#target + 1] = data
    end
  end
  local ok, value = pcall(vim.system, argv, {
    text = true,
    timeout = opts.timeout or 10000,
    cwd = opts.cwd,
    env = opts.env,
    stdout = collect(output),
    stderr = collect(errors),
  }, function(result)
    local stdout, stderr = table.concat(output), table.concat(errors)
    local err = reason
    if not err and result.code ~= 0 then
      err = result.code == 124 and "command timed out; delivery may be uncertain"
        or (stderr ~= "" and vim.trim(stderr) or "command exited " .. result.code)
    end
    finish(err, { code = result.code, stdout = stdout, stderr = stderr, signal = result.signal })
  end)
  if ok then job = value else finish("cannot start " .. tostring(argv[1]) .. ": " .. tostring(value)) end
  return { cancel = function() cancel("cancelled") end }
end

return M
