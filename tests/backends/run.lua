local herdr = require("herde.backends.herdr")
local process = require("herde.transport.process")
local fixture = table.concat(vim.fn.readfile("tests/fixtures/herdr/snapshot.json"), "\n")
local raw = assert(herdr.decode(fixture))
local identities = { occupants = {}, serial = 0, instance = "test" }
local first = assert(herdr.normalize(raw, "local", identities))
assert(#first.agents == 2 and #first.workspaces == 1)
assert(first.agents[1].identity_stable and not first.agents[2].identity_stable)
assert(first.agents[1].kind == "pi" and first.agents[2].state == "blocked")
assert(first.workspaces[1].path == "/tmp/herde-fixture")
assert(first.workspaces[1].project_id == "local/project/fixture" and first.workspaces[1].project_name == "fixture")
assert(first.workspaces[1].project_path == "/tmp/herde-fixture", "project root must be separate from linked checkout path")
local second = assert(herdr.normalize(raw, "local", identities))
assert(first.agents[2].id == second.agents[2].id, "fallback identity must survive a refresh")
local other = assert(herdr.normalize(raw, "remote", { occupants = {}, serial = 0, instance = "test" }))
assert(first.agents[1].id ~= other.agents[1].id, "namespaces must isolate identities")
local moved = vim.deepcopy(raw)
moved.snapshot.agents[1].pane_id = "w2:p9"
assert(herdr.normalize(moved, "local", identities).agents[1].id == first.agents[1].id, "pane move must retain verified occupant identity")
local removed = vim.deepcopy(raw)
removed.snapshot.agents = { removed.snapshot.agents[1] }
herdr.normalize(removed, "local", identities)
assert(herdr.normalize(raw, "local", identities).agents[2].id ~= first.agents[2].id, "removed ephemeral occupant cannot inherit identity")
local invalid, err = herdr.decode("{bad")
assert(not invalid and err:find("invalid JSON"))
local failed, failure = herdr.decode('{"error":{"code":"agent_blocked","message":"needs approval"}}')
assert(not failed and failure:find("agent_blocked"))
assert(not herdr.normalize({}, "local", identities))

-- Exercise actions with a fake transport rather than controlling a live terminal.
local original_run, commands = process.run, {}
local action_raw = vim.deepcopy(raw)
local read_stdout = "Agent output is plain text.\nLatest response.\n"
process.run = function(argv, _, cb)
  commands[#commands + 1] = argv
  if vim.tbl_contains(argv, "read") then
    vim.schedule(function() cb(nil, { stdout = read_stdout, stderr = "", code = 0 }) end)
    return { cancel = function() end }
  end
  local response
  if vim.tbl_contains(argv, "snapshot") then response = action_raw
  elseif vim.tbl_contains(argv, "get") then response = { result = { type = "agent_info", agent = action_raw.snapshot.agents[1] } }
  else response = { result = { type = "ok" } } end
  vim.schedule(function() cb(nil, { stdout = vim.json.encode(response), stderr = "", code = 0 }) end)
  return { cancel = function() end }
end
local adapter = herdr.new({ herdr = { command = "herdr-test", machine = "remote-test" } })
local inv, ready
adapter:snapshot(function(error, value) assert(not error); inv, ready = value, true end)
assert(vim.wait(1000, function() return ready end))
assert(inv.agents[1].remote and inv.workspaces[1].remote)
local preview_text, preview_error, preview_done
adapter:read(inv.agents[1], function(e, text) preview_error, preview_text, preview_done = e, text, true end)
assert(vim.wait(1000, function() return preview_done end))
assert(not preview_error and preview_text == read_stdout, "text previews must not be decoded as JSON")
read_stdout = '{"status":"done","message":"literal agent output"}\n'
preview_done = false
adapter:read(inv.agents[1], function(e, text) preview_error, preview_text, preview_done = e, text, true end)
assert(vim.wait(1000, function() return preview_done end))
assert(not preview_error and preview_text == read_stdout, "JSON-looking terminal content must remain literal text")
local sent = false
adapter:prompt(inv.agents[1], "literal $(text)", function(error) assert(not error); sent = true end)
assert(vim.wait(1000, function() return sent end))
assert(commands[#commands][#commands[#commands]] == "literal $(text)")
for _, argv in ipairs(commands) do assert(argv[2] == "--machine" and argv[3] == "remote-test") end
action_raw.snapshot.agents[1].agent_status = "blocked"
local blocked
adapter:prompt(inv.agents[1], "must not send", function(error) blocked = error end)
assert(vim.wait(1000, function() return blocked ~= nil end))
assert(blocked:find("needs input") and commands[#commands][4] == "agent" and commands[#commands][5] == "get")
action_raw.snapshot.agents[1].agent_session.value = "replacement"
local replaced
adapter:focus(inv.agents[1], function(error) replaced = error end)
assert(vim.wait(1000, function() return replaced ~= nil end))
assert(replaced:find("occupant changed"))
local flag_error
local count = #commands
adapter:prompt(inv.agents[1], "--wait", function(error) flag_error = error end)
assert(flag_error and flag_error:find("introductory") and #commands == count)
adapter:stop()
local managed_env = vim.env.HERDR_ENV
vim.env.HERDR_ENV = nil
local standalone = herdr.new({ herdr = { command = "herdr-test" } })
local standalone_error, standalone_snapshot, standalone_done
standalone:snapshot(function(e, value) standalone_error, standalone_snapshot, standalone_done = e, value, true end)
vim.env.HERDR_ENV = managed_env
assert(vim.wait(1000, function() return standalone_done end))
assert(not standalone_error and standalone_snapshot, "standalone Neovim must be allowed to query the default session")
standalone:stop()
process.run = original_run

local function wait_command(argv, opts)
  local done, e, out = false
  process.run(argv, opts, function(err_, output) done, e, out = true, err_, output end)
  assert(vim.wait(5000, function() return done end), "process callback did not finish")
  return e, out
end
-- Literal shell metacharacters stay data because transport uses argv.
local payload = "`echo WRONG` $(echo WRONG) ; a\nb"
local e, out = wait_command({ "printf", "%s", payload })
assert(not e and out.stdout == payload)
local limit_err = wait_command({ "printf", "%s", string.rep("x", 4096) }, { max_bytes = 20 })
assert(limit_err and limit_err:find("limit"))
local timeout_err = wait_command({ "sleep", "2" }, { timeout = 20 })
assert(timeout_err and timeout_err:find("timed out"))
local missing_err = wait_command({ "/tmp/herde-nonexistent-program" })
assert(missing_err)
local cancelled, calls = false, 0
local handle = process.run({ "sleep", "2" }, {}, function(err_)
  calls = calls + 1
  assert(err_ == "cancelled")
  cancelled = true
end)
handle.cancel()
assert(vim.wait(2000, function() return cancelled end))
assert(calls == 1)
print("backend and transport checks passed")
