-- Standalone file preview: show a target (file or directory) in any window.
-- Knows nothing about oil or coil's panes; directory listing is injected via `list_dir`.
local buffer = require("coil.preview.buffer")
local card = require("coil.preview.providers.card")
local classify = require("coil.preview.classify")
local directory = require("coil.preview.providers.directory")
local image = require("coil.preview.image")
local text = require("coil.preview.providers.text")
local thumbnail = require("coil.preview.thumbnail")
local uv = vim.uv or vim.loop
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
---@field loading_delay_ms integer Wait this long before showing "Loading..."
---@field images boolean Draw images with image.nvim when it is installed and set up
---@field image_delay_ms integer Wait this long after an image card is shown before working on the image
---@field thumbnail_size integer[] Images are drawn from thumbnails at most {width, height} pixels (setup only)
---@field prefetch integer prefetch() prepares images up to this many entries from the cursor (0 for none)
---@field thumbnail_cache_mb number|false Size limit of the thumbnail cache in MiB (setup only; false for none)
---@field list_dir? coil.ListDir Lists directories for directory previews

---@type coil.PreviewOpts
local defaults = {
  max_bytes = 2 * 1024 * 1024,
  max_lines = 1000,
  sniff_bytes = 8192,
  loading_delay_ms = 100,
  images = true,
  image_delay_ms = 100,
  thumbnail_size = { 600, 900 },
  prefetch = 2,
  thumbnail_cache_mb = 200,
  list_dir = nil,
}

---@type coil.PreviewOpts
local config = vim.deepcopy(defaults)

---@param opts? table
M.setup = function(opts)
  config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  thumbnail.setup({
    size = config.thumbnail_size,
    max_bytes = config.thumbnail_cache_mb and config.thumbnail_cache_mb * 1024 * 1024,
  })
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

-- Kinds whose preview is a picture drawn below the card, and what the card says meanwhile
local loading = {
  image = "Loading image...",
  video = "Loading a frame...",
  pdf = "Loading the first page...",
}

---Show a card for an image, video or PDF, then draw a picture of it below once the cursor has
---rested on it. The picture is a thumbnail made in the background (see thumbnail.lua): the
---image itself, a frame of the video, the PDF's first page. For images without ImageMagick,
---image.nvim gets the original, which it converts and scales while Neovim waits.
---@param winid integer
---@param gen integer
---@param target coil.PreviewTarget
---@param kind "image"|"video"|"pdf"
---@param info coil.ClassifyInfo
---@param opts coil.PreviewOpts
local function show_picture(winid, gen, target, kind, info, opts)
  local path, stat = assert(target.path), assert(info.stat)
  local bufnr = card.render(target, kind, info, opts, true)
  local row = card.image_row(bufnr)
  local use_thumbnail = thumbnail.available(kind)
  if use_thumbnail and not thumbnail.cached(path, stat) then
    card.set_status(bufnr, row, loading[kind])
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
    -- Made at the size image.nvim will draw it, so it doesn't scale it while Neovim waits
    local fit = image.fitter(winid, row)
    thumbnail.get(path, stat, function(thumb, err)
      if thumb then
        draw(thumb)
      elseif current() then
        card.set_status(bufnr, row, "No preview: " .. (err or "unknown error"))
      end
    end, fit)
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
  elseif loading[kind] and o.images and image.available() then
    if kind == "image" or thumbnail.available(kind) then
      return show_picture(winid, gen, target, kind, info, o)
    end
    local what = kind == "pdf" and "the first page" or "a frame from the video"
    info = vim.tbl_extend("force", info, {
      note = string.format("Install %s to see %s.", thumbnail.tool_name(kind), what),
    })
  end
  place(winid, gen, card.render(target, kind, info, o))
end

---Show an empty buffer (or a message) in `winid`
---@param winid integer
---@param lines? string[]
M.clear = function(winid, lines)
  place(winid, next_generation(winid), buffer.message(lines or {}))
end

---How far from the cursor prefetch() should look, in entries (the `prefetch` option)
---@return integer
M.prefetch_distance = function()
  return config.prefetch
end

---Prepare the images, videos and PDFs among `targets` (entries near the cursor, nearest first) in the background,
---so they are ready when the cursor reaches them. Call it after show(): like the image the cursor
---is on, nothing starts until the preview has stayed the same for `image_delay_ms`.
---@param winid integer The window show() last ran in
---@param targets coil.PreviewTarget[]
M.prefetch = function(winid, targets)
  if not (config.images and image.available()) then
    return
  end
  local gen = generations[winid]
  vim.defer_fn(function()
    if generations[winid] ~= gen then
      return
    end
    local files, fit = {}, nil
    for _, target in ipairs(targets) do
      if target.path and not target.is_dir and not target.unsaved then
        local kind = classify.kind_by_name(target.name)
        local stat = loading[kind] and thumbnail.available(kind) and uv.fs_stat(target.path)
        if stat and stat.type == "file" then
          table.insert(files, { path = target.path, stat = stat })
          -- Cards of one kind have the same lines; for the others, the exact-size copy is made
          -- when the cursor gets there
          if not fit then
            local lines = card.lines(target, kind, { stat = stat }, config, true)
            fit = image.estimated_fitter(winid, #lines - 1)
          end
        end
      end
    end
    thumbnail.prefetch(files, fit)
  end, config.image_delay_ms)
end

return M
