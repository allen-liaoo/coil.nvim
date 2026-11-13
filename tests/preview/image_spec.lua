local h = require("tests.helpers")
local preview = require("coil.preview")
local thumbnail = require("coil.preview.thumbnail")
local uv = vim.uv or vim.loop

-- A stand-in for image.nvim that records what coil asks of it. Headless Neovim has no terminal
-- to draw in, so the real plugin can't be checked here beyond loading (see the last test).
local fake = {}

---@return table image.nvim's API, as far as coil uses it
local function fake_image_nvim()
  fake.created = {}
  return {
    from_file = function(path, opts)
      local img = { path = path, opts = opts, renders = {}, cleared = false }
      function img:render(geometry)
        table.insert(self.renders, geometry)
        self.cleared = false
      end
      function img:clear()
        self.cleared = true
      end
      table.insert(fake.created, img)
      return img
    end,
  }
end

describe("image previews", function()
  local dir, cache, win

  ---@param name string
  local function make_image(name)
    vim.fn.system({ "magick", "-size", "40x30", "xc:red", dir .. "/" .. name })
    assert.equals(0, vim.v.shell_error)
  end

  ---@param name string
  ---@return nil|string
  local function thumb_of(name)
    local path = dir .. "/" .. name
    return thumbnail.cached(path, assert(uv.fs_stat(path)))
  end

  before_each(function()
    h.reset_tab()
    preview.setup({ image_delay_ms = 0 })
    cache = h.tmpdir()
    thumbnail.setup({ dir = cache })
    package.loaded["image"] = fake_image_nvim()
    -- image.nvim defines :ImageReport in its setup()
    vim.api.nvim_create_user_command("ImageReport", "", {})
    dir = h.tmpdir()
    win = vim.api.nvim_get_current_win()
    make_image("pic.png")
    h.write(dir .. "/a.txt", { "a" })
  end)

  after_each(function()
    h.wait(function()
      return thumbnail.pending() == 0
    end)
    package.loaded["image"] = nil
    pcall(vim.api.nvim_del_user_command, "ImageReport")
  end)

  ---@param name string
  ---@return coil.PreviewTarget
  local function target(name)
    local path = dir .. "/" .. name
    return { name = name, url = path, path = path, is_dir = false }
  end

  local function wait_drawn(n)
    assert.is_true(h.wait(function()
      return #fake.created >= n and #fake.created[n].renders > 0
    end))
    return fake.created[n]
  end

  it("draws the image below the card, filling the rest of the window", function()
    preview.show(win, target("pic.png"))
    local img = wait_drawn(1)
    local bufnr = vim.api.nvim_win_get_buf(win)
    local lines = h.win_lines(win)
    -- image.nvim gets the thumbnail, not the original
    assert.equals(thumb_of("pic.png"), img.path)
    assert.equals(cache, vim.fs.dirname(img.path))
    assert.equals(win, img.opts.window)
    assert.equals(bufnr, img.opts.buffer)
    local geom = img.renders[1]
    assert.equals(#lines - 1, geom.y)
    assert.equals(0, geom.x)
    assert.equals(vim.api.nvim_win_get_width(win), geom.width)
    assert.equals(vim.api.nvim_win_get_height(win) - #lines + 1, geom.height)
  end)

  it("draws a copy at the size image.nvim will draw it at", function()
    -- image.nvim's helpers, as coil uses them: 10x20-pixel cells, and a fit that keeps the
    -- width and takes 5 rows
    package.loaded["image/utils/term"] = {
      get_size = function()
        return { cell_width = 10, cell_height = 20, screen_cols = 200, screen_rows = 50 }
      end,
    }
    local asked
    package.loaded["image/utils/math"] = {
      adjust_to_aspect_ratio = function(_, w, h, cols, rows)
        asked = { w, h, cols, rows }
        return cols, 5
      end,
    }
    preview.show(win, target("pic.png"))
    local img = wait_drawn(1)
    package.loaded["image/utils/term"] = nil
    package.loaded["image/utils/math"] = nil
    local cols = vim.api.nvim_win_get_width(win)
    -- Asked with the thumbnail's size (the 40x30 image keeps its size) and the space below the card
    assert.same({ 40, 30, cols, img.renders[1].height }, asked)
    assert.equals(
      thumb_of("pic.png"):gsub("%.png$", "") .. ("-%dx100.png"):format(cols * 10),
      img.path
    )
  end)

  it("removes the image when the preview changes", function()
    preview.show(win, target("pic.png"))
    local img = wait_drawn(1)
    preview.show(win, target("a.txt"))
    assert.is_true(img.cleared)
    assert.same({ "a" }, h.win_lines(win))
  end)

  it("only draws the image the cursor rests on", function()
    make_image("other.png")
    preview.show(win, target("pic.png"), { image_delay_ms = 50 })
    preview.show(win, target("other.png"), { image_delay_ms = 50 })
    local img = wait_drawn(1)
    vim.wait(100)
    assert.equals(1, #fake.created)
    assert.equals(thumb_of("other.png"), img.path)
  end)

  it("redraws at the new size when the window is resized", function()
    vim.cmd("vsplit")
    preview.show(win, target("pic.png"))
    local img = wait_drawn(1)
    vim.api.nvim_win_set_width(win, 20)
    -- Headless Neovim never redraws, so WinResized has to be fired by hand
    vim.api.nvim_exec_autocmds("WinResized", {})
    assert.is_true(h.wait(function()
      return img.renders[#img.renders].width == 20
    end))
  end)

  ---The dimmed note on an image card ("Loading image...")
  ---@return nil|string
  local function status()
    local ns = vim.api.nvim_get_namespaces()["coil_card_status"]
    local marks =
      vim.api.nvim_buf_get_extmarks(vim.api.nvim_win_get_buf(win), ns, 0, -1, { details = true })
    return marks[1] and marks[1][4].virt_text[1][1]
  end

  it("says the image is loading until its thumbnail is ready", function()
    preview.show(win, target("pic.png"))
    assert.equals("Loading image...", status())
    wait_drawn(1)
    assert.is_nil(status())
    -- Once the thumbnail is cached there's nothing to wait for
    preview.show(win, target("a.txt"))
    preview.show(win, target("pic.png"))
    assert.is_nil(status())
    wait_drawn(2)
  end)

  it("notes images that can't be read", function()
    h.write(dir .. "/broken.png", { "not an image" })
    preview.show(win, target("broken.png"))
    assert.is_true(h.wait(function()
      return (status() or ""):find("^No preview: ") ~= nil
    end, 10000))
    assert.equals(0, #fake.created)
  end)

  it("gives image.nvim the original without ImageMagick", function()
    local path = vim.env.PATH
    vim.env.PATH = ""
    preview.show(win, target("pic.png"))
    local img = wait_drawn(1)
    vim.env.PATH = path
    assert.equals(dir .. "/pic.png", img.path)
  end)

  it("draws a frame below a video's card", function()
    local path = dir .. "/clip.mp4"
    vim.fn.system({
      "ffmpeg",
      "-v",
      "error",
      "-f",
      "lavfi",
      "-i",
      "testsrc=duration=1:rate=10:size=64x48",
      "-c:v",
      "mpeg4",
      path,
    })
    preview.show(win, target("clip.mp4"))
    assert.equals("Loading a frame...", status())
    local img = wait_drawn(1)
    assert.equals(thumb_of("clip.mp4"), img.path)
    assert.equals("Kind         Video", h.win_lines(win)[3])
  end)

  it("says which tool to install when one is missing", function()
    h.write(dir .. "/doc.pdf", { "%PDF-1.4" })
    local executable = vim.fn.executable
    vim.fn.executable = function(name)
      return name ~= "pdftoppm" and executable(name) or 0
    end
    preview.show(win, target("doc.pdf"))
    vim.fn.executable = executable
    local lines = h.win_lines(win)
    assert.equals("Install poppler (pdftoppm) to see the first page.", lines[#lines])
    vim.wait(20)
    assert.equals(0, #fake.created)
  end)

  it("shows the card alone when images are off", function()
    preview.show(win, target("pic.png"), { images = false })
    local lines = h.win_lines(win)
    assert.equals("Kind         Image", lines[3])
    -- No room left for an image
    assert.truthy(lines[#lines]:match("^Location"))
    vim.wait(20)
    assert.equals(0, #fake.created)
  end)

  it("shows the card alone when image.nvim isn't set up", function()
    vim.api.nvim_del_user_command("ImageReport")
    preview.show(win, target("pic.png"))
    local lines = h.win_lines(win)
    assert.truthy(lines[#lines]:match("^Location"))
    vim.wait(20)
    assert.equals(0, #fake.created)
  end)

  it("turns text attributes off before image.nvim writes kitty placeholders", function()
    -- image.nvim's kitty helpers, as coil uses them
    local written = {}
    local helpers = {
      write = function(data)
        table.insert(written, data)
      end,
    }
    helpers.write_placeholder = function()
      helpers.write("placeholders")
    end
    package.loaded["image/backends/kitty/helpers"] = helpers
    preview.show(win, target("pic.png"))
    wait_drawn(1)
    preview.show(win, target("a.txt"))
    preview.show(win, target("pic.png"))
    wait_drawn(2)
    package.loaded["image/backends/kitty/helpers"] = nil
    -- As image.nvim's backend calls it, including when it redraws by itself; wrapped only once
    helpers.write_placeholder()
    assert.same({ "\27[0m", "placeholders" }, written)
  end)

  it("works with the real image.nvim", function()
    local image_path = os.getenv("COIL_IMAGE_PATH")
    assert.truthy(image_path, "COIL_IMAGE_PATH is not set; run tests inside `nix develop`")
    package.loaded["image"] = nil
    vim.api.nvim_del_user_command("ImageReport")
    vim.opt.runtimepath:append(image_path)
    -- A 1x1 PNG
    h.write_bytes(
      dir .. "/real.png",
      vim.base64.decode(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
      )
    )
    local notify = vim.notify
    -- Without a terminal, image.nvim warns that it can't read the terminal size, and draws nothing
    vim.notify = function() end
    -- Inside tmux, image.nvim's kitty backend insists on tmux's allow-passthrough
    vim.env.TMUX = nil
    local api = require("image")
    api.setup({ backend = "kitty", integrations = {} })
    assert.is_true(require("coil.preview.image").available())

    local from_file = api.from_file
    local created = {}
    api.from_file = function(...)
      local img = from_file(...)
      table.insert(created, img)
      return img
    end
    preview.show(win, target("real.png"))
    assert.is_true(h.wait(function()
      return #created > 0
    end))
    api.from_file = from_file
    vim.notify = notify
    assert.equals(1, created[1].image_width)
    assert.equals(win, created[1].window)
    preview.show(win, target("a.txt"))
    assert.is_false(created[1].is_rendered)
  end)
end)
