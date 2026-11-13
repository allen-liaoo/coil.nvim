local h = require("tests.helpers")

describe("bin/coil", function()
  local dir, stub

  before_each(function()
    dir = h.tmpdir()
    -- Stands in for nvim: prints $COIL_CWD_FILE, then one argument per line
    stub = dir .. "/nvim"
    h.write(stub, {
      "#!/usr/bin/env bash",
      'echo "cwd_file=${COIL_CWD_FILE-unset}"',
      'printf "%s\\n" "$@"',
    })
    vim.fn.setfperm(stub, "rwxr-xr-x")
  end)

  ---@param args string[]
  ---@param env? table<string, string>
  ---@return vim.SystemCompleted
  local function run(args, env)
    local cmd = { "bin/coil" }
    vim.list_extend(cmd, args)
    return vim
      .system(cmd, { env = vim.tbl_extend("force", { COIL_NVIM_PROGRAM = stub }, env or {}) })
      :wait(5000)
  end

  ---@param result vim.SystemCompleted
  ---@return string[]
  local function lines(result)
    assert.equals(0, result.code, result.stderr)
    return vim.split(result.stdout, "\n", { trimempty = true })
  end

  local standalone = { "--cmd", "let g:coil_standalone = 1" }

  it("starts Neovim in standalone mode with the other arguments", function()
    assert.same(
      vim.list_extend(
        { "cwd_file=unset" },
        vim.list_extend(vim.deepcopy(standalone), { "a dir", "-R" })
      ),
      lines(run({ "a dir", "-R" }))
    )
    assert.same(vim.list_extend({ "cwd_file=unset" }, standalone), lines(run({})))
  end)

  it("passes --cwd-file on as $COIL_CWD_FILE", function()
    local expected = vim.list_extend({ "cwd_file=/tmp/x y" }, vim.deepcopy(standalone))
    table.insert(expected, "a")
    assert.same(expected, lines(run({ "--cwd-file", "/tmp/x y", "a" })))
    assert.same(expected, lines(run({ "a", "--cwd-file=/tmp/x y" })))
  end)

  it("never passes on an inherited $COIL_CWD_FILE", function()
    assert.equals("cwd_file=unset", lines(run({}, { COIL_CWD_FILE = "/tmp/x" }))[1])
  end)

  it("leaves everything after -- to Neovim", function()
    local expected = vim.list_extend({ "cwd_file=unset" }, vim.deepcopy(standalone))
    vim.list_extend(expected, { "--", "--cwd-file" })
    assert.same(expected, lines(run({ "--", "--cwd-file" })))
  end)

  it("fails without a path after --cwd-file", function()
    local result = run({ "--cwd-file" })
    assert.equals(2, result.code)
    assert.truthy(result.stderr:find("--cwd-file needs a path", 1, true))
  end)
end)
