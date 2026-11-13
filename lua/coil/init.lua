-- coil's public Lua API. Every other module under coil.* is internal.
local M = {}

---@param opts? table See coil.Config
M.setup = function(opts)
  require("coil.config").setup(opts)
  require("coil.preview").setup(require("coil.config").get().preview)
end

---Whether Neovim was started as a file manager (bin/coil, or
---`nvim --cmd "let g:coil_standalone = 1"`). Known from the start, so your config can check it
---while it loads.
---@return boolean
M.standalone = function()
  return require("coil.config").standalone()
end

---Open the column view on `dirs`, one tab per directory (see :Coil)
---@param dirs? string|string[] Paths or oil URLs; nil means the current buffer's directory
M.open = function(dirs)
  require("coil.view").open(dirs)
end

---Close the current tab's column view (otherwise the one used most recently)
M.close = function()
  require("coil.view").close()
end

return M
