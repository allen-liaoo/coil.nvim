-- Headless test bootstrap. The Nix dev shell exports the dependency paths.

---@param name string
---@return string
local function require_env(name)
  local value = os.getenv(name)
  if not value or value == "" then
    error(string.format("%s is not set; run tests inside `nix develop` (or direnv)", name))
  end
  return value
end

vim.opt.runtimepath:prepend(".")
vim.opt.runtimepath:append(require_env("COIL_OIL_PATH"))
vim.opt.runtimepath:append(require_env("COIL_PLENARY_PATH"))
vim.cmd.runtime("plugin/plenary.vim")

vim.o.swapfile = false
