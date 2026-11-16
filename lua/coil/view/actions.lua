-- coil's own actions, and the `keymaps` values that run them. Like oil's keymaps, a value is an
-- action ("actions.<name>"), a function, keys to type, or a table with one of those (first item or
-- `callback`) and `mode`, `desc` or `opts`. They run in a view's middle pane.
local M = {}

---@class (exact) coil.Action
---@field desc string
---@field mode? string|string[] Default "n"
---@field callback fun(view: coil.View, opts: table)

---@type table<string, coil.Action>
M.list = {
  go_in = {
    desc = "Enter the directory under the cursor",
    callback = function(view)
      -- Files are for oil's select key, so moving around can't open (or, when choosing, pick) one
      -- by accident
      require("coil.oil_bridge").select(function(bufnr, is_dir)
        if is_dir then
          vim.api.nvim_win_set_buf(view.panes.current, bufnr)
        elseif vim.fn.bufloaded(bufnr) == 0 then
          -- oil added a buffer for the file
          pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
        end
      end)
    end,
  },
  go_out = {
    desc = "Go to the parent directory",
    callback = function()
      require("coil.oil_bridge").open_parent()
    end,
  },
  close = {
    desc = "Close the column view",
    callback = function()
      require("coil.view").close()
    end,
  },
  quit = {
    desc = "Quit Neovim, asking about unsaved changes",
    callback = function()
      vim.cmd("confirm qall")
    end,
  },
  cancel = {
    desc = "Quit like quit, without writing the cd-on-exit directory",
    callback = function()
      require("coil.startup").quit_without_cwd()
    end,
  },
}

---@class (exact) coil.ResolvedKeymap
---@field action? string The coil action it runs, if any
---@field desc string
---@field modes string[] "n" and/or "x"
---@field run fun(view: coil.View)

---@param mode any
---@return nil|string[]
local function resolve_modes(mode)
  local modes = {}
  for _, m in ipairs(type(mode) == "table" and mode or { mode }) do
    if m == "" then
      -- Like oil (and Vim's :map): normal and visual
      vim.list_extend(modes, { "n", "x" })
    elseif m == "n" or m == "x" then
      table.insert(modes, m)
    elseif m == "v" then
      table.insert(modes, "x")
    else
      return nil
    end
  end
  return #modes > 0 and modes or nil
end

---What a `keymaps` value runs
---@param rhs any
---@return nil|coil.ResolvedKeymap nil for false or an invalid value
---@return nil|string err Why the value is invalid
M.resolve = function(rhs)
  if rhs == false then
    return nil
  end
  local spec = type(rhs) == "table" and rhs or { rhs }
  local target, opts, mode = spec.callback or spec[1], spec.opts, spec.mode
  if opts ~= nil and type(opts) ~= "table" then
    return nil, "opts must be a table"
  end
  local ret = { desc = spec.desc }
  if type(target) == "string" and vim.startswith(target, "actions.") then
    local name = target:sub(#"actions." + 1)
    local action = M.list[name]
    if not action then
      local names = vim.tbl_keys(M.list)
      table.sort(names)
      return nil, string.format("no action %q (actions: %s)", name, table.concat(names, ", "))
    end
    ret.action, ret.desc, mode = name, ret.desc or action.desc, mode or action.mode
    ret.run = function(view)
      action.callback(view, opts or {})
    end
  elseif type(target) == "function" then
    ret.run = function()
      if opts then
        target(opts)
      else
        target()
      end
    end
  elseif type(target) == "string" and target ~= "" then
    ret.run = function()
      vim.api.nvim_feedkeys(vim.keycode(target), "ni", false)
    end
  else
    return nil, '"actions.<name>", a function, keys, a table with one of those, or false'
  end
  ret.desc = ret.desc or (type(target) == "string" and target or "your function")
  ret.modes = resolve_modes(mode or "n")
  if not ret.modes then
    return nil,
      string.format('mode must be "n", "x", "v", "" or a list of them, got %s', vim.inspect(mode))
  end
  return ret
end

return M
