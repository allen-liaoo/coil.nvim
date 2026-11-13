local h = require("tests.helpers")
local preview = require("coil.preview")

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
  local dir, win

  before_each(function()
    h.reset_tab()
    preview.setup({ image_delay_ms = 0 })
    package.loaded["image"] = fake_image_nvim()
    -- image.nvim defines :ImageReport in its setup()
    vim.api.nvim_create_user_command("ImageReport", "", {})
    dir = h.tmpdir()
    win = vim.api.nvim_get_current_win()
    h.write(dir .. "/pic.png", { "x" })
    h.write(dir .. "/a.txt", { "a" })
  end)

  after_each(function()
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
    assert.equals(dir .. "/pic.png", img.path)
    assert.equals(win, img.opts.window)
    assert.equals(bufnr, img.opts.buffer)
    -- No markdown embed, or a markdown image plugin would draw it a second time
    for _, line in ipairs(lines) do
      assert.is_nil(line:find("![", 1, true))
    end
    local geom = img.renders[1]
    assert.equals(#lines - 1, geom.y)
    assert.equals(0, geom.x)
    assert.equals(vim.api.nvim_win_get_width(win), geom.width)
    assert.equals(vim.api.nvim_win_get_height(win) - #lines + 1, geom.height)
  end)

  it("removes the image when the preview changes", function()
    preview.show(win, target("pic.png"))
    local img = wait_drawn(1)
    preview.show(win, target("a.txt"))
    assert.is_true(img.cleared)
    assert.same({ "a" }, h.win_lines(win))
  end)

  it("only draws the image the cursor rests on", function()
    h.write(dir .. "/other.png", { "x" })
    preview.show(win, target("pic.png"), { image_delay_ms = 50 })
    preview.show(win, target("other.png"), { image_delay_ms = 50 })
    local img = wait_drawn(1)
    vim.wait(100)
    assert.equals(1, #fake.created)
    assert.equals(dir .. "/other.png", img.path)
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

  it("embeds the image in the card when images are off", function()
    preview.show(win, target("pic.png"), { images = false })
    local lines = h.win_lines(win)
    assert.equals(string.format("![pic.png](%s/pic.png)", dir), lines[#lines])
    vim.wait(20)
    assert.equals(0, #fake.created)
  end)

  it("embeds the image in the card when image.nvim isn't set up", function()
    vim.api.nvim_del_user_command("ImageReport")
    preview.show(win, target("pic.png"))
    local lines = h.win_lines(win)
    assert.equals(string.format("![pic.png](%s/pic.png)", dir), lines[#lines])
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
