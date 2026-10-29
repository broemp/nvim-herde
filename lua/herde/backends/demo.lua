local M = {}
function M.new(opts)
  opts = opts or {}
  local stopped, step = false, 0
  local root = opts.demo and opts.demo.path or vim.fn.getcwd()
  local snapshot = {
    namespace = "demo",
    workspaces = { { id = "demo/main", name = "Current project", path = root }, { id = "demo/review", name = "Review workspace", path = root } },
    agents = {
      { id = "demo/builder", name = "builder", kind = "pi", state = "working", workspace_id = "demo/main", pane_id = "demo:p1", path = root, identity_stable = true },
      { id = "demo/reviewer", name = "reviewer", kind = "codex", state = "blocked", workspace_id = "demo/main", pane_id = "demo:p2", path = root, identity_stable = true },
      { id = "demo/tests", name = "tests", kind = "claude", state = "idle", workspace_id = "demo/review", pane_id = "demo:p3", path = root, identity_stable = true },
    },
  }
  local self = { capabilities = { read = true, focus = false, prompt = false, checkout = true }, namespace = "demo" }
  local function reply(cb, err, result)
    vim.schedule(function() if not stopped then cb(err, result) end end)
  end
  function self:snapshot(cb)
    step = step + 1
    if opts.demo and opts.demo.animate and step % 4 == 0 then
      snapshot.agents[1].state = snapshot.agents[1].state == "working" and "done" or "working"
    end
    reply(cb, nil, vim.deepcopy(snapshot))
  end
  function self:read(agent, cb)
    reply(cb, nil, "Demo preview for " .. agent.name .. " (" .. agent.kind .. ")\n"
      .. (agent.state == "blocked" and "Should retries include timeouts?\nFocus an actual Herdr agent to answer." or "Inspecting project files...\nLatest state: " .. agent.state))
  end
  function self:focus(_, cb) reply(cb, "Demo backend cannot focus a terminal") end
  function self:prompt(_, _, cb) reply(cb, "Demo backend cannot submit prompts") end
  function self:stop() stopped = true end
  return self
end
return M
