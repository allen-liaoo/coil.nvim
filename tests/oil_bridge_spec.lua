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

  it("resolves the entries around the cursor, nearest first", function()
    for _, name in ipairs({ "a", "b", "c", "d", "e" }) do
      h.write(dir .. "/" .. name, { "" })
    end
    h.open_oil(dir)
    local win = vim.api.nvim_get_current_win()
    local function names(distance)
      return vim.tbl_map(function(target)
        return target.name
      end, bridge.targets_near(win, distance))
    end
    h.cursor_to(win, "c")
    assert.same({ "d", "b", "e", "a" }, names(2))
    assert.same({}, names(0))
    -- Lines past either end of the listing are skipped
    h.cursor_to(win, "a")
    assert.same({ "b", "c", "d" }, names(3))
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

  it("marks hidden entries, and lists an always_show entry even when hidden", function()
    h.write(dir .. "/.hidden", { "" })
    h.write(dir .. "/.other", { "" })
    h.write(dir .. "/a.txt", { "" })

    local _, entries = list("oil://" .. dir .. "/")
    assert.same(
      { "a.txt" },
      vim.tbl_map(function(e)
        return e.name
      end, assert(entries))
    )

    local done, result = false, nil
    bridge.list_dir("oil://" .. dir .. "/", function(_, r)
      done, result = true, r
    end, { always_show = ".hidden" })
    assert(h.wait(function()
      return done
    end))
    local hidden = {}
    for _, e in ipairs(assert(result)) do
      hidden[e.name] = e.is_hidden
    end
    assert.same({ [".hidden"] = true, ["a.txt"] = false }, hidden)

    require("oil.config").view_options.show_hidden = true
    _, entries = list("oil://" .. dir .. "/")
    hidden = {}
    for _, e in ipairs(assert(entries)) do
      hidden[e.name] = e.is_hidden
    end
    assert.same({ [".hidden"] = true, [".other"] = true, ["a.txt"] = false }, hidden)
  end)

  it("formats local directory URLs as paths for titles", function()
    local home = vim.fn.expand("~")
    assert.equals("~/x/", bridge.display_path("oil://" .. home .. "/x/"))
    assert.equals("/tmp/x/", bridge.display_path("oil:///tmp/x/"))
    assert.equals("oil-ssh://host/x/", bridge.display_path("oil-ssh://host/x/"))
  end)

  describe("remote files", function()
    after_each(function()
      h.setup_oil()
    end)

    it("are downloaded with scp, never asking for a password, with oil's scp arguments", function()
      h.setup_oil({ extra_scp_args = { "-O" } })
      assert.same({
        "scp",
        "-C",
        "-o",
        "BatchMode=yes",
        "-O",
        -- Escaped like oil's own scp URLs, slashes too
        "scp://me@host:2222/%2Fetc%2Fmy%20file",
        "/tmp/dest",
      }, bridge.fetch_command("oil-ssh://me@host:2222//etc/my file", "/tmp/dest"))
      -- Paths relative to the remote home, as oil has them
      assert.same(
        "scp://host/notes.txt",
        bridge.fetch_command("oil-ssh://host/notes.txt", "/tmp/dest")[6]
      )
    end)

    it("are downloaded with aws s3 cp from S3, with oil's s3 arguments", function()
      h.setup_oil({ extra_s3_args = { "--profile", "p" } })
      local url = (vim.fn.has("nvim-0.12") == 1 and "oil-s3://" or "oil-sss://") .. "bucket/a/b.txt"
      assert.same(
        { "aws", "s3", "cp", "s3://bucket/a/b.txt", "/tmp/dest", "--profile", "p" },
        bridge.fetch_command(url, "/tmp/dest")
      )
    end)

    it("have no downloader for local files, the trash or unknown schemes", function()
      assert.is_nil(bridge.fetcher("oil://" .. dir .. "/a.txt"))
      assert.is_nil(bridge.fetcher("oil-trash:///a.txt"))
      assert.is_nil(bridge.fetcher("https://example.com/a.txt"))
      assert.is_function(bridge.fetcher("oil-ssh://host//a.txt"))
    end)

    it("get their size and modification time from oil's listing", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(bufnr, "oil-ssh://host//srv/")
      local target = bridge.entry_target(bufnr, {
        name = "a.txt",
        type = "file",
        id = 1,
        meta = { size = 42, iso_modified_date = "2026-11-14 10:00" },
      })
      assert.equals("oil-ssh://host//srv/a.txt", target.url)
      assert.is_nil(target.path)
      assert.equals(42, target.size)
      assert.equals("2026-11-14 10:00", target.mtime)
      -- A link's size is its target's
      local link = bridge.entry_target(bufnr, {
        name = "l",
        type = "link",
        id = 2,
        meta = { size = 5, link_stat = { type = "file", size = 900 } },
      })
      assert.equals(900, link.size)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
