-- Load this working copy of coil, plus the pinned oil.nvim and image.nvim, into whatever Neovim
-- runs this. Use with --cmd so it runs before plugin scripts load (see `make dev`):
--   nvim --cmd "luafile scripts/dev.lua"
local oil_path = os.getenv("COIL_OIL_PATH")
if not oil_path or oil_path == "" then
  error("COIL_OIL_PATH is not set; run inside `nix develop` (or direnv)")
end

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:append(oil_path)

-- image.nvim, for images in previews (optional: the dev shell provides it)
local image_path = os.getenv("COIL_IMAGE_PATH")
if image_path and image_path ~= "" then
  vim.opt.runtimepath:append(image_path)
  -- Set up like the standalone build (nix/defaults), unless your config set it up already. Your
  -- config runs after this file, so wait for it; this VimEnter runs before coil's own.
  vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    callback = function()
      -- image.nvim creates :ImageReport in its setup()
      if vim.fn.exists(":ImageReport") ~= 2 then
        require("image").setup({
          kitty_method = "unicode-placeholders",
          tmux_show_only_in_active_window = true,
        })
      end
    end,
  })
end

require("oil").setup()
require("coil").setup()
