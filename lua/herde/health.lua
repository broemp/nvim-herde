local M = {}
function M.check()
  vim.health.start("herde.nvim")
  if vim.fn.has("nvim-0.10") == 1 then vim.health.ok("Neovim 0.10+ available")
  else vim.health.error("Neovim 0.10 or newer is required") end
  local ctx = require("herde").get_context()
  local c = ctx and ctx.config or require("herde.config").defaults
  if (c.picker == "auto" or c.picker == "snacks") and require("herde.integrations.snacks").available() then
    vim.health.ok("Using Snacks Picker")
  elseif c.picker == "snacks" then
    vim.health.warn("Snacks Picker unavailable; using vim.ui.select")
  elseif c.picker == "auto" or c.picker == "fzf-lua" then
    if require("herde.integrations.fzf").available() then vim.health.ok("fzf-lua and fzf available")
    elseif c.picker == "fzf-lua" then vim.health.error("Install ibhagwan/fzf-lua and the fzf executable")
    else vim.health.info("fzf-lua unavailable; using vim.ui.select") end
  end
  if ctx and ctx.persistence then
    if ctx.persistence.error then vim.health.warn(ctx.persistence.error)
    elseif not ctx.persistence.writable then vim.health.warn("Another Neovim instance owns metadata; changes here are temporary")
    else vim.health.ok("Metadata writer lock acquired") end
  end
  if c.backend == "demo" then vim.health.info("Demo backend: no live agents controlled"); return end
  if type(c.backend) == "table" then vim.health.info("Custom backend configured"); return end
  if vim.fn.executable(c.herdr.command) == 1 then vim.health.ok("Herdr executable found")
  else vim.health.error("Herdr executable missing: " .. c.herdr.command) end
  if vim.env.HERDR_ENV ~= "1" and not c.herdr.machine and not c.herdr.session then
    vim.health.info("Standalone Neovim: using Herdr's default session. Set herdr.session for a named session.")
  end
  if ctx and ctx.store.stale then vim.health.warn("Backend unavailable: " .. tostring(ctx.store.error))
  elseif ctx then vim.health.ok("Backend snapshot available or initial refresh pending") end
  vim.health.info("Direct Pi RPC is not required: Pi agents are discovered through Herdr")
end
return M
