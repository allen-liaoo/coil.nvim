-- Load this working copy of coil, plus the pinned oil.nvim, image.nvim and oil-git-status.nvim,
-- into whatever Neovim runs this. Use with --cmd so it runs before plugin scripts load (see
-- `make dev`):
--   nvim --cmd "luafile scripts/dev.lua"
local oil_path = os.getenv("COIL_OIL_PATH")
if not oil_path or oil_path == "" then
  error("COIL_OIL_PATH is not set; run inside `nix develop` (or direnv)")
end

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:append(oil_path)

---An optional plugin the dev shell provides, added to the runtimepath
---@param env string
---@return boolean added
local function add_optional(env)
  local path = os.getenv(env)
  if not path or path == "" then
    return false
  end
  vim.opt.runtimepath:append(path)
  return true
end

local images = add_optional("COIL_IMAGE_PATH")
local git_status = add_optional("COIL_OIL_GIT_STATUS_PATH")

-- Set up the optional plugins like the standalone build (nix/defaults), unless your config set them
-- up already. Your config runs after this file, so wait for it; this VimEnter runs before coil's own.
vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    -- image.nvim creates :ImageReport in its setup()
    if images and vim.fn.exists(":ImageReport") ~= 2 then
      require("image").setup({
        kitty_method = "unicode-placeholders",
        tmux_show_only_in_active_window = true,
      })
    end
    -- oil-git-status needs room for its two signs, which oil's signcolumn may not leave
    local signcolumn = require("oil.config").win_options.signcolumn or ""
    if
      git_status
      and not package.loaded["oil-git-status"]
      and (vim.startswith(signcolumn, "yes") or vim.startswith(signcolumn, "auto"))
    then
      require("oil-git-status").setup()
      -- It decorates oil buffers as oil finishes them (OilEnter); some may be done already
      for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.b[bufnr].oil_ready then
          vim.api.nvim_exec_autocmds("User", { pattern = "OilEnter", data = { buf = bufnr } })
        end
      end
    end
  end,
})

-- With oil-git-status, two sign columns for its index and working-tree signs
require("oil").setup(git_status and { win_options = { signcolumn = "yes:2" } } or nil)
require("coil").setup()
