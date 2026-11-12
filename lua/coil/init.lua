local M = {}

---@param opts? table See coil.Config
M.setup = function(opts)
  require("coil.config").setup(opts)
  require("coil.preview").setup(require("coil.config").get().preview)
end

---Open the column view on `dir`, or switch to it if it is already open
---@param dir? string A path or oil URL; nil means the current buffer's directory
M.open = function(dir)
  require("coil.view").open(dir)
end

---Close the column view
M.close = function()
  require("coil.view").close()
end

return M
