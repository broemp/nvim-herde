if vim.g.loaded_herde then return end
vim.g.loaded_herde = true
require("herde").register_command()
