local dimensions = require("coil.preview.dimensions")
local h = require("tests.helpers")

describe("image dimensions", function()
  local dir

  before_each(function()
    dir = h.tmpdir()
  end)

  ---Make an image with ImageMagick
  ---@param name string
  ---@param ... string Extra arguments before the output
  ---@return string path
  local function image(name, ...)
    local path = dir .. "/" .. name
    vim.fn.system(vim.list_extend({ "magick", "-size", "37x23", "xc:red", ... }, { path }))
    assert.equals(0, vim.v.shell_error, "magick failed for " .. name)
    return path
  end

  for _, name in ipairs({ "a.png", "a.jpg", "a.gif", "a.bmp" }) do
    it("reads " .. name, function()
      assert.same({ 37, 23 }, { dimensions.read(image(name)) })
    end)
  end

  it("reads WebP, lossy and lossless", function()
    assert.same({ 37, 23 }, { dimensions.read(image("lossy.webp")) })
    assert.same(
      { 37, 23 },
      { dimensions.read(image("lossless.webp", "-define", "webp:lossless=true")) }
    )
    -- With an alpha channel: the extended format
    assert.same({ 37, 23 }, {
      dimensions.read(
        image("alpha.webp", "-alpha", "set", "-channel", "A", "-evaluate", "set", "50%")
      ),
    })
  end)

  it("steps over JPEG metadata to the frame header", function()
    -- A comment segment and EXIF-style data before the frame
    local path = image("meta.jpg", "-set", "comment", string.rep("x", 5000))
    assert.same({ 37, 23 }, { dimensions.read(path) })
  end)

  it("returns nothing for other files", function()
    h.write(dir .. "/a.txt", { "not an image" })
    assert.is_nil(dimensions.read(dir .. "/a.txt"))
    assert.is_nil(dimensions.read(dir .. "/missing.png"))
    -- A truncated PNG
    h.write_bytes(dir .. "/short.png", "\137PNG\r\n\26\n")
    assert.is_nil(dimensions.read(dir .. "/short.png"))
  end)
end)
