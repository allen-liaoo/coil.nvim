local config = require("coil.config")

describe("config", function()
  local notifications

  before_each(function()
    notifications = {}
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function(msg, level)
      table.insert(notifications, { msg = msg, level = level })
    end
    config.setup()
  end)

  it("uses the defaults without options", function()
    assert.same({ 1, 4, 3 }, config.get().ratio)
    assert.equals(30, config.get().debounce_ms)
    assert.is_false(config.get().winbar)
    assert.is_true(config.get().tab_title)
    assert.equals("L", config.get().keymaps.go_in)
  end)

  it("merges keymaps, keeping the ones not mentioned", function()
    config.setup({ keymaps = { go_in = "l", close = false } })
    assert.equals("l", config.get().keymaps.go_in)
    assert.is_false(config.get().keymaps.close)
    assert.equals("H", config.get().keymaps.go_out)
  end)

  it("rejects options of the wrong type with a clear message", function()
    for _, case in ipairs({
      { opts = { ratio = { 1, 2 } }, match = "ratio" },
      { opts = { ratio = { 1, 0, 1 } }, match = "ratio" },
      { opts = { debounce_ms = -1 }, match = "debounce_ms" },
      { opts = { debounce_ms = "fast" }, match = "debounce_ms" },
      { opts = { winbar = "yes" }, match = "winbar" },
      { opts = { tab_title = 1 }, match = "tab_title" },
      { opts = { open_external = "yes" }, match = "open_external" },
      { opts = { edit_here = 1 }, match = "edit_here" },
      { opts = { preview = false }, match = "preview" },
      { opts = { keymaps = { go_in = 1 } }, match = "keymaps.go_in" },
      { opts = { keymaps = { go_in = "" } }, match = "keymaps.go_in" },
    }) do
      local ok, err = pcall(config.setup, case.opts)
      assert.is_false(ok, vim.inspect(case.opts))
      assert.truthy(err:find(case.match, 1, true), err)
    end
  end)

  it("keeps the previous config when setup fails", function()
    config.setup({ ratio = { 2, 2, 2 } })
    pcall(config.setup, { ratio = "wide" })
    assert.same({ 2, 2, 2 }, config.get().ratio)
  end)

  it("warns about unknown options instead of failing", function()
    config.setup({ ratoi = { 1, 1, 1 }, keymaps = { go_inn = "l" } })
    assert.equals(1, #notifications)
    assert.equals(vim.log.levels.WARN, notifications[1].level)
    assert.truthy(notifications[1].msg:find("keymaps.go_inn, ratoi", 1, true))
  end)

  describe("standalone mode", function()
    after_each(function()
      vim.g.coil_standalone = nil
      config.setup()
    end)

    it("is off unless g:coil_standalone is set", function()
      assert.is_false(config.standalone())
      assert.is_false(require("coil").standalone())
      for _, value in ipairs({ 0, false }) do
        vim.g.coil_standalone = value
        assert.is_false(config.standalone())
      end
      for _, value in ipairs({ 1, true }) do
        vim.g.coil_standalone = value
        assert.is_true(config.standalone())
      end
    end)

    it("ignores the standalone options otherwise", function()
      config.setup({ standalone = { ratio = { 1, 1, 1 } } })
      assert.same({ 1, 4, 3 }, config.get().ratio)
      assert.equals("q", config.get().keymaps.close)
      assert.is_false(config.get().keymaps.quit)
    end)

    it("merges the standalone options over the rest", function()
      vim.g.coil_standalone = 1
      config.setup({
        winbar = true,
        keymaps = { go_in = "l" },
        standalone = { ratio = { 1, 1, 1 }, keymaps = { go_out = "h" } },
      })
      local c = config.get()
      assert.same({ 1, 1, 1 }, c.ratio)
      assert.is_true(c.winbar)
      -- From the options, from the standalone options, and the standalone defaults
      assert.same({ go_in = "l", go_out = "h", close = false, quit = "q" }, c.keymaps)
    end)

    it("lets the options you set win over coil's standalone defaults", function()
      vim.g.coil_standalone = 1
      config.setup({ keymaps = { quit = "Q" } })
      assert.equals("Q", config.get().keymaps.quit)
      assert.is_false(config.get().keymaps.close)
      config.setup({ keymaps = { quit = "Q" }, standalone = { keymaps = { quit = "<C-q>" } } })
      assert.equals("<C-q>", config.get().keymaps.quit)
    end)

    it("checks the standalone options in either mode", function()
      for _, case in ipairs({
        { opts = { standalone = false }, match = "standalone must be a table" },
        { opts = { standalone = { ratio = { 1 } } }, match = "standalone.ratio" },
        { opts = { standalone = { keymaps = { quit = 1 } } }, match = "standalone.keymaps.quit" },
      }) do
        local ok, err = pcall(config.setup, case.opts)
        assert.is_false(ok, vim.inspect(case.opts))
        assert.truthy(err:find(case.match, 1, true), err)
      end
      config.setup({ standalone = { winbr = true, standalone = {}, keymaps = { qiut = "q" } } })
      assert.truthy(
        notifications[1].msg:find(
          "standalone.keymaps.qiut, standalone.standalone, standalone.winbr",
          1,
          true
        )
      )
    end)
  end)
end)
