local M = {}

---@param opts? table See coil.Config
M.setup = function(opts)
  require("coil.config").setup(opts)
  require("coil.preview").setup(require("coil.config").get().preview)
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
