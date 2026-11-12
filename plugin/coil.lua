if vim.g.loaded_coil then
  return
end
vim.g.loaded_coil = true

vim.api.nvim_create_user_command("CoilPreview", function()
  require("coil.split_preview").toggle()
end, { desc = "Toggle a preview split that follows the oil cursor" })
