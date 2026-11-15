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

vim.api.nvim_create_user_command("CoilInstallCli", function(args)
  local cli = require("coil.cli")
  local link, err, replaced = cli.install(args.fargs[1])
  if not link then
    return vim.notify("[coil] " .. err, vim.log.levels.ERROR)
  end
  local msg = string.format("[coil] %s links to %s", link, cli.launcher())
  if replaced then
    msg = msg .. string.format(" (it linked to %s)", replaced)
  end
  local problem = cli.path_problem(link)
  if problem then
    msg = msg .. ", but " .. problem
  end
  vim.notify(msg, problem and vim.log.levels.WARN or vim.log.levels.INFO)
end, {
  nargs = "?",
  complete = "dir",
  desc = "Put the `coil` command on PATH: a link to it in ~/.local/bin (or the given directory)",
})

-- Started as a file manager (`nvim --cmd "let g:coil_standalone = 1"`)
if require("coil.config").standalone() then
  require("coil.startup").init()
end
