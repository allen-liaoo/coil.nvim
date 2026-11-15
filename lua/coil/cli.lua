-- Internal. :CoilInstallCli: puts the plugin's `coil` command (bin/coil) on PATH as a symlink, so
-- it follows the plugin through updates.
local uv = vim.uv or vim.loop
local M = {}

---The plugin's bin/coil
---@return string
M.launcher = function()
  local source = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(source, ":p:h:h:h") .. "/bin/coil"
end

---Whether the link's target may be replaced: it's gone (the plugin moved, for example to another
---plugin manager), or it's another copy of coil.nvim's launcher
---@param target string
---@return boolean
local function replaceable(target)
  if not uv.fs_stat(target) then
    return true
  end
  return vim.fn.fnamemodify(target, ":h:t") == "bin"
    and uv.fs_stat(vim.fn.fnamemodify(target, ":h:h") .. "/lua/coil/init.lua") ~= nil
end

---Link `<dir>/coil` to the launcher, creating `dir` if needed. Replaces only a broken link or a
---link to another coil.nvim's launcher.
---@param dir? string Default: ~/.local/bin
---@return nil|string link, nil|string err, nil|string replaced The old link's target
M.install = function(dir)
  if vim.fn.has("win32") == 1 then
    return nil, "coil's command is a bash script, which doesn't run on Windows"
  end
  local launcher = M.launcher()
  if vim.startswith(launcher, "/nix/store/") then
    return nil,
      "coil.nvim is in the Nix store, where its path changes with every update, so a link to it "
        .. "would break. Put its bin/ on PATH with Nix instead"
  end
  if vim.fn.executable(launcher) ~= 1 then
    return nil, launcher .. " is missing or not executable"
  end
  dir = vim.fn.fnamemodify(vim.fs.normalize(dir or "~/.local/bin"), ":p"):gsub("/$", "")
  local link = dir .. "/coil"
  local replaced = uv.fs_readlink(link)
  if replaced then
    if replaced == launcher then
      return link
    end
    -- A relative target is relative to the link's directory
    local target = vim.startswith(replaced, "/") and replaced or dir .. "/" .. replaced
    if not replaceable(target) then
      return nil, string.format("%s already exists (a link to %s)", link, replaced)
    end
    assert(uv.fs_unlink(link))
  elseif uv.fs_lstat(link) then
    return nil, link .. " already exists"
  end
  vim.fn.mkdir(dir, "p")
  local ok, err = uv.fs_symlink(launcher, link)
  if not ok then
    return nil, err
  end
  return link, nil, replaced
end

---Why `coil` in a shell wouldn't run the link: its directory isn't on PATH, or another `coil`
---comes first. Nil when it would.
---@param link string
---@return nil|string
M.path_problem = function(link)
  local found = vim.fn.exepath("coil")
  if found == "" then
    return vim.fn.fnamemodify(link, ":h") .. " isn't on PATH: add it in your shell's config"
  end
  if uv.fs_realpath(found) ~= uv.fs_realpath(link) then
    return string.format("`coil` runs %s, which comes first on PATH", found)
  end
end

return M
