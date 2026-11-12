if vim.g.loaded_coil then
  return
end
vim.g.loaded_coil = true

vim.api.nvim_create_user_command("Coil", function(args)
  require("coil").open(args.args ~= "" and args.args or nil)
end, {
  nargs = "?",
  complete = "dir",
  desc = "Open the column view on a directory (default: the current buffer's)",
})

vim.api.nvim_create_user_command("CoilClose", function()
  require("coil").close()
end, { desc = "Close the column view" })

vim.api.nvim_create_user_command("CoilPreview", function()
  require("coil.split_preview").toggle()
end, { desc = "Toggle a preview split that follows the oil cursor" })
