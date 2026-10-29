local M = {}
function M.create(opts)
  local backend = opts.backend or "herdr"
  if type(backend) == "table" then return backend end
  assert(backend == "herdr" or backend == "demo", "Unsupported Herde backend: " .. tostring(backend))
  return require("herde.backends." .. backend).new(opts)
end
return M
