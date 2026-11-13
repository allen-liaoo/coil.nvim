local coil = require("coil")
local h = require("tests.helpers")
local standalone = require("coil.standalone")
local state = require("coil.view.state")

describe("standalone startup", function()
  local dir, notifications, notify

  before_each(function()
    dir = h.tmpdir()
    notifications = {}
    notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(notifications, { msg = msg, level = level })
    end
  end)

  after_each(function()
    vim.notify = notify
  end)

  ---Write a config file and load it
  ---@param lines string[]
  ---@return table
  local function load(lines)
    local path = dir .. "/init.lua"
    h.write(path, lines)
    local result = standalone.load_config(path)
    -- Warnings are scheduled
    vim.wait(20)
    return result
  end

  describe("the config file", function()
    it("is optional", function()
      assert.same({}, standalone.load_config(dir .. "/missing.lua"))
    end)

    it("runs as Lua and may return setup options", function()
      local options = standalone.options(load({
        "vim.g.coil_test_config_ran = true",
        "return { oil = { delete_to_trash = false }, coil = { ratio = { 1, 2, 3 } } }",
      }))
      assert.is_true(vim.g.coil_test_config_ran)
      assert.is_false(options.oil.delete_to_trash)
      assert.same({ 1, 2, 3 }, options.coil.ratio)
      -- Not mentioned: the build's defaults
      assert.same(standalone.defaults.image, options.image)
    end)

    it("merges into the build's defaults", function()
      local defaults = standalone.defaults
      standalone.defaults = { oil = { a = 1, nested = { b = 2 } }, coil = {}, image = {} }
      local options = standalone.options(load({ "return { oil = { nested = { c = 3 } } }" }))
      standalone.defaults = defaults
      assert.same({ a = 1, nested = { b = 2, c = 3 } }, options.oil)
    end)

    it("can turn image.nvim off", function()
      assert.is_false(standalone.options(load({ "return { image = false }" })).image)
    end)

    it("reports errors and falls back to the defaults", function()
      assert.same({}, load({ "error('oops')" }))
      assert.equals(1, #notifications)
      assert.truthy(notifications[1].msg:find("oops", 1, true))
      assert.same({}, load({ "return 42" }))
      assert.truthy(notifications[2].msg:find("should return a table", 1, true))
    end)
  end)

  describe("the command line", function()
    before_each(function()
      for _ = 1, 5 do
        pcall(coil.close)
      end
      h.reset_tab()
      h.setup_oil()
      coil.setup()
      vim.fn.mkdir(dir .. "/one")
      vim.fn.mkdir(dir .. "/two")
      h.write(dir .. "/file.txt", { "" })
    end)

    after_each(function()
      for _ = 1, 5 do
        pcall(coil.close)
      end
    end)

    it("opens the current directory, all-directory arguments, or nothing", function()
      assert.same({ vim.fn.getcwd() }, standalone.dirs_for({}))
      local dirs = { dir .. "/one", "oil://" .. dir .. "/two/" }
      assert.same(dirs, standalone.dirs_for(dirs))
      assert.is_nil(standalone.dirs_for({ dir .. "/one", dir .. "/file.txt" }))
    end)

    it("starts with only the column views", function()
      local start_buf = vim.api.nvim_get_current_buf()
      standalone.open_args({ dir .. "/one", dir .. "/two" })
      assert.equals(2, #vim.api.nvim_list_tabpages())
      for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
        assert.truthy(state.get(tab))
      end
      assert.is_false(vim.api.nvim_buf_is_valid(start_buf))
    end)
  end)
end)
