local specs = dofile("install/herde.lua")
local github = dofile("examples/github.lua")
assert(github[1] == "broemp/nvim-herde" and github.dir == nil and github.main == "herde", "GitHub spec must install the public repository")
local herde, claude, herdr = unpack(specs)
assert(#github.keys == #herde.keys, "GitHub and local examples must expose the same shortcuts")
for i, mapping in ipairs(herde.keys) do
  assert(mapping[1] == github.keys[i][1] and vim.deep_equal(mapping.mode, github.keys[i].mode))
end
assert(herde.name == "herde.nvim" and herde.main == "herde" and herde.cmd == "Herde")
assert(herde.opts.picker == "snacks", "local install must use existing Snacks")
for _, dep in ipairs(herde.dependencies or {}) do
  assert((type(dep) == "table" and dep[1] or dep) ~= "ibhagwan/fzf-lua", "local install must not require fzf-lua")
end
assert(claude[1] == "coder/claudecode.nvim" and claude.enabled == false)
assert(herdr[1] == "ChmaraX/herdr-nvim" and herdr.opts.prefix == "<leader>aR")
local occupied = {}
local function register(mode, key)
  local id = mode .. ":" .. key
  assert(not occupied[id], "Duplicate mapping: " .. id)
  occupied[id] = true
end
for _, mapping in ipairs(herde.keys) do
  local modes = mapping.mode or "n"
  for _, mode in ipairs(type(modes) == "table" and modes or { modes }) do register(mode, mapping[1]) end
  assert(mapping.desc and mapping[1]:find("^<leader>a"))
end
-- Verified installed Herdr defaults: comments, list, paste, submit, reference.
for _, entry in ipairs({ {"n", "c"}, {"x", "c"}, {"n", "l"}, {"n", "s"}, {"n", "S"}, {"n", "i"}, {"x", "i"} }) do
  register(entry[1], herdr.opts.prefix .. entry[2])
end
local opts = { spec = {} }
herde.specs[1].opts(nil, opts)
assert(opts.spec[1].group == "agents" and opts.spec[2].group == "Herdr comments")
print("Local naming and keymap checks passed")
