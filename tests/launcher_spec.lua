local h = require("tests.helpers")

describe("the Nix coil's launcher (nix/coil.sh)", function()
  local dir

  before_each(function()
    dir = h.tmpdir()
  end)

  ---nix/coil.sh with its placeholders filled in, as nix/coil.nix does
  ---@param nvim string
  ---@return string path
  local function launcher(nvim)
    local script = table.concat(vim.fn.readfile("nix/coil.sh"), "\n")
    script = script:gsub("@shell@", vim.fn.exepath("bash")):gsub("@nvim@", nvim)
    local path = dir .. "/coil"
    vim.fn.writefile(vim.split(script, "\n"), path)
    vim.fn.setfperm(path, "rwxr-xr-x")
    return path
  end

  describe("with a stand-in for Neovim", function()
    local coil

    before_each(function()
      -- Prints its environment, then one argument per line
      local stub = dir .. "/nvim"
      h.write(stub, {
        "#!/usr/bin/env bash",
        'echo "cwd_file=${COIL_CWD_FILE-unset}"',
        'echo "appname=${NVIM_APPNAME-unset} user_appname=${COIL_USER_NVIM_APPNAME-unset}"',
        'printf "%s\\n" "$@"',
      })
      vim.fn.setfperm(stub, "rwxr-xr-x")
      coil = launcher(stub)
    end)

    ---@param args string[]
    ---@return vim.SystemCompleted
    ---@param env? table<string, string>
    local function run(args, env)
      local cmd = { coil }
      vim.list_extend(cmd, args)
      return vim.system(cmd, { env = env }):wait(5000)
    end

    ---@param result vim.SystemCompleted
    ---@return string[]
    local function lines(result)
      assert.equals(0, result.code, result.stderr)
      return vim.split(result.stdout, "\n", { trimempty = true })
    end

    local standalone = {
      "--cmd",
      "let g:coil_standalone = 1",
      "--cmd",
      'let g:coil_editor_env = {"NVIM_APPNAME": $COIL_USER_NVIM_APPNAME}'
        .. " | unlet $COIL_USER_NVIM_APPNAME",
    }
    local env = "appname=coil user_appname="
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
        concat({ "cwd_file=unset", env }, standalone, { "a dir", "-R" }),
        lines(run({ "a dir", "-R" }))
      )
      assert.same(concat({ "cwd_file=unset", env }, standalone), lines(run({})))
    end)

    it("passes --cwd-file on through the environment, never in a command", function()
      local expected = concat({ "cwd_file=/tmp/it's x", env }, standalone, cwd, { "a" })
      assert.same(expected, lines(run({ "--cwd-file", "/tmp/it's x", "a" })))
      assert.same(expected, lines(run({ "a", "--cwd-file=/tmp/it's x" })))
    end)

    it("runs as its own Neovim app, keeping the user's for editors", function()
      assert.equals("appname=coil user_appname=mine", lines(run({}, { NVIM_APPNAME = "mine" }))[2])
    end)

    it("leaves everything after -- to Neovim", function()
      assert.same(
        concat({ "cwd_file=unset", env }, standalone, { "--", "--cwd-file" }),
        lines(run({ "--", "--cwd-file" }))
      )
    end)

    it("fails without a path after --cwd-file", function()
      local result = run({ "--cwd-file" })
      assert.equals(2, result.code)
      assert.truthy(result.stderr:find("--cwd-file needs a path", 1, true))
    end)
  end)

  it("makes Neovim write the last directory to the --cwd-file", function()
    vim.fn.mkdir(dir .. "/one")
    local out = dir .. "/report.json"
    local cwd_file = dir .. "/it's a cwd"
    local cmd = { launcher(vim.v.progpath), "--headless", "--clean" }
    vim.list_extend(cmd, { "-u", "tests/fixtures/standalone_init.lua", "--cwd-file", cwd_file })
    vim.list_extend(cmd, { "--", dir .. "/one" })
    local result = vim.system(cmd, { env = { COIL_TEST_OUT = out } }):wait(20000)
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
