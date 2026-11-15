local h = require("tests.helpers")

describe("the launcher (bin/coil)", function()
  local dir
  local launcher = vim.fn.fnamemodify("bin/coil", ":p")

  before_each(function()
    dir = h.tmpdir()
  end)

  describe("with a stand-in for Neovim", function()
    local stub

    before_each(function()
      -- Prints its environment, then one argument per line
      stub = dir .. "/nvim"
      h.write(stub, {
        "#!/usr/bin/env bash",
        'echo "cwd_file=${COIL_CWD_FILE-unset}"',
        'echo "appname=${NVIM_APPNAME-unset} user_appname=${COIL_USER_NVIM_APPNAME-unset}"',
        'echo "launcher_env=${COIL_NVIM-unset} ${COIL_APPNAME-unset}"',
        'printf "%s\\n" "$@"',
      })
      vim.fn.setfperm(stub, "rwxr-xr-x")
    end)

    ---@param args string[]
    ---@param opts? { env?: table<string, string>, cwd?: string }
    ---@return vim.SystemCompleted
    local function run(args, opts)
      opts = opts or {}
      local cmd = { launcher }
      vim.list_extend(cmd, args)
      local env =
        vim.tbl_extend("force", { COIL_NVIM = stub, NVIM_APPNAME = "mine" }, opts.env or {})
      return vim.system(cmd, { env = env, cwd = opts.cwd }):wait(5000)
    end

    ---@param result vim.SystemCompleted
    ---@return string[]
    local function lines(result)
      assert.equals(0, result.code, result.stderr)
      return vim.split(result.stdout, "\n", { trimempty = true })
    end

    -- Neither COIL_NVIM nor COIL_APPNAME reaches Neovim
    local env = { "appname=mine user_appname=unset", "launcher_env=unset unset" }
    local standalone = { "--cmd", "let g:coil_standalone = 1" }
    local cwd = { "--cmd", "let g:coil_cwd_file = $COIL_CWD_FILE | unlet $COIL_CWD_FILE" }

    ---@param ... string[]
    ---@return string[]
    local function concat(...)
      local ret = {}
      for _, list in ipairs({ ... }) do
        vim.list_extend(ret, list)
      end
      return ret
    end

    it("starts Neovim in standalone mode with the other arguments", function()
      assert.same(
        concat({ "cwd_file=unset" }, env, standalone, { "a dir", "-R" }),
        lines(run({ "a dir", "-R" }))
      )
      assert.same(concat({ "cwd_file=unset" }, env, standalone), lines(run({})))
    end)

    it("runs as COIL_APPNAME, keeping the user's NVIM_APPNAME for editors", function()
      assert.same(
        concat(
          { "cwd_file=unset", "appname=coil user_appname=mine", "launcher_env=unset unset" },
          standalone,
          {
            "--cmd",
            'let g:coil_editor_env = {"NVIM_APPNAME": $COIL_USER_NVIM_APPNAME}'
              .. " | unlet $COIL_USER_NVIM_APPNAME",
          }
        ),
        lines(run({}, { env = { COIL_APPNAME = "coil" } }))
      )
    end)

    it("passes --cwd-file on through the environment, never in a command", function()
      local expected = concat({ "cwd_file=/tmp/it's x" }, env, standalone, cwd, { "a" })
      assert.same(expected, lines(run({ "--cwd-file", "/tmp/it's x", "a" })))
      assert.same(expected, lines(run({ "a", "--cwd-file=/tmp/it's x" })))
    end)

    it("makes a relative --cwd-file absolute", function()
      local cwd_file = vim.uv.fs_realpath(dir) .. "/it's x"
      assert.equals(
        "cwd_file=" .. cwd_file,
        lines(run({ "--cwd-file", "it's x" }, { cwd = dir }))[1]
      )
    end)

    it("leaves everything after -- to Neovim", function()
      assert.same(
        concat({ "cwd_file=unset" }, env, standalone, { "--", "--cwd-file", "--help" }),
        lines(run({ "--", "--cwd-file", "--help" }))
      )
    end)

    it("fails without a path after --cwd-file", function()
      for _, args in ipairs({ { "--cwd-file" }, { "--cwd-file=" }, { "--cwd-file", "" } }) do
        local result = run(args)
        assert.equals(2, result.code)
        assert.truthy(result.stderr:find("--cwd-file needs a path", 1, true))
      end
    end)

    it("prints its help and version without starting Neovim", function()
      for _, flag in ipairs({ "-h", "--help" }) do
        local out = lines(run({ "a", flag }))
        assert.equals("Usage: coil [options] [directory...]", out[1])
      end
      for _, flag in ipairs({ "-v", "--version" }) do
        assert.same({ "coil 0-unstable" }, lines(run({ flag })))
      end
    end)
  end)

  it("makes Neovim write the last directory to the --cwd-file", function()
    vim.fn.mkdir(dir .. "/one")
    local out = dir .. "/report.json"
    local cwd_file = dir .. "/it's a cwd"
    local cmd = { launcher, "--headless", "--clean" }
    vim.list_extend(cmd, { "-u", "tests/fixtures/standalone_init.lua", "--cwd-file", cwd_file })
    vim.list_extend(cmd, { "--", dir .. "/one" })
    local result = vim
      .system(cmd, {
        env = { COIL_NVIM = vim.v.progpath, COIL_APPNAME = "coil", COIL_TEST_OUT = out },
      })
      :wait(20000)
    assert.equals(0, result.code, result.stderr)
    local report = vim.json.decode(table.concat(vim.fn.readfile(out), "\n"))
    assert.equals(cwd_file, report.cwd_file)
    -- Copied and removed, so Neovims started from this one (:terminal) don't inherit it
    assert.equals(vim.NIL, report.cwd_file_env)
    -- Editors get the user's NVIM_APPNAME back (none here), and the copy is gone too
    assert.same({ NVIM_APPNAME = "" }, report.editor_env)
    assert.equals(vim.NIL, report.user_appname_env)
    assert.equals(dir .. "/one", table.concat(vim.fn.readfile(cwd_file, "b"), "\n"))
  end)
end)
