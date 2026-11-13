-- Draws images into preview windows with image.nvim (https://github.com/3rd/image.nvim). Optional:
-- without image.nvim, image cards show the file's details only.
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

---The exact size image.nvim will scale an image to when it fills `cols` x `rows` cells, so a copy
---can be made at that size in the background (see thumbnail.lua's fit_thumb). image.nvim scales
---any image whose width differs, while Neovim waits. This follows image.nvim's renderer using its
---own terminal-size and aspect-ratio helpers; if they're missing or the result is off, image.nvim
---just scales the image itself, as it would anyway.
---@param cols integer
---@param rows integer
---@return nil|coil.ThumbnailFit
local function fitter(cols, rows)
  local ok_term, term = pcall(require, "image/utils/term")
  local ok_math, image_math = pcall(require, "image/utils/math")
  if
    not (ok_term and ok_math)
    or type(term.get_size) ~= "function"
    or type(image_math.adjust_to_aspect_ratio) ~= "function"
  then
    return nil
  end
  local size = term.get_size()
  if not size then
    return nil
  end
  cols = math.min(cols, size.screen_cols)
  return function(w, h)
    local fit_cols, fit_rows = image_math.adjust_to_aspect_ratio(size, w, h, cols, rows)
    local width, height = fit_cols * size.cell_width, fit_rows * size.cell_height
    -- image.nvim compares the width exactly; with fractional cell sizes it always scales
    if width % 1 ~= 0 or height % 1 ~= 0 then
      return nil
    end
    return width, height
  end
end

---The exact size image.nvim will draw an image at in `winid`, below line `row` of the buffer
---shown there
---@param winid integer
---@param row integer 0-based buffer line
---@return nil|coil.ThumbnailFit
M.fitter = function(winid, row)
  local geom = image_api() and geometry(winid, row)
  return geom and fitter(geom.width, geom.height) or nil
end

---Like fitter(), for a card that isn't shown yet: assumes it is shown from its first line and its
---lines don't wrap
---@param winid integer
---@param row integer 0-based line of that card where the image would start
---@return nil|coil.ThumbnailFit
M.estimated_fitter = function(winid, row)
  local info = image_api() and vim.fn.getwininfo(winid)[1]
  if not info or info.height - row < MIN_HEIGHT then
    return nil
  end
  return fitter(info.width - info.textoff, info.height - row)
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
