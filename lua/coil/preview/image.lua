-- Draws images into preview windows with image.nvim (https://github.com/3rd/image.nvim). Optional:
-- without image.nvim, image cards embed `![](path)` for whatever markdown renderer is installed.
local M = {}

---@class (exact) coil.DrawnImage
---@field image table image.nvim's Image
---@field bufnr integer The card buffer the image belongs to
---@field row integer 0-based buffer line the image starts at

-- The image drawn in each window, at most one per window
---@type table<integer, coil.DrawnImage>
local drawn = {}

-- Smallest image worth drawing, in rows
local MIN_HEIGHT = 3

---image.nvim is installed and its setup() has run. It has no public check for the latter, but
---setup() is what defines :ImageReport, and from_file() throws until it has run.
---@return nil|table api
local function image_api()
  if vim.fn.exists(":ImageReport") ~= 2 then
    return nil
  end
  local ok, api = pcall(require, "image")
  if not ok or type(api.from_file) ~= "function" then
    return nil
  end
  return api
end

---@return boolean
M.available = function()
  return image_api() ~= nil
end

---The space below `row` in `winid`, which the image fills
---@param winid integer
---@param row integer 0-based buffer line
---@return nil|{x: integer, y: integer, width: integer, height: integer}
local function geometry(winid, row)
  local info = vim.fn.getwininfo(winid)[1]
  if not info then
    return nil
  end
  -- Screen row of the anchor line (0 when it is scrolled out of view). Unlike counting buffer
  -- lines, this accounts for wrapped card lines.
  local pos = vim.fn.screenpos(winid, row + 1, 1)
  if pos.row == 0 then
    return nil
  end
  local width = info.width - info.textoff
  -- From the anchor line to the window's last row. `winrow` is the winbar's row when there is one
  local height = info.winrow + info.winbar + info.height - pos.row
  if width < 1 or height < MIN_HEIGHT then
    return nil
  end
  return { x = 0, y = row, width = width, height = height }
end

---@param winid integer
---@param entry coil.DrawnImage
local function render(winid, entry)
  local geom = geometry(winid, entry.row)
  if not geom then
    pcall(entry.image.clear, entry.image)
    return
  end
  pcall(entry.image.render, entry.image, geom)
end

local group
-- image.nvim clears an image when its tab is left, and keeps the geometry it was given when the
-- window is resized or scrolled. Draw again with the window's current size and position.
local function ensure_autocmds()
  if group then
    return
  end
  group = vim.api.nvim_create_augroup("CoilPreviewImage", {})
  vim.api.nvim_create_autocmd({ "TabEnter", "WinResized", "VimResized", "WinScrolled" }, {
    group = group,
    callback = function()
      vim.schedule(function()
        local tab = vim.api.nvim_get_current_tabpage()
        for winid, entry in pairs(drawn) do
          if not vim.api.nvim_win_is_valid(winid) then
            drawn[winid] = nil
          elseif
            vim.api.nvim_win_get_tabpage(winid) == tab
            and vim.api.nvim_win_get_buf(winid) == entry.bufnr
          then
            render(winid, entry)
          end
        end
      end)
    end,
  })
end

---Draw the image at `path` in `winid`, below line `row` of the card buffer shown there
---@param winid integer
---@param bufnr integer
---@param row integer 0-based buffer line
---@param path string
---@return boolean drawn
M.draw = function(winid, bufnr, row, path)
  M.clear(winid)
  local api = image_api()
  if not api or vim.api.nvim_win_get_buf(winid) ~= bufnr then
    return false
  end
  local ok, image = pcall(api.from_file, path, {
    window = winid,
    buffer = bufnr,
    -- The geometry already fits the window; without these image.nvim also caps the image at its
    -- global max_*_window_percentage (half the window's height by default)
    max_width_window_percentage = 100,
    max_height_window_percentage = 100,
  })
  if not ok or not image then
    return false
  end
  local entry = { image = image, bufnr = bufnr, row = row }
  drawn[winid] = entry
  ensure_autocmds()
  render(winid, entry)
  -- The card buffer is wiped when the preview changes; take the image with it
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = bufnr,
    once = true,
    callback = function()
      if drawn[winid] == entry then
        M.clear(winid)
      end
    end,
  })
  return true
end

---Remove the image drawn in `winid`, if any
---@param winid integer
M.clear = function(winid)
  local entry = drawn[winid]
  drawn[winid] = nil
  if entry then
    pcall(entry.image.clear, entry.image)
  end
end

return M
