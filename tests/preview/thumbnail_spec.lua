local h = require("tests.helpers")
local thumbnail = require("coil.preview.thumbnail")
local uv = vim.uv or vim.loop

describe("thumbnails", function()
  local dir, cache, spawned, system

  before_each(function()
    dir = h.tmpdir()
    cache = h.tmpdir()
    thumbnail.setup({ dir = cache })
    -- Count ImageMagick runs
    spawned = 0
    system = vim.system
    vim.system = function(...)
      spawned = spawned + 1
      return system(...)
    end
  end)

  after_each(function()
    vim.system = system
    h.wait(function()
      return thumbnail.pending() == 0
    end)
  end)

  ---Make an image with ImageMagick
  ---@param name string
  ---@param size string e.g. "1200x1800"
  ---@return string path
  local function image(name, size)
    local path = dir .. "/" .. name
    vim.fn.system({ "magick", "-size", size, "xc:red", path })
    assert.equals(0, vim.v.shell_error)
    return path
  end

  ---@param path string
  ---@return string "WxH"
  local function dimensions(path)
    return vim.trim(vim.fn.system({ "magick", "identify", "-format", "%wx%h", path }))
  end

  ---Get a thumbnail and wait for it
  ---@param path string
  ---@return string|nil thumb
  ---@return string|nil err
  local function get(path)
    local done, thumb, err = false, nil, nil
    thumbnail.get(path, assert(uv.fs_stat(path)), function(t, e)
      done, thumb, err = true, t, e
    end)
    assert.is_true(h.wait(function()
      return done
    end, 10000))
    return thumb, err
  end

  it("shrinks an image to fit 600x900, as a PNG in the cache", function()
    local thumb = assert(get(image("big.jpg", "1200x1800")))
    assert.equals(cache, vim.fs.dirname(thumb))
    assert.equals("600x900", dimensions(thumb))
    assert.truthy(vim.fn.system({ "magick", "identify", "-format", "%m", thumb }):match("PNG"))
  end)

  it("keeps a small image's size", function()
    assert.equals("10x20", dimensions(assert(get(image("small.png", "10x20")))))
    -- JPEGs are read with a size hint, which must not enlarge them
    assert.equals("50x60", dimensions(assert(get(image("small.jpg", "50x60")))))
  end)

  it("uses the first frame of an animation", function()
    local path = dir .. "/anim.gif"
    vim.fn.system({ "magick", "-size", "20x10", "xc:red", "xc:blue", path })
    assert.equals("20x10", dimensions(assert(get(path))))
  end)

  it("reuses a thumbnail without running ImageMagick again", function()
    local path = image("a.jpg", "100x100")
    local first = get(path)
    assert.equals(1, spawned)
    local hit
    thumbnail.get(path, assert(uv.fs_stat(path)), function(t)
      hit = t
    end)
    -- A cache hit answers straight away
    assert.equals(first, hit)
    assert.equals(1, spawned)
    assert.equals(first, thumbnail.cached(path, assert(uv.fs_stat(path))))
  end)

  it("makes a new thumbnail when the file changes", function()
    local path = image("a.jpg", "100x100")
    local first = get(path)
    image("a.jpg", "50x60")
    local second = assert(get(path))
    assert.are_not.equal(first, second)
    assert.equals("50x60", dimensions(second))
  end)

  it("runs ImageMagick once for requests that arrive together", function()
    local path = image("a.jpg", "100x100")
    local results = {}
    for _ = 1, 2 do
      thumbnail.get(path, assert(uv.fs_stat(path)), function(t)
        table.insert(results, t)
      end)
    end
    assert.is_true(h.wait(function()
      return #results == 2
    end, 10000))
    assert.equals(1, spawned)
    assert.equals(results[1], results[2])
  end)

  it("reports files ImageMagick can't read", function()
    local path = dir .. "/broken.jpg"
    h.write(path, { "not an image" })
    local thumb, err = get(path)
    assert.is_nil(thumb)
    assert.truthy(err)
    -- No temporary file is left behind
    assert.same({}, vim.fn.readdir(cache))
  end)

  it("makes prefetched thumbnails, dropping ones replaced before they start", function()
    thumbnail.setup({ dir = cache, max_jobs = 1 })
    local a, b, c, d =
      image("a.png", "10x10"),
      image("b.png", "10x10"),
      image("c.png", "10x10"),
      image("d.png", "10x10")
    local function files(...)
      return vim.tbl_map(function(path)
        return { path = path, stat = assert(uv.fs_stat(path)) }
      end, { ... })
    end
    thumbnail.prefetch(files(a, b, c))
    -- `a` has started; b and c are still waiting, and are dropped
    thumbnail.prefetch(files(d))
    assert.is_true(h.wait(function()
      return thumbnail.pending() == 0
    end, 10000))
    local function cached(path)
      return thumbnail.cached(path, assert(uv.fs_stat(path))) ~= nil
    end
    assert.is_true(cached(a))
    assert.is_false(cached(b))
    assert.is_false(cached(c))
    assert.is_true(cached(d))
  end)

  it("puts a requested thumbnail ahead of prefetched ones", function()
    thumbnail.setup({ dir = cache, max_jobs = 1 })
    local a, b, c = image("a.png", "10x10"), image("b.png", "10x10"), image("c.png", "10x10")
    thumbnail.prefetch({
      { path = a, stat = assert(uv.fs_stat(a)) },
      { path = b, stat = assert(uv.fs_stat(b)) },
    })
    local order = {}
    thumbnail.get(c, assert(uv.fs_stat(c)), function()
      table.insert(order, "c")
      table.insert(order, thumbnail.cached(b, assert(uv.fs_stat(b))) and "b done" or "b not done")
    end)
    assert.is_true(h.wait(function()
      return #order == 2
    end, 10000))
    assert.same({ "c", "b not done" }, order)
  end)

  it("knows when ImageMagick isn't installed", function()
    assert.is_true(thumbnail.available())
    local path = vim.env.PATH
    vim.env.PATH = ""
    local ok, available = pcall(thumbnail.available)
    vim.env.PATH = path
    assert.is_true(ok)
    assert.is_false(available)
  end)
end)
