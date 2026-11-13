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
  })
end

-- Icons in oil's icon column
if _G.MiniIcons == nil then
  require("mini.icons").setup()
end

-- image.nvim creates :ImageReport in its setup()
if vim.fn.exists(":ImageReport") ~= 2 then
  require("image").setup()
end

-- Neovim's default colour scheme draws keywords, types and numbers in the normal text colour, so
-- syntax-highlighted previews look almost plain
if vim.g.colors_name == nil then
  vim.cmd.colorscheme("habamax")
end
