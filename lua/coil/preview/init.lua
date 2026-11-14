-- Standalone file preview: show a target (file or directory) in any window.
-- Knows nothing about oil or coil's panes; directory listing is injected via `list_dir`, and
-- downloading remote files via `fetch`.
local buffer = require("coil.preview.buffer")
local classify = require("coil.preview.classify")
local directory = require("coil.preview.providers.directory")
local image = require("coil.preview.image")
local remote = require("coil.preview.remote")
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
---@field size? integer Size in bytes, if known without reading the file (remote targets)
---@field mtime? string|number When it last changed, in any form (remote targets)

---@alias coil.ListDir fun(url: string, cb: fun(err?: string, entries?: coil.ListEntry[]))

---@class (exact) coil.PreviewOpts
---@field max_bytes integer Files larger than this get no text preview
---@field max_lines integer Read at most this many lines of a text file
---@field sniff_bytes integer Bytes read to detect binary content
---@field loading_delay_ms integer Wait this long before showing "Loading..."
---@field images boolean Draw images with image.nvim when it is installed and set up
---@field image_delay_ms integer Wait this long after an image's preview is shown before working on the image
---@field thumbnail_size integer[] Images are drawn from thumbnails at most {width, height} pixels (setup only)
---@field prefetch integer prefetch() prepares images up to this many entries from the cursor (0 for none)
---@field thumbnail_cache_mb number|false Size limit of the thumbnail cache in MiB (setup only; false for none)
---@field list_dir? coil.ListDir Lists directories for directory previews
---@field fetch? coil.Fetch Downloads remote targets (those without a local path)
---@field remote_max_bytes integer Remote images, videos and PDFs larger than this aren't downloaded (other remote files: max_bytes)
---@field remote_delay_ms integer Wait this long after a remote file's preview is shown before downloading it
---@field remote_cache_mb number|false Size limit of the downloaded copies in MiB (setup only; false for none)

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
  fetch = nil,
  remote_max_bytes = 20 * 1024 * 1024,
  remote_delay_ms = 200,
  remote_cache_mb = 100,
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
  remote.setup({ max_bytes = config.remote_cache_mb and config.remote_cache_mb * 1024 * 1024 })
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

-- The download each window waits for, as the function that gives it up
---@type table<integer, fun()>
local downloads = {}

---Stop waiting for the download `winid` asked for last, if any
---@param winid integer
local function release_download(winid)
  local release = downloads[winid]
  downloads[winid] = nil
  if release then
    release()
  end
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

-- Kinds whose preview is a picture, and what it shows
local pictures = {
  image = "the image",
  video = "a frame from the video",
  pdf = "the first page",
}

---@param size integer
---@return string
local function format_size(size)
  if size >= 1e9 then
    return string.format("%.1fG", size / 1e9)
  elseif size >= 1e6 then
    return string.format("%.1fM", size / 1e6)
  elseif size >= 1e3 then
    return string.format("%.1fk", size / 1e3)
  else
    return string.format("%d", size)
  end
end

---Whether a picture of `kind` can be drawn (image.nvim, and the tool that makes its thumbnails)
---@param kind coil.PreviewKind
---@param opts coil.PreviewOpts
---@return boolean
local function can_draw(kind, opts)
  return pictures[kind] ~= nil
    and opts.images
    and image.available()
    and (kind == "image" or thumbnail.available(kind))
end

---What the preview says for a file it shows neither text nor a picture of
---@param kind coil.PreviewKind
---@param info coil.ClassifyInfo
---@param opts coil.PreviewOpts
---@return string
local function message_for(kind, info, opts)
  if pictures[kind] then
    if not opts.images then
      return "Image previews are off"
    elseif not image.available() then
      return "Set up image.nvim to see " .. pictures[kind]
    end
    return string.format("Install %s to see %s", thumbnail.tool_name(kind), pictures[kind])
  elseif kind == "too_large" then
    return string.format("Larger than %s, so the text isn't shown", format_size(opts.max_bytes))
  elseif kind == "special" then
    return string.format("Not a regular file (%s)", info.stat and info.stat.type or "unknown")
  elseif kind == "unreadable" then
    return "Cannot read this file: " .. (info.err or "unknown error")
  elseif kind == "remote" then
    return "No preview: coil can't download files from here"
  elseif kind == "archive" then
    return "No preview for archives"
  end
  return string.format("No preview for %s files", kind)
end

