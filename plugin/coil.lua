if vim.g.loaded_coil then
  return
end
vim.g.loaded_coil = true

vim.api.nvim_create_user_command("Coil", function(args)
  require("coil").open(#args.fargs > 0 and args.fargs or nil)
end, {
  nargs = "*",
  complete = "dir",
  desc = "Open the column view on directories, one tab each (default: the current buffer's)",
})

vim.api.nvim_create_user_command("CoilClose", function()
  require("coil").close()
end, { desc = "Close the column view" })

vim.api.nvim_create_user_command("CoilPreview", function()
  require("coil.split_preview").toggle()
end, { desc = "Toggle a preview split that follows the oil cursor" })

vim.api.nvim_create_user_command("CoilClearCache", function()
  local count, bytes = require("coil.preview.thumbnail").clear_cache()
  vim.notify(string.format("[coil] Deleted %d thumbnails (%.1f MiB)", count, bytes / 1024 / 1024))
end, { desc = "Delete coil's cached image thumbnails" })

-- Started as a file manager (`nvim --cmd "let g:coil_standalone = 1"`)
if require("coil.config").standalone() then
  require("coil.startup").init()
end
