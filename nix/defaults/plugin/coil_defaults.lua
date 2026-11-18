-- The Nix `coil` build's defaults. Runs after ~/.config/coil/init.lua, like any plugin script, and
-- sets up the bundled plugins that it didn't set up itself.

-- oil.nvim creates :Oil in its setup()
if vim.fn.exists(":Oil") ~= 2 then
  require("oil").setup({
    -- Deleting a line and saving moves the file to the trash, which oil's trash view (g\) can
    -- restore from
    delete_to_trash = true,
    -- Permissions, size and modification time next to each name
    columns = { "icon", "permissions", "size", "mtime" },
    -- Files changed outside Neovim show up in every pane (local directories)
    watch_for_changes = true,
    -- Two sign columns, for oil-git-status's index and working-tree signs
    win_options = { signcolumn = "yes:2" },
  })
end

-- Git status signs next to each entry (in a git repository). They need room in the sign column,
-- which an oil set up by init.lua may not leave.
local signcolumn = require("oil.config").win_options.signcolumn or ""
if
  not package.loaded["oil-git-status"]
  and (vim.startswith(signcolumn, "yes") or vim.startswith(signcolumn, "auto"))
then
  require("oil-git-status").setup()
end

-- Counts of LSP diagnostics next to each entry, from files open with a language server attached
if not package.loaded["oil-lsp-diagnostics"] then
  require("oil-lsp-diagnostics").setup()
end

-- Icons in oil's icon column
if _G.MiniIcons == nil then
  require("mini.icons").setup()
end

-- image.nvim creates :ImageReport in its setup()
if vim.fn.exists(":ImageReport") ~= 2 then
  -- For tmux (the README has these too): kitty's default, cursor-based method lands images at the
  -- cursor there, and images show only in the active tmux window
  require("image").setup({
    kitty_method = "unicode-placeholders",
    tmux_show_only_in_active_window = true,
  })
end

-- Neovim's default colour scheme draws keywords, types and numbers in the normal text colour, so
-- syntax-highlighted previews look almost plain
if vim.g.colors_name == nil then
  vim.cmd.colorscheme("habamax")
end
