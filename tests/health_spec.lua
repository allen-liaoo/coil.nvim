local cli = require("coil.cli")
local h = require("tests.helpers")
local uv = vim.uv or vim.loop

describe(":checkhealth coil", function()
  local dir, path, health

  before_each(function()
    dir = h.tmpdir()
    path = vim.env.PATH
    health = vim.health
  end)

  after_each(function()
    vim.env.PATH = path
    vim.health = health
  end)

  ---PATH with only `dir` and bash's directory (the check looks for bash)
  ---@param only string
  local function set_path(only)
    vim.env.PATH = only .. ":" .. vim.fn.fnamemodify(vim.fn.exepath("bash"), ":h")
  end

  ---The report, as "<kind>: <message>" lines, with advice after " -- "
  ---@return string[]
  local function check()
    local report = {}
    local function record(kind)
      return function(msg, advice)
        if type(advice) == "table" then
          advice = table.concat(advice, " ")
        end
        table.insert(report, kind .. ": " .. msg .. (advice and " -- " .. advice or ""))
      end
    end
    vim.health = setmetatable({}, {
      __index = function(_, kind)
        return record(kind)
      end,
    })
    require("coil.health").check()
    vim.health = health
    return report
  end

  ---The report's lines under the `coil` command's heading
  ---@return string[]
  local function command_section()
    local report = check()
    for i, line in ipairs(report) do
      if line == "start: coil: the `coil` command" then
        return vim.list_slice(report, i + 1)
      end
    end
    error("no command section in " .. vim.inspect(report))
  end

  it("checks the requirements", function()
    local report = check()
    assert.equals("start: coil", report[1])
    assert.equals("ok: Neovim " .. tostring(vim.version()), report[2])
    assert.equals("ok: oil.nvim is installed", report[3])
  end)

  it("says whether previews draw images", function()
    local coil = require("coil")
    coil.setup()
    assert.truthy(
      vim.tbl_contains(
        check(),
        "info: image.nvim isn't installed and set up, so previews of images, videos and PDFs show "
          .. "their details instead"
      )
    )
    coil.setup({ preview = { images = false } })
    assert.truthy(vim.tbl_contains(check(), "info: Turned off (preview.images = false)"))
    coil.setup()
  end)

  it("says how to get a `coil` command", function()
    set_path(dir)
    assert.same({
      "info: No `coil` on PATH. To use coil as a file manager from a shell, run :CoilInstallCli",
    }, command_section())
  end)

  it("knows a `coil` that runs this coil.nvim's launcher", function()
    local link = assert(cli.install(dir .. "/bin"))
    set_path(dir .. "/bin")
    assert.same({ "ok: `coil` runs this coil.nvim's " .. cli.launcher() }, command_section())
    assert.equals(cli.launcher(), uv.fs_readlink(link))
  end)

  it("points out another coil.nvim's launcher and other programs", function()
    local other = dir .. "/other/coil.nvim/bin/coil"
    h.write(dir .. "/other/coil.nvim/lua/coil/init.lua", { "" })
    h.write(other, { "#!/bin/sh" })
    vim.fn.setfperm(other, "rwxr-xr-x")
    vim.fn.mkdir(dir .. "/bin")
    assert(uv.fs_symlink(other, dir .. "/bin/coil"))
    set_path(dir .. "/bin")
    assert.same({
      string.format(
        "info: `coil` runs another coil.nvim's launcher, %s. Run :CoilInstallCli %s to link it to "
          .. "this coil.nvim",
        other,
        dir .. "/bin"
      ),
    }, command_section())

    h.write(dir .. "/nix/coil", { "#!/bin/sh" })
    vim.fn.setfperm(dir .. "/nix/coil", "rwxr-xr-x")
    set_path(dir .. "/nix")
    assert.same(
      { string.format("info: `coil` on PATH is %s, not this coil.nvim's", dir .. "/nix/coil") },
      command_section()
    )
  end)

  it("warns about broken links on PATH", function()
    vim.fn.mkdir(dir .. "/bin")
    assert(uv.fs_symlink(dir .. "/gone/bin/coil", dir .. "/bin/coil"))
    set_path(dir .. "/bin")
    assert.same({
      string.format(
        "warn: %s is a broken link (to %s) -- Run :CoilInstallCli %s to link it to this coil.nvim",
        dir .. "/bin/coil",
        dir .. "/gone/bin/coil",
        dir .. "/bin"
      ),
      "info: No `coil` on PATH. To use coil as a file manager from a shell, run :CoilInstallCli",
    }, command_section())
  end)
end)
