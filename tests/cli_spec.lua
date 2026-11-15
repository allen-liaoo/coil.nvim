local cli = require("coil.cli")
local h = require("tests.helpers")
local uv = vim.uv or vim.loop

describe(":CoilInstallCli", function()
  local dir, bin, launcher, path, notified, notify

  before_each(function()
    dir = h.tmpdir()
    bin = dir .. "/bin"
    launcher = cli.launcher()
    path = vim.env.PATH
    notify = vim.notify
    notified = {}
    vim.notify = function(msg, level)
      table.insert(notified, { msg = msg, level = level })
    end
  end)

  after_each(function()
    vim.env.PATH = path
    vim.notify = notify
  end)

  ---A launcher in another copy of coil.nvim
  ---@param root string
  ---@return string
  local function other_coil(root)
    h.write(root .. "/lua/coil/init.lua", { "" })
    h.write(root .. "/bin/coil", { "" })
    return root .. "/bin/coil"
  end

  it("is the plugin's own bin/coil", function()
    assert.equals(vim.fn.fnamemodify("bin/coil", ":p"), launcher)
  end)

  it("links the launcher into the directory, creating it", function()
    assert.equals(bin .. "/coil", cli.install(bin))
    assert.equals(launcher, uv.fs_readlink(bin .. "/coil"))
    -- Again: nothing to do
    local link, err, replaced = cli.install(bin)
    assert.equals(bin .. "/coil", link)
    assert.is_nil(err)
    assert.is_nil(replaced)
  end)

  it("replaces a broken link and a link to another coil.nvim", function()
    vim.fn.mkdir(bin, "p")
    assert(uv.fs_symlink(dir .. "/gone/bin/coil", bin .. "/coil"))
    local link, _, replaced = cli.install(bin)
    assert.equals(dir .. "/gone/bin/coil", replaced)
    assert.equals(launcher, uv.fs_readlink(assert(link)))

    assert(uv.fs_unlink(bin .. "/coil"))
    assert(uv.fs_symlink(other_coil(dir .. "/old/coil.nvim"), bin .. "/coil"))
    link, _, replaced = cli.install(bin)
    assert.equals(dir .. "/old/coil.nvim/bin/coil", replaced)
    assert.equals(launcher, uv.fs_readlink(assert(link)))
  end)

  it("leaves any other coil alone", function()
    h.write(bin .. "/coil", { "#!/bin/sh" })
    local link, err = cli.install(bin)
    assert.is_nil(link)
    assert.equals(bin .. "/coil already exists", err)

    assert(uv.fs_unlink(bin .. "/coil"))
    h.write(dir .. "/elsewhere/coil", { "#!/bin/sh" })
    assert(uv.fs_symlink(dir .. "/elsewhere/coil", bin .. "/coil"))
    link, err = cli.install(bin)
    assert.is_nil(link)
    assert.equals(
      string.format("%s already exists (a link to %s)", bin .. "/coil", dir .. "/elsewhere/coil"),
      err
    )
  end)

  it("refuses a coil.nvim in the Nix store", function()
    local orig = cli.launcher
    cli.launcher = function()
      return "/nix/store/abc-coil.nvim/bin/coil"
    end
    local ok, link, err = pcall(cli.install, bin)
    cli.launcher = orig
    assert.is_true(ok, link)
    assert.is_nil(link)
    assert.truthy(err:find("Nix store", 1, true))
    assert.is_nil(uv.fs_lstat(bin))
  end)

  it("says when `coil` wouldn't run the link", function()
    local link = assert(cli.install(bin))
    vim.env.PATH = dir .. "/empty"
    assert.equals(bin .. " isn't on PATH: add it in your shell's config", cli.path_problem(link))
    vim.env.PATH = bin .. ":" .. path
    assert.is_nil(cli.path_problem(link))
    -- Another coil first
    local other = other_coil(dir .. "/other")
    vim.fn.setfperm(other, "rwxr-xr-x")
    vim.env.PATH = dir .. "/other/bin:" .. bin
    assert.equals(
      string.format("`coil` runs %s, which comes first on PATH", other),
      cli.path_problem(link)
    )
  end)

  it("reports what it did", function()
    vim.env.PATH = bin .. ":" .. path
    vim.cmd.CoilInstallCli(bin)
    assert.same({
      {
        msg = string.format("[coil] %s links to %s", bin .. "/coil", launcher),
        level = vim.log.levels.INFO,
      },
    }, notified)

    notified = {}
    vim.env.PATH = dir .. "/empty"
    vim.cmd.CoilInstallCli(bin)
    assert.equals(vim.log.levels.WARN, notified[1].level)
    assert.truthy(notified[1].msg:find(", but " .. bin .. " isn't on PATH", 1, true))

    notified = {}
    h.write(dir .. "/taken/coil", { "" })
    vim.cmd.CoilInstallCli(dir .. "/taken")
    assert.same({
      { msg = "[coil] " .. dir .. "/taken/coil already exists", level = vim.log.levels.ERROR },
    }, notified)
  end)
end)
