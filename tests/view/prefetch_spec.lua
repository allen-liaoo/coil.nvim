local coil = require("coil")
local h = require("tests.helpers")
local thumbnail = require("coil.preview.thumbnail")
local uv = vim.uv or vim.loop

describe("thumbnail prefetch", function()
  local dir

  ---@param opts? table coil's `preview` options
  local function setup(opts)
    coil.setup({ preview = vim.tbl_extend("force", { image_delay_ms = 0 }, opts or {}) })
    -- After coil.setup(), which resets the thumbnail module
    thumbnail.setup({ dir = h.tmpdir() })
  end

  before_each(function()
    pcall(coil.close)
    h.reset_tab()
    h.setup_oil()
    setup()
    -- Stand in for image.nvim: prefetch only runs when images can be drawn
    package.loaded["image"] = {
      from_file = function()
        return { render = function() end, clear = function() end }
      end,
    }
    vim.api.nvim_create_user_command("ImageReport", "", {})
    dir = h.tmpdir()
    for _, name in ipairs({ "a", "b", "c", "d", "e", "f", "g" }) do
      vim.fn.system({ "magick", "-size", "10x10", "xc:red", dir .. "/" .. name .. ".png" })
    end
    h.write(dir .. "/notes.txt", { "" })
  end)

  after_each(function()
    h.wait(function()
      return thumbnail.pending() == 0
    end, 10000)
    package.loaded["image"] = nil
    pcall(vim.api.nvim_del_user_command, "ImageReport")
  end)

  ---Names among a..g (and notes) whose thumbnail is cached once the queue is empty
  ---@return string[]
  local function cached()
    assert.is_true(h.wait(function()
      return thumbnail.pending() == 0
    end, 10000))
    local names = {}
    for _, name in ipairs({ "a", "b", "c", "d", "e", "f", "g" }) do
      local path = dir .. "/" .. name .. ".png"
      if thumbnail.cached(path, assert(uv.fs_stat(path))) then
        table.insert(names, name)
      end
    end
    return names
  end

  ---Move the middle pane's cursor, starting from an empty cache: opening the view already
  ---prepared the images around its first entry
  ---@param view coil.View
  ---@param text string
  local function move_to(view, text)
    assert.is_true(h.wait(function()
      return h.win_lines(view.panes.preview)[1] == "a.png"
    end))
    -- The prefetch for a.png's neighbours starts after a zero-delay timer
    vim.wait(50)
    cached()
    for _, name in ipairs(vim.fn.readdir(thumbnail.dir())) do
      uv.fs_unlink(thumbnail.dir() .. "/" .. name)
    end
    h.cursor_to(view.panes.current, text)
    vim.api.nvim_exec_autocmds("CursorMoved", {})
  end

  it("prepares the images within two entries of the cursor", function()
    local view = h.open_view(dir)
    move_to(view, "d.png")
    -- Let the preview and the prefetch timers run
    vim.wait(100)
    assert.same({ "b", "c", "d", "e", "f" }, cached())
  end)

  it("skips entries that aren't images", function()
    local view = h.open_view(dir)
    -- notes.txt sorts last, after g.png
    move_to(view, "g.png")
    vim.wait(100)
    assert.same({ "e", "f", "g" }, cached())
  end)

  it("can be turned off", function()
    setup({ prefetch = 0 })
    local view = h.open_view(dir)
    move_to(view, "d.png")
    vim.wait(100)
    assert.same({ "d" }, cached())
  end)
end)