---Draw a picture of an image, video or PDF once the cursor has rested on it. The picture is a
---thumbnail made in the background (see thumbnail.lua): the image itself, a frame of the video,
---the PDF's first page. For images without ImageMagick, image.nvim gets the original, which it
---converts and scales while Neovim waits.
---@param winid integer
---@param gen integer
---@param target coil.PreviewTarget
---@param kind "image"|"video"|"pdf"
---@param info coil.ClassifyInfo
---@param opts coil.PreviewOpts
local function show_picture(winid, gen, target, kind, info, opts)
  local path, stat = assert(target.path), assert(info.stat)
  -- The picture fills the window below the buffer's only line, which says what is happening
  -- until the picture is drawn: during image_delay_ms, while the thumbnail is made, and while
  -- image.nvim scales an original
  local bufnr = buffer.scratch({ "" })
  buffer.set_status(bufnr, "Loading thumbnail...")
  local use_thumbnail = thumbnail.available(kind)
  place(winid, gen, bufnr)

  local function current()
    return is_latest(winid, gen) and vim.api.nvim_win_get_buf(winid) == bufnr
  end
  ---@param file string
  local function draw(file)
    if current() then
      buffer.set_status(bufnr, nil)
      image.draw(winid, bufnr, 0, file)
    end
  end
  vim.defer_fn(function()
    if not current() then
      return
    elseif not use_thumbnail then
      return draw(path)
    end
    -- Made at the size image.nvim will draw it, so it doesn't scale it while Neovim waits
    local fit = image.fitter(winid, 0)
    thumbnail.get(path, stat, function(thumb, err)
      if thumb then
        draw(thumb)
      elseif current() then
        buffer.set_status(bufnr, "No preview: " .. (err or "unknown error"))
      end
    end, fit)
  end, opts.image_delay_ms)
end

---Preview a local file
---@param winid integer
---@param gen integer
---@param target coil.PreviewTarget
---@param opts coil.PreviewOpts
local function show_file(winid, gen, target, opts)
  local kind, info = classify.classify(target, opts)
  if kind == "directory" then
    return show_directory(winid, gen, target, opts)
  elseif kind == "text" then
    return place(winid, gen, text.render(assert(target.path), opts))
  elseif can_draw(kind, opts) then
    ---@cast kind "image"|"video"|"pdf"
    return show_picture(winid, gen, target, kind, info, opts)
  end
  place(winid, gen, buffer.message({ message_for(kind, info, opts) }))
end

---Preview a remote file from a local copy, downloaded once the cursor has rested on it
---@param winid integer
---@param gen integer
---@param target coil.PreviewTarget
---@param opts coil.PreviewOpts
local function show_remote(winid, gen, target, opts)
  if not opts.fetch then
    release_download(winid)
    return place(winid, gen, buffer.message({ message_for("remote", {}, opts) }))
  end
  -- Files whose extension alone decides their message: downloading them wouldn't change it
  local kind = classify.kind_by_name(target.name)
  local limit = kind and opts.remote_max_bytes or opts.max_bytes
  local msg
  if kind and not can_draw(kind, opts) then
    msg = message_for(kind, {}, opts)
  elseif target.size and target.size > limit then
    msg = kind and string.format("Larger than %s, so it isn't downloaded", format_size(limit))
      or message_for("too_large", {}, opts)
  end
  if msg then
    release_download(winid)
    return place(winid, gen, buffer.message({ msg }))
  end

  ---@param path string
  local function show_copy(path)
    show_file(
      winid,
      gen,
      { name = target.name, url = target.url, path = path, is_dir = false },
      opts
    )
  end
  local cached = remote.cached(target)
  if cached then
    release_download(winid)
    return show_copy(cached)
  end
  -- The window's previous download keeps going until this one starts, so showing the same file
  -- again (a redraw) doesn't restart it
  place(winid, gen, buffer.message({ "Downloading..." }))
  vim.defer_fn(function()
    if not is_latest(winid, gen) then
      return
    end
    local done = false
    local release = remote.download(target, opts.fetch, function(path, err)
      done = true
      if not is_latest(winid, gen) then
        return
      elseif path then
        return show_copy(path)
      end
      local line = vim.trim(err or ""):match("^[^\n]*")
      place(
        winid,
        gen,
        buffer.message({ "Cannot download: " .. (line ~= "" and line or "unknown error") })
      )
    end)
    release_download(winid)
    if not done then
      downloads[winid] = release
    end
  end, opts.remote_delay_ms)
end

---The kind of preview `target` gets (text, image, binary, ...)
---@param target coil.PreviewTarget
---@return coil.PreviewKind
M.kind = function(target)
  return (classify.classify(target, config))
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
  if not target.path and not target.is_dir then
    return show_remote(winid, gen, target, o)
  end
  release_download(winid)
  if target.is_dir then
    return show_directory(winid, gen, target, o)
  end
  show_file(winid, gen, target, o)
end

---Stop previewing in `winid` without placing a buffer, because something else will show there:
---drops the image and any download, and keeps pending results from landing
---@param winid integer
M.stop = function(winid)
  release_download(winid)
  next_generation(winid)
end

---Show an empty buffer (or a message) in `winid`
---@param winid integer
---@param lines? string[]
M.clear = function(winid, lines)
  release_download(winid)
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
    local files = {}
    for _, target in ipairs(targets) do
      if target.path and not target.is_dir and not target.unsaved then
        local kind = classify.kind_by_name(target.name)
        local stat = pictures[kind] and thumbnail.available(kind) and uv.fs_stat(target.path)
        if stat and stat.type == "file" then
          table.insert(files, { path = target.path, stat = stat })
        end
      end
    end
    -- Every picture fills the window from its first line
    thumbnail.prefetch(files, image.estimated_fitter(winid, 0))
  end, config.image_delay_ms)
end

return M
