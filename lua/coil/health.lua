-- :checkhealth coil
local uv = vim.uv or vim.loop
local M = {}

local function check_requirements()
  vim.health.start("coil")
  if vim.fn.has("nvim-0.10") == 1 then
    vim.health.ok("Neovim " .. tostring(vim.version()))
  else
    vim.health.error("coil needs Neovim 0.10 or newer")
  end
  if pcall(require, "oil") then
    vim.health.ok("oil.nvim is installed")
  else
    vim.health.error("oil.nvim isn't installed", "Install stevearc/oil.nvim")
  end
end

local function check_images()
  vim.health.start("coil: images in previews")
  -- The user's preview options, which default to images = true
  if require("coil.config").get().preview.images == false then
    return vim.health.info("Turned off (preview.images = false)")
  end
  if not require("coil.preview.image").available() then
    return vim.health.info(
      "image.nvim isn't installed and set up, so previews of images, videos and PDFs show their "
        .. "details instead"
    )
  end
  vim.health.ok("image.nvim is set up")
  local thumbnail = require("coil.preview.thumbnail")
  local missing = {
    image = "images are scaled from the original files while Neovim waits",
    video = "videos show their details instead",
    pdf = "PDFs show their details instead",
  }
  for _, kind in ipairs({ "image", "video", "pdf" }) do
    if thumbnail.available(kind) then
      vim.health.ok(thumbnail.tool_name(kind) .. " is installed")
    else
      vim.health.warn(
        string.format("%s isn't installed: %s", thumbnail.tool_name(kind), missing[kind])
      )
    end
  end
end

local function check_command()
  vim.health.start("coil: the `coil` command")
  local cli = require("coil.cli")
  local launcher = cli.launcher()
  -- Without bin/, so `coil` comes from Nix packages, which run their own bash
  local nix_build = vim.startswith(launcher, "/nix/store/") and not uv.fs_stat(launcher)
  if not nix_build then
    if vim.fn.executable(launcher) ~= 1 then
      vim.health.error(
        launcher .. " is missing or not executable",
        "Reinstall coil.nvim with a plugin manager that keeps file modes (git clones do)"
      )
    end
    if vim.fn.executable("bash") ~= 1 then
      vim.health.warn("bash isn't on PATH, and `coil` is a bash script")
    end
  end
  ---Advice for a `coil` link in PATH that should be this coil.nvim's
  ---@param link string
  ---@return string
  local function relink(link)
    if nix_build then
      return cli.nix_advice
    end
    local dir = vim.fn.fnamemodify(link, ":h")
    return string.format(
      "Run :CoilInstallCli %s to link it to this coil.nvim",
      vim.fn.fnameescape(dir)
    )
  end
  for _, broken in ipairs(cli.broken_links()) do
    vim.health.warn(
      string.format("%s is a broken link (to %s)", broken[1], broken[2]),
      relink(broken[1])
    )
  end

  local found = vim.fn.exepath("coil")
  if found == "" then
    return vim.health.info(
      "No `coil` on PATH. To use coil as a file manager from a shell, "
        .. (nix_build and cli.nix_advice or "run :CoilInstallCli")
    )
  end
  local real = uv.fs_realpath(found)
  if real == uv.fs_realpath(launcher) then
    vim.health.ok(string.format("`coil` runs this coil.nvim's %s", launcher))
  elseif real and cli.is_launcher(real) then
    -- Another install's (another plugin manager or NVIM_APPNAME), whose launcher may be older.
    -- It still starts the same `nvim`, so it isn't a warning.
    local msg = string.format("`coil` runs another coil.nvim's launcher, %s", real)
    vim.health.info(uv.fs_readlink(found) and msg .. ". " .. relink(found) or msg)
  else
    -- Such as the Nix `coil`, which wraps its own copy
    vim.health.info(string.format("`coil` on PATH is %s, not this coil.nvim's", found))
  end
end

M.check = function()
  check_requirements()
  check_images()
  check_command()
end

return M
