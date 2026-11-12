local classify = require("coil.preview.classify")
local h = require("tests.helpers")

local opts = { max_bytes = 100, sniff_bytes = 8192 }

describe("preview.classify", function()
  local dir

  before_each(function()
    dir = h.tmpdir()
  end)

  ---@param name string
  ---@return coil.PreviewTarget
  local function target(name)
    local path = dir .. "/" .. name
    return { name = name, url = path, path = path, is_dir = false }
  end

  it("detects text", function()
    h.write(dir .. "/a.lua", { "print(1)" })
    assert.equals("text", (classify.classify(target("a.lua"), opts)))
  end)

  it("detects binary content by NUL bytes", function()
    h.write_bytes(dir .. "/blob.dat", "ab\0cd")
    assert.equals("binary", (classify.classify(target("blob.dat"), opts)))
  end)

  it("skips text preview for large files", function()
    h.write(dir .. "/big.txt", { string.rep("x", 200) })
    local kind, info = classify.classify(target("big.txt"), opts)
    assert.equals("too_large", kind)
    assert.equals(201, info.stat.size)
  end)

  it("recognizes media by extension, case-insensitively", function()
    for name, kind in pairs({
      ["pic.PNG"] = "image",
      ["clip.mp4"] = "video",
      ["song.flac"] = "audio",
      ["paper.pdf"] = "pdf",
      ["src.tar.gz"] = "archive",
    }) do
      h.write(dir .. "/" .. name, { "x" })
      assert.equals(kind, (classify.classify(target(name), opts)), name)
    end
  end)

  it("reports missing files as unreadable", function()
    local kind, info = classify.classify(target("missing.txt"), opts)
    assert.equals("unreadable", kind)
    assert.truthy(info.err:match("ENOENT"))
  end)

  it("detects directories", function()
    vim.fn.mkdir(dir .. "/sub")
    assert.equals("directory", (classify.classify(target("sub"), opts)))
  end)

  it("treats targets without a local path as remote", function()
    local kind = classify.classify({ name = "x", url = "oil-ssh://host/x", is_dir = false }, opts)
    assert.equals("remote", kind)
  end)
end)
