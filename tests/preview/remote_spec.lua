local h = require("tests.helpers")
local preview = require("coil.preview")
local remote = require("coil.preview.remote")
local uv = vim.uv or vim.loop

describe("remote previews", function()
  local dir, win
  -- What the fake remote holds, by URL
  ---@type table<string, string>
  local files
  ---@type {url: string, dest: string, cb: fun(err?: string), cancelled: boolean}[]
  local fetches

  ---Copy the fake remote file into `dest` and finish the download
  local function complete(fetch)
    local data = files[fetch.url]
    if data then
      h.write_bytes(fetch.dest, data)
      fetch.cb()
    else
      fetch.cb("No such file\nsecond line")
    end
  end

  ---A fetch that waits for complete()
  ---@type coil.Fetch
  local function slow_fetch(url, dest, cb)
    local fetch = { url = url, dest = dest, cb = cb, cancelled = false }
    table.insert(fetches, fetch)
    return function()
      fetch.cancelled = true
    end
  end

  ---@type coil.Fetch
  local function fetch_now(url, dest, cb)
    slow_fetch(url, dest, cb)
    complete(fetches[#fetches])
  end

  ---@param name string
  ---@param size? integer
  ---@return coil.PreviewTarget
  local function target(name, size)
    return { name = name, url = "oil-ssh://host/" .. name, is_dir = false, size = size }
  end

  ---@param t coil.PreviewTarget
  ---@param opts? table
  local function show(t, opts)
    preview.show(
      win,
      t,
      vim.tbl_extend(
        "force",
        { fetch = fetch_now, remote_delay_ms = 0, images = false },
        opts or {}
      )
    )
  end

  ---@param lines string[]
  local function wait_for(lines)
    h.wait(function()
      return vim.deep_equal(lines, h.win_lines(win))
    end)
    assert.same(lines, h.win_lines(win))
  end

  before_each(function()
    h.reset_tab()
    preview.setup()
    remote.clear()
    dir = h.tmpdir()
    win = vim.api.nvim_get_current_win()
    files = {}
    fetches = {}
  end)

  it("says when nothing can download remote files", function()
    preview.show(win, target("r.txt"))
    assert.same({ "No downloader configured for remote files" }, h.win_lines(win))
  end)

  it("downloads a text file and shows it", function()
    files["oil-ssh://host/r.lua"] = "local x = 1\n"
    show(target("r.lua"), { fetch = slow_fetch })
    assert.same({ "Downloading..." }, h.win_lines(win))
    h.wait(function()
      return #fetches == 1
    end)
    complete(fetches[1])
    wait_for({ "local x = 1" })
    -- The copy keeps the file's name, for filetype detection
    assert.equals("r.lua", vim.fs.basename(assert(remote.cached(target("r.lua")))))
  end)

  it("shows binary content and errors like local files", function()
    files["oil-ssh://host/blob"] = "ab\0cd"
    show(target("blob"))
    wait_for({ "No preview for binary files" })
    show(target("missing.txt"))
    wait_for({ "Cannot download: No such file" })
  end)

  it("reuses a copy until the file's size changes", function()
    files["oil-ssh://host/r.txt"] = "one"
    show(target("r.txt", 3))
    wait_for({ "one" })
    files["oil-ssh://host/r.txt"] = "two!"
    show(target("r.txt", 3))
    -- Straight from the copy, without a download
    assert.same({ "one" }, h.win_lines(win))
    assert.equals(1, #fetches)
    show(target("r.txt", 4))
    wait_for({ "two!" })
    assert.equals(2, #fetches)
  end)

  it("doesn't download files the extension or size rule out", function()
    show(target("song.mp3"))
    assert.same({ "No preview for audio files" }, h.win_lines(win))
    show(target("big.txt", 10), { max_bytes = 4 })
    assert.same({ "Larger than 4, so the text isn't shown" }, h.win_lines(win))
    show(target("photo.png"))
    assert.same({ "Image previews are off" }, h.win_lines(win))
    vim.wait(50)
    assert.equals(0, #fetches)
  end)

  it("never downloads files the cursor only passed over", function()
    show(target("a.txt"), { fetch = slow_fetch, remote_delay_ms = 50 })
    show(target("b.txt"), { fetch = slow_fetch, remote_delay_ms = 50 })
    h.wait(function()
      return #fetches == 1
    end)
    vim.wait(100)
    assert.equals(1, #fetches)
    assert.equals("oil-ssh://host/b.txt", fetches[1].url)
  end)

  it("stops a download for another file, but not for a redraw of the same one", function()
    files["oil-ssh://host/a.txt"] = "a"
    show(target("a.txt"), { fetch = slow_fetch })
    h.wait(function()
      return #fetches == 1
    end)
    -- Shown again: waits for the same download
    show(target("a.txt"), { fetch = slow_fetch })
    vim.wait(50)
    assert.equals(1, #fetches)
    assert.is_false(fetches[1].cancelled)

    show(target("b.txt"), { fetch = slow_fetch })
    h.wait(function()
      return #fetches == 2
    end)
    assert.is_true(fetches[1].cancelled)
    -- A late result for the old file doesn't replace the preview, and its part file is removed
    complete(fetches[1])
    assert.same({ "Downloading..." }, h.win_lines(win))
    assert.is_nil(uv.fs_stat(fetches[1].dest))
  end)

  it("stops a download when a local file is shown instead", function()
    show(target("a.txt"), { fetch = slow_fetch })
    h.wait(function()
      return #fetches == 1
    end)
    h.write(dir .. "/l.txt", { "local" })
    preview.show(
      win,
      { name = "l.txt", url = dir .. "/l.txt", path = dir .. "/l.txt", is_dir = false }
    )
    assert.is_true(fetches[1].cancelled)
  end)

  it("deletes the least recently used copies past the size limit", function()
    preview.setup({ remote_cache_mb = 5 / 1024 / 1024 })
    files["oil-ssh://host/a.txt"] = "aaa"
    files["oil-ssh://host/b.txt"] = "bbb"
    show(target("a.txt"))
    wait_for({ "aaa" })
    local copy_a = assert(remote.cached(target("a.txt")))
    show(target("b.txt"))
    wait_for({ "bbb" })
    assert.is_nil(remote.cached(target("a.txt")))
    assert.is_nil(uv.fs_stat(copy_a))
    assert.truthy(remote.cached(target("b.txt")))
  end)
end)
