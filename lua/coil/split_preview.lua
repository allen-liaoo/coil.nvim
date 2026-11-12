-- :CoilPreview, the preview module used on its own: a split that follows an oil window's cursor.
local bridge = require("coil.oil_bridge")
local preview = require("coil.preview")
local util = require("coil.util")
local M = {}

local DEBOUNCE_MS = 30

local win_options = {
  number = false,
  relativenumber = false,
  signcolumn = "no",
  foldcolumn = "0",
  wrap = false,
  winfixbuf = true,
}

---@class (exact) coil.SplitPreview
---@field win integer The preview window
---@field group integer Autocmd group
---@field cancel fun() Stops the debounce timer

-- Keyed by the oil (source) window
---@type table<integer, coil.SplitPreview>
local attached = {}

---@param src integer
local function detach(src)
  local split = attached[src]
  if not split then
    return
  end
  attached[src] = nil
  split.cancel()
  pcall(vim.api.nvim_del_augroup_by_id, split.group)
  if vim.api.nvim_win_is_valid(split.win) then
    pcall(vim.api.nvim_win_close, split.win, true)
  end
end

---Re-render the preview for the entry under the source window's cursor
---@param src integer
M.refresh = function(src)
  local split = attached[src]
  if not split then
    return
  end
  if not vim.api.nvim_win_is_valid(split.win) or not vim.api.nvim_win_is_valid(src) then
    return detach(src)
  end
  local target = bridge.cursor_target(src)
  if target then
    preview.show(split.win, target, { list_dir = bridge.list_dir })
  else
    preview.clear(split.win)
  end
end

---@param src integer
---@return boolean
M.is_open = function(src)
  return attached[src] ~= nil
end

---Open a preview split to the right of an oil window
---@param src? integer Defaults to the current window
M.open = function(src)
  src = src or vim.api.nvim_get_current_win()
  if attached[src] then
    return
  end
  local bufnr = vim.api.nvim_win_get_buf(src)
  if not bridge.is_oil_buffer(bufnr) then
    vim.notify("[coil] :CoilPreview must be run from an oil buffer", vim.log.levels.WARN)
    return
  end

  local placeholder = require("coil.preview.buffer").message({})
  local win = vim.api.nvim_open_win(placeholder, false, { split = "right", win = src })
  util.set_win_options(win, win_options)

  local group = vim.api.nvim_create_augroup("CoilSplitPreview" .. src, { clear = true })
  local debounced, cancel = util.debounce(DEBOUNCE_MS, function()
    M.refresh(src)
  end)
  attached[src] = { win = win, group = group, cancel = cancel }

  vim.api.nvim_create_autocmd("CursorMoved", {
    group = group,
    callback = function()
      -- Visual mode means editing, not browsing; skip to avoid flicker
      if vim.api.nvim_get_current_win() == src and not vim.fn.mode():match("^[vV\22]") then
        debounced()
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    callback = function()
      -- The source window navigated to another buffer (e.g. another directory)
      if vim.api.nvim_get_current_win() == src then
        local new_buf = vim.api.nvim_win_get_buf(src)
        if bridge.is_oil_buffer(new_buf) then
          bridge.on_ready(new_buf, function()
            M.refresh(src)
          end)
        else
          M.refresh(src)
        end
      end
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    pattern = { tostring(src), tostring(win) },
    callback = function()
      vim.schedule(function()
        detach(src)
      end)
    end,
  })

  bridge.on_ready(bufnr, function()
    M.refresh(src)
  end)
end

---Close the preview split attached to an oil window
---@param src? integer Defaults to the current window
M.close = function(src)
  detach(src or vim.api.nvim_get_current_win())
end

---@param src? integer Defaults to the current window
M.toggle = function(src)
  src = src or vim.api.nvim_get_current_win()
  if attached[src] then
    M.close(src)
  else
    M.open(src)
  end
end

return M
