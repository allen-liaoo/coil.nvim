-- Load this working copy of coil, plus the pinned oil.nvim, into whatever Neovim runs this.
-- Use with --cmd so it runs before plugin scripts load (see `make dev`):
--   nvim --cmd "luafile scripts/dev.lua"
local oil_path = os.getenv("COIL_OIL_PATH")
if not oil_path or oil_path == "" then
  error("COIL_OIL_PATH is not set; run inside `nix develop` (or direnv)")
end

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:append(oil_path)

require("oil").setup()
require("coil").setup()
