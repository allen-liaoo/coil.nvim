local bridge = require("coil.oil_bridge")
local h = require("tests.helpers")

describe("oil_bridge", function()
  local dir

  before_each(function()
    h.reset_tab()
    h.setup_oil()
    dir = h.tmpdir()
  end)

  ---@param url string
  ---@return string|nil err
  ---@return coil.ListEntry[]|nil entries
  local function list(url)
    local done, err, entries = false, nil, nil
    bridge.list_dir(url, function(e, result)
      done, err, entries = true, e, result
    end)
    assert(h.wait(function()
      return done
    end))
    return err, entries
  end

  it("lists like oil: hidden files filtered, directories first, natural order", function()
    h.write(dir .. "/file10.txt", { "" })
    h.write(dir .. "/file2.txt", { "" })
    h.write(dir .. "/.hidden", { "" })
    vim.fn.mkdir(dir .. "/sub")
    assert((vim.uv or vim.loop).fs_symlink(dir .. "/sub", dir .. "/linkdir"))

    local err, entries = list("oil://" .. dir .. "/")
    assert.is_nil(err)
    assert(entries)
    assert.same(
      { "linkdir", "sub", "file2.txt", "file10.txt" },
      vim.tbl_map(function(e)
        return e.name
      end, entries)
    )
    assert.same(
      { true, true, false, false },
      vim.tbl_map(function(e)
        return e.is_dir
      end, entries)
    )
    assert.equals("link", entries[1].type)
  end)

  it("does not add listed entries to oil's cache", function()
    h.write(dir .. "/a.txt", { "" })
    list("oil://" .. dir .. "/")
    assert.same({}, require("oil.cache").list_url("oil://" .. dir .. "/"))
  end)

  it("lists a missing directory as empty", function()
    local err, entries = list("oil://" .. dir .. "/nope/")
    assert.is_nil(err)
    assert.same({}, entries)
  end)

  it("errors for URLs without an oil adapter", function()
    local err = list("nope://x/")
    assert.truthy(err:match("No oil adapter"))
  end)

  it("resolves the entry under an oil window's cursor", function()
    h.write(dir .. "/a.txt", { "" })
    vim.fn.mkdir(dir .. "/sub")
    h.open_oil(dir)
    local win = vim.api.nvim_get_current_win()

    h.cursor_to(win, "a.txt")
    local target = assert(bridge.cursor_target(win))
    assert.equals("a.txt", target.name)
    assert.equals(dir .. "/a.txt", target.path)
    assert.is_false(target.is_dir)
    assert.is_false(target.unsaved)

    h.cursor_to(win, "sub/")
    target = assert(bridge.cursor_target(win))
    assert.is_true(target.is_dir)
    assert.equals("oil://" .. dir .. "/sub/", target.url)
  end)

  it("marks entries typed but not yet saved", function()
    local bufnr = h.open_oil(dir)
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "new.txt" })
    h.cursor_to(win, "new.txt")
    local target = assert(bridge.cursor_target(win))
    assert.is_true(target.unsaved)
  end)

  it("returns nil outside oil buffers", function()
    assert.is_nil(bridge.cursor_target(vim.api.nvim_get_current_win()))
  end)
end)
