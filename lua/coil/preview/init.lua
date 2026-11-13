-- Standalone file preview: show a target (file or directory) in any window.
-- Knows nothing about oil or coil's panes; directory listing is injected via `list_dir`.
local buffer = require("coil.preview.buffer")
local card = require("coil.preview.providers.card")
local classify = require("coil.preview.classify")
local directory = require("coil.preview.providers.directory")
local image = require("coil.preview.image")
local text = require("coil.preview.providers.text")
local thumbnail = require("coil.preview.thumbnail")
local M = {}

---@class (exact) coil.PreviewTarget
---@field name string Display name
---@field url string Where the target lives (oil URL or plain path)
---@field path? string Local filesystem path; nil for remote targets
---@field is_dir boolean
---@field unsaved? boolean The entry only exists in an unsaved oil buffer

---@alias coil.ListDir fun(url: string, cb: fun(err?: string, entries?: coil.ListEntry[]))

---@class (exact) coil.PreviewOpts
---@field max_bytes integer Files larger than this get a card instead of text
---@field max_lines integer Read at most this many lines of a text file
---@field sniff_bytes integer Bytes read to detect binary content
---@field card_filetype? string Filetype for metadata cards (nil to skip)
---@field loading_delay_ms integer Wait this long before showing "Loading..."
---@field images boolean Draw images with image.nvim when it is installed and set up
---@field image_delay_ms integer Wait this long after an image card is shown before working on the image
---@field thumbnail_size integer[] Images are drawn from thumbnails at most {width, height} pixels (setup only)
---@field list_dir? coil.ListDir Lists directories for directory previews

---@type coil.PreviewOpts
local defaults = {
  max_bytes = 2 * 1024 * 1024,
  max_lines = 1000,
  sniff_bytes = 8192,
  card_filetype = "markdown",
  loading_delay_ms = 100,
  images = true,
  image_delay_ms = 100,
  thumbnail_size = { 600, 900 },
  list_dir = nil,
}

---@type coil.PreviewOpts
local config = vim.deepcopy(defaults)

---@param opts? table
M.setup = function(opts)
  config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  thumbnail.setup({ size = config.thumbnail_size })
end

-- Bumped on every show/clear. Async work compares its generation before touching the window,
-- so a slow listing can never overwrite a newer preview.
---@type table<integer, integer>
local generations = {}

---@param winid integer
---@return integer
local function next_generation(winid)
  image.clear(winid)
  generations[winid] = (generations[winid] or 0) + 1
  return generations[winid]
end

---@param winid integer
---@param gen integer
---@return boolean
local function is_latest(winid, gen)
  return generations[winid] == gen and vim.api.nvim_win_is_valid(winid)
end

---@param winid integer
---@param gen integer
---@param bufnr integer
local function place(winid, gen, bufnr)
  if not is_latest(winid, gen) or not buffer.set_win_buf(winid, bufnr) then
    buffer.discard(bufnr)
  end
end

---@param winid integer
---@param gen integer
---@param target coil.PreviewTarget
---@param opts coil.PreviewOpts
local function show_directory(winid, gen, target, opts)
  if not opts.list_dir then
    return place(winid, gen, buffer.message({ "No directory lister configured" }))
  end
  local done = false
  vim.defer_fn(function()
    if not done then
      place(winid, gen, buffer.message({ "Loading..." }))
    end
  end, opts.loading_delay_ms)
  opts.list_dir(target.url, function(err, entries)
    done = true
    if not is_latest(winid, gen) then
      return
    end
    if err then
      place(winid, gen, buffer.message({ "Cannot list directory: " .. err }))
    else
      place(winid, gen, directory.render(entries or {}, target.url))
    end
  end)
end

---Show an image card, then draw the image once the cursor has rested on it. The image drawn is a
---thumbnail made in the background (see thumbnail.lua): image.nvim converts and resizes the
---original synchronously, which stalls Neovim for seconds on a large photo. Without ImageMagick,
---image.nvim gets the original.
---@param winid integer
---@param gen integer
---@param target coil.PreviewTarget
---@param info coil.ClassifyInfo
---@param opts coil.PreviewOpts
local function show_image(winid, gen, target, info, opts)
  local path, stat = assert(target.path), assert(info.stat)
  local bufnr = card.render(target, "image", info, opts, true)
  local row = card.image_row(bufnr)
  local use_thumbnail = thumbnail.available()
  if use_thumbnail and not thumbnail.cached(path, stat) then
    card.set_status(bufnr, row, "Loading image...")
  end
  place(winid, gen, bufnr)

  local function current()
    return is_latest(winid, gen) and vim.api.nvim_win_get_buf(winid) == bufnr
  end
  ---@param file string
  local function draw(file)
    if current() then
      card.set_status(bufnr, row, nil)
      image.draw(winid, bufnr, row, file)
    end
  end
  vim.defer_fn(function()
    if not current() then
      return
    elseif not use_thumbnail then
      return draw(path)
    end
    thumbnail.get(path, stat, function(thumb, err)
      if thumb then
        draw(thumb)
      elseif current() then
        card.set_status(bufnr, row, "No image preview: " .. (err or "unknown error"))
      end
    end)
  end, opts.image_delay_ms)
end

---Show a preview of `target` in `winid`
---@param winid integer
---@param target coil.PreviewTarget
---@param opts? table Overrides for this call (see coil.PreviewOpts)
M.show = function(winid, target, opts)
  ---@type coil.PreviewOpts
  local o = vim.tbl_extend("force", config, opts or {})
  local gen = next_generation(winid)
  if target.unsaved then
    return place(
      winid,
      gen,
      buffer.message({ "Not saved yet", "Write the oil buffer to create it" })
    )
  end
  if target.is_dir then
    return show_directory(winid, gen, target, o)
  end
  local kind, info = classify.classify(target, o)
  if kind == "directory" then
    return show_directory(winid, gen, target, o)
  elseif kind == "text" then
    return place(winid, gen, text.render(assert(target.path), o))
  elseif kind == "image" and o.images and image.available() then
    return show_image(winid, gen, target, info, o)
  end
  place(winid, gen, card.render(target, kind, info, o))
end

---Show an empty buffer (or a message) in `winid`
---@param winid integer
---@param lines? string[]
M.clear = function(winid, lines)
  place(winid, next_generation(winid), buffer.message(lines or {}))
end

return M
