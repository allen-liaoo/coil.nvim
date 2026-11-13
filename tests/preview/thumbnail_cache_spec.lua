local h = require("tests.helpers")
local thumbnail = require("coil.preview.thumbnail")
local uv = vim.uv or vim.loop

describe("thumbnail cache limit", function()
  local dir, cache

  ---@param max_bytes integer|false
  local function setup(max_bytes)
    thumbnail.setup({ dir = cache, max_bytes = max_bytes })
  end

  before_each(function()
    dir = h.tmpdir()
    cache = h.tmpdir()
  end)

  after_each(function()
    h.wait(function()
      return thumbnail.pending() == 0
    end)
  end)

  ---A file in the cache of `size` bytes, last used `age` seconds ago
  ---@param name string
  ---@param size integer
  ---@param age integer
  local function cached_file(name, size, age)
    local path = cache .. "/" .. name
    h.write_bytes(path, string.rep("x", size))
    local t = os.time() - age
    uv.fs_utime(path, t, t)
    return path
  end

  ---@return string[] names Files in the cache, sorted
  local function cache_files()
    local names = vim.fn.readdir(cache)
    table.sort(names)
    return names
  end

  ---Make a real thumbnail, which counts it and may make room. With `reuse`, ask for the same
  ---image again.
  ---@param reuse? boolean
  ---@return string thumb
  local function make_thumbnail(reuse)
    local path = dir .. "/new.png"
    if not reuse then
      vim.fn.system({ "magick", "-size", "4x4", "xc:red", path })
    end
    local thumb
    thumbnail.get(path, assert(uv.fs_stat(path)), function(t)
      thumb = t
    end)
    assert.is_true(h.wait(function()
      return thumb ~= nil
    end, 10000))
    return thumb
  end

  it("deletes the least recently used thumbnails down to 80% of the limit", function()
    -- 10 files of 1000 bytes, f01 used longest ago
    for i = 1, 10 do
      cached_file(string.format("f%02d.png", i), 1000, 1000 - i)
    end
    setup(8000)
    local thumb = make_thumbnail()
    local stat = assert(uv.fs_stat(thumb))
    -- Down to 6400 bytes: the new thumbnail plus the newest files that still fit
    local kept = math.floor((6400 - stat.size) / 1000)
    local expected = {}
    for i = 10 - kept + 1, 10 do
      table.insert(expected, string.format("f%02d.png", i))
    end
    table.insert(expected, vim.fs.basename(thumb))
    table.sort(expected)
    assert.same(expected, cache_files())
  end)

  it("keeps everything below the limit", function()
    for i = 1, 3 do
      cached_file(string.format("f%02d.png", i), 1000, 100)
    end
    setup(8000)
    make_thumbnail()
    assert.equals(4, #cache_files())
  end)

  it("keeps everything without a limit", function()
    for i = 1, 10 do
      cached_file(string.format("f%02d.png", i), 1000, 100)
    end
    setup(false)
    make_thumbnail()
    assert.equals(11, #cache_files())
  end)

  it("marks a thumbnail as used when it's reused", function()
    setup(false)
    local thumb = make_thumbnail()
    local old = os.time() - 5000
    uv.fs_utime(thumb, old, old)
    assert.equals(thumb, make_thumbnail(true))
    assert.is_true(assert(uv.fs_stat(thumb)).mtime.sec > old + 4000)
  end)

  it("deletes temporary files left over from killed jobs", function()
    cached_file("old.png.123.tmp", 10, 7200)
    cached_file("fresh.png.123.tmp", 10, 10)
    for i = 1, 10 do
      cached_file(string.format("f%02d.png", i), 1000, 1000 - i)
    end
    setup(8000)
    make_thumbnail()
    local names = cache_files()
    assert.is_false(vim.tbl_contains(names, "old.png.123.tmp"))
    assert.is_true(vim.tbl_contains(names, "fresh.png.123.tmp"))
  end)

  it(":CoilClearCache deletes every thumbnail", function()
    setup(false)
    cached_file("a.png", 100, 10)
    cached_file("b.png", 100, 10)
    cached_file("running.png.1.tmp", 100, 10)
    local count, bytes = thumbnail.clear_cache()
    assert.equals(2, count)
    assert.equals(200, bytes)
    assert.same({ "running.png.1.tmp" }, cache_files())
    cached_file("c.png", 100, 10)
    local notify = vim.notify
    local msg
    vim.notify = function(m)
      msg = m
    end
    vim.cmd("CoilClearCache")
    vim.notify = notify
    assert.same({ "running.png.1.tmp" }, cache_files())
    assert.truthy(msg:find("Deleted 1 thumbnails", 1, true))
  end)
end)
