local process = require("herde.transport.process")
local M = {}
local states = { idle = true, working = true, blocked = true, done = true, unknown = true }

local function present(value)
  return value ~= nil and value ~= vim.NIL and value ~= ""
end

function M.decode(text)
  local ok, value = pcall(vim.json.decode, text)
  if not ok or type(value) ~= "table" then return nil, "Herdr returned invalid JSON" end
  if value.error then
    local e = value.error
    return nil, type(e) == "table" and ((e.code or "error") .. ": " .. (e.message or "")) or tostring(e)
  end
  return value.result or value
end

---Normalize protocol-22 SessionSnapshot. Fallback identities are instance-local.
function M.normalize(raw, namespace, identities)
  identities = identities or { occupants = {}, serial = 0, instance = tostring(vim.uv.hrtime()) }
  if type(raw) ~= "table" then return nil, "Herdr snapshot is not an object" end
  raw = raw.snapshot or raw
  if type(raw.workspaces) ~= "table" or type(raw.agents) ~= "table" then
    return nil, "Herdr snapshot missing workspaces or agents; check backend version"
  end
  local result = { namespace = namespace, workspaces = {}, agents = {}, version = raw.version, protocol = raw.protocol }
  local workspaces, seen = {}, {}
  for _, w in ipairs(raw.workspaces) do
    if type(w.workspace_id) == "string" then
      local tree = type(w.worktree) == "table" and w.worktree or {}
      local ws = { id = namespace .. "/" .. w.workspace_id, backend_id = w.workspace_id,
        name = w.label or w.workspace_id, path = present(tree.checkout_path) and tree.checkout_path or nil }
      if type(tree.repo_key) == "string" and tree.repo_key ~= "" then ws.project_id = namespace .. "/project/" .. tree.repo_key end
      if type(tree.repo_name) == "string" and tree.repo_name ~= "" then ws.project_name = tree.repo_name end
      if type(tree.repo_root) == "string" and tree.repo_root ~= "" then ws.project_path = tree.repo_root end
      result.workspaces[#result.workspaces + 1], workspaces[w.workspace_id] = ws, ws
    end
  end
  for _, a in ipairs(raw.agents) do
    if present(a.agent) and type(a.pane_id) == "string" and type(a.workspace_id) == "string" then
      local ws = workspaces[a.workspace_id]
      local session = type(a.agent_session) == "table" and a.agent_session or nil
      local stable = session and present(session.value) and present(session.kind)
      local terminal = tostring(a.terminal_id or a.pane_id)
      local occupant_key = terminal .. ":" .. a.agent
      local id
      if stable then
        -- Include the terminal identity: the same agent conversation can be open in two terminals.
        id = namespace .. "/agent/" .. a.agent .. "/" .. session.kind .. "/" .. session.value .. "/" .. terminal
      else
        if not identities.occupants[occupant_key] then
          identities.serial = identities.serial + 1
          identities.occupants[occupant_key] = "ephemeral/" .. identities.instance .. "/" .. identities.serial
        end
        id = namespace .. "/agent/" .. identities.occupants[occupant_key]
      end
      seen[occupant_key] = true
      local path = present(a.foreground_cwd) and a.foreground_cwd or (present(a.cwd) and a.cwd or (ws and ws.path))
      if ws and not ws.path and path then ws.path = path end
      result.agents[#result.agents + 1] = {
        id = id, name = present(a.name) and a.name or a.pane_id, kind = a.agent,
        state = states[a.agent_status] and a.agent_status or "unknown",
        workspace_id = namespace .. "/" .. a.workspace_id, pane_id = a.pane_id,
        terminal_id = a.terminal_id, path = path, identity_stable = not not stable,
        session = session, completion_seq = present(a.completion_seq) and a.completion_seq or nil,
        state_change_seq = a.state_change_seq, target = a.pane_id,
      }
    end
  end
  for key in pairs(identities.occupants) do if not seen[key] then identities.occupants[key] = nil end end
  return result
end

function M.new(opts)
  opts = opts or {}
  local config = opts.herdr or {}
  assert(not (config.machine and config.session), "Herdr machine and session cannot be combined")
  local namespace = "herdr:" .. (config.machine and ("machine:" .. config.machine)
    or config.session and ("session:" .. config.session) or (vim.env.HERDR_SOCKET_PATH or "default"))
  local prefix = { config.command or "herdr" }
  if config.machine then vim.list_extend(prefix, { "--machine", config.machine }) end
  if config.session then vim.list_extend(prefix, { "--session", config.session }) end
  local self = { capabilities = { read = true, focus = true, prompt = true, checkout = not config.machine }, namespace = namespace }
  local identities = { occupants = {}, serial = 0, instance = tostring(vim.uv.hrtime()) }
  local jobs, stopped = {}, false
  local function run(args, cb, max_bytes, text_output)
    if stopped then cb("backend stopped"); return end
    -- The user can operate Neovim outside Herdr. Let the CLI resolve its
    -- default session, inherited socket, or explicit session/machine selector.
    local argv = vim.list_extend(vim.deepcopy(prefix), args)
    local handle
    handle = process.run(argv, { timeout = opts.timeout or 10000, max_bytes = max_bytes or 4194304 }, function(err, output)
      jobs[handle] = nil
      if stopped then return end
      if err then
        if output and output.stderr then
          local ok, failure = pcall(vim.json.decode, output.stderr)
          if ok and type(failure) == "table" and type(failure.error) == "table" then
            err = (failure.error.code or "error") .. ": " .. (failure.error.message or err)
          end
        end
        cb(err)
        return
      end
      if text_output then cb(nil, output.stdout); return end
      local value, decode_err = M.decode(output.stdout)
      cb(decode_err, value)
    end)
    jobs[handle] = true
    return handle
  end
  function self:snapshot(cb)
    return run({ "api", "snapshot" }, function(err, value)
      if err then cb(err); return end
      local snapshot, normalize_err = M.normalize(value, namespace, identities)
      if snapshot and config.machine then
        for _, ws in ipairs(snapshot.workspaces) do ws.remote = true end
        for _, agent in ipairs(snapshot.agents) do agent.remote = true end
      end
      cb(normalize_err, snapshot)
    end)
  end
  function self:read(agent, cb)
    local preview = opts.preview or {}
    return run({ "agent", "read", agent.pane_id, "--source", "recent-unwrapped", "--lines", tostring(preview.lines or 120), "--format", "text" }, function(err, text)
      if err then cb(err); return end
      cb(nil, text:sub(-(preview.max_bytes or 131072)))
    end, math.max((preview.max_bytes or 131072) * 8, 1048576), true)
  end
  local function validate(agent, cb)
    run({ "agent", "get", agent.pane_id }, function(err, value)
      if err then cb(err); return end
      local raw = value.agent
      if type(raw) ~= "table" then cb("Herdr get response missing agent"); return end
      local normalized, e = M.normalize({ workspaces = {}, agents = { raw } }, namespace, vim.deepcopy(identities))
      if e or not normalized.agents[1] or normalized.agents[1].id ~= agent.id then cb("Agent occupant changed; refresh and select again"); return end
      cb(nil, normalized.agents[1])
    end)
  end
  function self:focus(agent, cb)
    validate(agent, function(err)
      if err then cb(err); return end
      run({ "agent", "focus", agent.pane_id }, cb)
    end)
  end
  function self:prompt(agent, text, cb)
    if type(text) ~= "string" or vim.trim(text) == "" then cb("Prompt is empty"); return end
    if text:sub(1, 1) == "-" then
      cb("Prompt begins with '-'; add an introductory sentence because this Herdr CLI's positional flag escaping is unverified")
      return
    end
    validate(agent, function(err, current)
      if err then cb(err); return end
      if current.state == "blocked" then cb("Agent needs input in its terminal; focus it to answer"); return end
      -- Deliberately do not retry. Submission does not wait for a model turn.
      run({ "agent", "prompt", agent.pane_id, text }, cb)
    end)
  end
  function self:stop()
    stopped = true
    for job in pairs(jobs) do job.cancel() end
    jobs = {}
  end
  return self
end

return M
