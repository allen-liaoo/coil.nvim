-- Thumbnails for image previews: a small PNG made in the background with ImageMagick and kept on
-- disk, so image.nvim only has to fit it to the window. image.nvim on its own converts every
-- image to a full-size PNG while Neovim waits, which takes seconds for a large photo.
local uv = vim.uv or vim.loop
local M = {}

---@class (exact) coil.ThumbnailConfig
---@field size integer[] Largest thumbnail, {width, height} in pixels; smaller images keep their size
---@field dir string Where thumbnails are kept
---@field max_jobs integer Thumbnails made at the same time
---@field max_bytes integer|false Size limit of the cache; the least recently used files go first

---@type coil.ThumbnailConfig
local defaults = {
  size = { 600, 900 },
  dir = vim.fn.stdpath("cache") .. "/coil/thumbnails",
  max_jobs = 2,
  max_bytes = 200 * 1024 * 1024,
}

---@type coil.ThumbnailConfig
local config = vim.deepcopy(defaults)

-- Bytes in the cache, as far as this Neovim knows (nil until the folder has been listed)
---@type nil|integer
local total = nil

---@param opts? table See coil.ThumbnailConfig
M.setup = function(opts)
  config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  total = nil
end

---@return string
M.dir = function()
  return config.dir
end

---ImageMagick's command: `magick` (version 7) or `convert` (version 6)
---@return nil|string
local function magick()
  if vim.fn.executable("magick") == 1 then
    return "magick"
  elseif vim.fn.executable("convert") == 1 then
    return "convert"
  end
end

---@alias coil.ThumbnailKind "image"|"video"|"pdf"

---What makes each kind's thumbnails, as named to the user when it's missing
---@type table<coil.ThumbnailKind, string>
local tool_names = {
  image = "ImageMagick (magick or convert)",
  video = "ffmpeg (ffmpeg and ffprobe)",
  pdf = "poppler (pdftoppm)",
}

---@param kind coil.ThumbnailKind
---@return boolean
local function has_tools(kind)
  if kind == "video" then
    return vim.fn.executable("ffmpeg") == 1 and vim.fn.executable("ffprobe") == 1
  elseif kind == "pdf" then
    return vim.fn.executable("pdftoppm") == 1
  end
  return magick() ~= nil
end

---Whether thumbnails of `kind` can be made (the tools are installed)
---@param kind? coil.ThumbnailKind Default "image"
---@return boolean
M.available = function(kind)
  return has_tools(kind or "image")
end

---The tool to install for thumbnails of `kind`, as shown to the user
---@param kind coil.ThumbnailKind
---@return string
M.tool_name = function(kind)
  return tool_names[kind]
end

---Which kind of thumbnail a file gets, from its extension
---@param path string
---@return coil.ThumbnailKind
M.kind_of = function(path)
  local kind = require("coil.preview.classify").kind_by_name(vim.fs.basename(path))
  return (kind == "video" or kind == "pdf") and kind or "image"
end
---Where the thumbnail of a file at this size, length and modification time lives. A changed file
---gets a new name, so a stale thumbnail is never shown.
---@param path string
---@param stat uv.fs_stat.result
---@return string
M.path_for = function(path, stat)
  local key = table.concat({
    path,
    stat.size,
    stat.mtime.sec,
    stat.mtime.nsec,
    config.size[1],
    config.size[2],
  }, "|")
  return string.format("%s/%s.png", config.dir, vim.fn.sha256(key))
end

---@alias coil.ThumbnailCallback fun(thumb?: string, err?: string)

---Given a thumbnail's size, the exact size to draw it at (nil to draw it as it is)
---@alias coil.ThumbnailFit fun(width: integer, height: integer): nil|integer, nil|integer

---@class (exact) coil.ThumbnailJob
---@field src string
---@field kind coil.ThumbnailKind
---@field out string
---@field callbacks coil.ThumbnailCallback[]
---@field prefetch boolean Nobody is waiting for it
---@field fit? coil.ThumbnailFit Also make a copy at this size (prefetch)

---Jobs waiting to start, the next one first
---@type coil.ThumbnailJob[]
local queue = {}
---Jobs queued or running, by output path
---@type table<string, coil.ThumbnailJob>
local jobs = {}
local running = 0

local start_next, fit_thumb

---@param job coil.ThumbnailJob
---@param thumb? string
---@param err? string
local function finish(job, thumb, err)
  jobs[job.out] = nil
  running = running - 1
  if thumb and job.fit then
    fit_thumb(thumb, job.fit, function() end)
  end
  for _, cb in ipairs(job.callbacks) do
    cb(thumb, err)
  end
  start_next()
end

-- The cache's size limit. Each thumbnail's modification time records when it was last used
-- (access times are unreliable: many systems mount disks with noatime or relatime), and the least
-- recently used ones are deleted first.

-- Temporary files older than this are left over from a job that was killed
local STALE_TMP_SECONDS = 3600

---Mark a cached file as just used
---@param path string
local function touch(path)
  local now = os.time()
  uv.fs_utime(path, now, now)
end

---@class (exact) coil.CachedFile
---@field path string
---@field size integer
---@field mtime integer
---@field tmp boolean

---Every file in the cache folder
---@return coil.CachedFile[]
local function list_cache()
  local files = {}
  local handle = uv.fs_scandir(config.dir)
  while handle do
    local name, type = uv.fs_scandir_next(handle)
    if not name then
      break
    end
    local path = config.dir .. "/" .. name
    local stat = type == "file" and uv.fs_stat(path)
    if stat then
      table.insert(files, {
        path = path,
        size = stat.size,
        mtime = stat.mtime.sec,
        -- Also pdftoppm's `<name>.tmp.png`
        tmp = name:find("%.tmp") ~= nil,
      })
    end
  end
  return files
end

---Delete the least recently used thumbnails until the cache is at 80% of its limit, so this
---doesn't run again for every new thumbnail. Lists the folder again first, which also corrects
---the total when several Neovims share the cache.
local function evict()
  local files = list_cache()
  local now = os.time()
  total = 0
  local thumbs = {}
  for _, file in ipairs(files) do
    if file.tmp and now - file.mtime > STALE_TMP_SECONDS then
      uv.fs_unlink(file.path)
    else
      total = total + file.size
      if not file.tmp then
        table.insert(thumbs, file)
      end
    end
  end
  table.sort(thumbs, function(a, b)
    return a.mtime < b.mtime
  end)
  local target = config.max_bytes * 0.8
  for _, file in ipairs(thumbs) do
    if total <= target then
      break
    end
    if uv.fs_unlink(file.path) then
      total = total - file.size
    end
  end
end

---Count a file just written into the cache, and make room if the cache is over its limit
---@param path string
local function account(path)
  if not config.max_bytes then
    return
  end
  if not total then
    total = 0
    for _, file in ipairs(list_cache()) do
      total = total + file.size
    end
  else
    local stat = uv.fs_stat(path)
    total = total + (stat and stat.size or 0)
  end
  if total > config.max_bytes then
    evict()
  end
end

---Delete every thumbnail. Files that jobs are still writing are left alone.
---@return integer count Files deleted
---@return integer bytes Their total size
M.clear_cache = function()
  local count, bytes = 0, 0
  local now = os.time()
  for _, file in ipairs(list_cache()) do
    if (not file.tmp or now - file.mtime > STALE_TMP_SECONDS) and uv.fs_unlink(file.path) then
      count, bytes = count + 1, bytes + file.size
    end
  end
  total = nil
  return count, bytes
end

---Run a command in the background; `cb` gets its result on the main loop
---@param cmd string[]
---@param cb fun(result: vim.SystemCompleted)
local function spawn(cmd, cb)
  local ok, err = pcall(vim.system, cmd, { text = true }, function(result)
    vim.schedule(function()
      cb(result)
    end)
  end)
  if not ok then
    vim.schedule(function()
      cb({ code = -1, signal = 0, stdout = "", stderr = tostring(err) })
    end)
  end
end

---@param result vim.SystemCompleted
---@return string
local function first_error_line(result)
  local msg = vim.trim(result.stderr or ""):match("^[^\n]*")
  return msg ~= "" and msg or "failed"
end

---Makes a thumbnail of `src` that fits `w` x `h`, written to (or starting with) `tmp`. Calls
---back with the file it wrote, or an error.
---@alias coil.ThumbnailMaker fun(src: string, tmp: string, w: integer, h: integer, cb: fun(file?: string, err?: string))

---@type table<coil.ThumbnailKind, coil.ThumbnailMaker>
local makers = {
  image = function(src, tmp, w, h, cb)
    local input
    if src:lower():match("%.jpe?g$") then
      -- Read at up to twice the thumbnail's size, which lets the JPEG decoder skip detail the
      -- thumbnail can't show (much faster for photos). Unlike `-define jpeg:size`, it never
      -- enlarges small images.
      input = string.format("%s[%dx%d>]", src, w * 2, h * 2)
    else
      -- The first frame of an animation or the first page of a TIFF; otherwise every frame
      -- would be written as a separate file
      input = src .. "[0]"
    end
    spawn({
      assert(magick()),
      input,
      -- Phone photos store their rotation separately
      "-auto-orient",
      -- Shrink to fit, never enlarge
      "-thumbnail",
      string.format("%dx%d>", w, h),
      "png:" .. tmp,
    }, function(result)
      if result.code == 0 then
        cb(tmp)
      else
        cb(nil, first_error_line(result))
      end
    end)
  end,

  -- A frame 10% of the way in, which skips black intros and title fades
  video = function(src, tmp, w, h, cb)
    spawn({
      "ffprobe",
      "-v",
      "error",
      "-show_entries",
      "format=duration",
      "-of",
      "default=noprint_wrappers=1:nokey=1",
      src,
    }, function(probe)
      local duration = tonumber(vim.trim(probe.stdout or ""))
      spawn({
        "ffmpeg",
        "-nostdin",
        "-v",
        "error",
        -- Before -i: seek in the file instead of decoding up to that point
        "-ss",
        string.format("%.3f", duration and duration * 0.1 or 0),
        "-i",
        src,
        "-frames:v",
        "1",
        -- Shrink to fit, never enlarge
        "-vf",
        string.format("scale='min(%d,iw)':'min(%d,ih)':force_original_aspect_ratio=decrease", w, h),
        "-f",
        "image2",
        "-c:v",
        "png",
        "-y",
        tmp,
      }, function(result)
        if result.code == 0 and uv.fs_stat(tmp) then
          cb(tmp)
        else
          cb(nil, result.code == 0 and "no video frame" or first_error_line(result))
        end
      end)
    end)
  end,

  -- The first page, `w` pixels wide
  pdf = function(src, tmp, w, _, cb)
    spawn({
      "pdftoppm",
      "-png",
      "-f",
      "1",
      "-l",
      "1",
      "-singlefile",
      "-scale-to-x",
      tostring(w),
      "-scale-to-y",
      "-1",
      src,
      -- pdftoppm adds the extension
      tmp,
    }, function(result)
      if result.code == 0 then
        cb(tmp .. ".png")
      else
        uv.fs_unlink(tmp .. ".png")
        cb(nil, first_error_line(result))
      end
    end)
  end,
}

---@param job coil.ThumbnailJob
local function run(job)
  if not has_tools(job.kind) then
    jobs[job.out] = nil
    for _, cb in ipairs(job.callbacks) do
      cb(nil, tool_names[job.kind] .. " is not installed")
    end
    return
  end
  running = running + 1
  vim.fn.mkdir(config.dir, "p")
  -- Written under a temporary name and renamed when complete, so a half-written thumbnail is
  -- never drawn (by this Neovim or another one sharing the cache)
  local tmp = string.format("%s.%d.tmp", job.out, uv.os_getpid())
  makers[job.kind](job.src, tmp, config.size[1], config.size[2], function(file, err)
    if file and uv.fs_rename(file, job.out) then
      account(job.out)
      finish(job, job.out)
    else
      if file then
        uv.fs_unlink(file)
      end
      uv.fs_unlink(tmp)
      finish(job, nil, err or "failed")
    end
  end)
end

start_next = function()
  while running < config.max_jobs and #queue > 0 do
    run(table.remove(queue, 1))
  end
end

---@param out string
---@return boolean
local function exists(out)
  return uv.fs_stat(out) ~= nil
end

---Width and height of a PNG, read from its header
---@param path string
---@return nil|integer width
---@return nil|integer height
local function png_size(path)
  local fd = uv.fs_open(path, "r", 0)
  if not fd then
    return nil
  end
  local data = uv.fs_read(fd, 24, 0)
  uv.fs_close(fd)
  if not data or #data < 24 or data:sub(2, 4) ~= "PNG" then
    return nil
  end
  local function u32(i)
    local a, b, c, d = data:byte(i, i + 3)
    return ((a * 256 + b) * 256 + c) * 256 + d
  end
  return u32(17), u32(21)
end

-- Copies being scaled, with whoever is waiting for each, by output path
---@type table<string, coil.ThumbnailCallback[]>
local scaling = {}

---A copy of `thumb` at exactly the size `fit` asks for. Drawing the thumbnail at another size
---means image.nvim scales it, and it does that while Neovim waits (close to a second for a large
---window, mostly spent compressing the PNG). Here it happens in the background, with light PNG
---compression. Falls back to `thumb` itself.
---@param thumb string
---@param fit coil.ThumbnailFit
---@param cb fun(file: string)
fit_thumb = function(thumb, fit, cb)
  local w, h = png_size(thumb)
  local width, height
  if w and h then
    width, height = fit(w, h)
  end
  local cmd = magick()
  if not (width and height and cmd) or (width == w and height == h) then
    return cb(thumb)
  end
  local out = string.format("%s-%dx%d.png", (thumb:gsub("%.png$", "")), width, height)
  if exists(out) then
    touch(out)
    return cb(out)
  elseif scaling[out] then
    return table.insert(scaling[out], cb)
  end
  scaling[out] = { cb }
  local tmp = string.format("%s.%d.tmp", out, uv.os_getpid())
  ---@param ok boolean
  local function done(ok)
    local waiting = scaling[out]
    scaling[out] = nil
    if not ok then
      uv.fs_unlink(tmp)
    end
    for _, waiting_cb in ipairs(waiting) do
      waiting_cb(ok and out or thumb)
    end
  end
  local ok = pcall(vim.system, {
    cmd,
    thumb,
    -- Exactly this size (`!`): the drawer computes it from the thumbnail's own aspect ratio, so
    -- the stretch is under one terminal cell
    "-scale",
    string.format("%dx%d!", width, height),
    "-define",
    "png:compression-level=1",
    "png:" .. tmp,
  }, {}, function(result)
    vim.schedule(function()
      local ok = result.code == 0 and uv.fs_rename(tmp, out) == true
      if ok then
        account(out)
      end
      done(ok)
    end)
  end)
  if not ok then
    vim.schedule(function()
      done(false)
    end)
  end
end

---The thumbnail of `path`, if it has already been made
---@param path string
---@param stat uv.fs_stat.result
---@return nil|string
M.cached = function(path, stat)
  local out = M.path_for(path, stat)
  if exists(out) then
    return out
  end
end

---Get the thumbnail of `path`, making it if needed. This one goes ahead of anything waiting.
---`cb` runs straight away on a cache hit, otherwise once ImageMagick is done.
---@param path string
---@param stat uv.fs_stat.result
---@param cb coil.ThumbnailCallback
---@param fit? coil.ThumbnailFit Call back with a copy at this size instead (see fit_thumb)
M.get = function(path, stat, cb, fit)
  if fit then
    local want = cb
    cb = function(thumb, err)
      if thumb then
        fit_thumb(thumb, fit, want)
      else
        want(nil, err)
      end
    end
  end
  local out = M.path_for(path, stat)
  if exists(out) then
    touch(out)
    return cb(out)
  end
  local job = jobs[out]
  if job then
    table.insert(job.callbacks, cb)
    job.prefetch = false
    -- Still waiting to start: move it to the front
    for i, queued in ipairs(queue) do
      if queued == job then
        table.remove(queue, i)
        table.insert(queue, 1, job)
        break
      end
    end
  else
    job = { src = path, kind = M.kind_of(path), out = out, callbacks = { cb }, prefetch = false }
    jobs[out] = job
    table.insert(queue, 1, job)
  end
  start_next()
end

---Make thumbnails in the background, in this order, before anyone asks for them. Replaces the
---previous prefetch's files that haven't started yet; ones already being made are finished.
---@param files {path: string, stat: uv.fs_stat.result}[]
---@param fit? coil.ThumbnailFit Also make copies at this size (see fit_thumb)
M.prefetch = function(files, fit)
  queue = vim.tbl_filter(function(job)
    if job.prefetch then
      jobs[job.out] = nil
      return false
    end
    return true
  end, queue)
  for _, file in ipairs(files) do
    local out = M.path_for(file.path, file.stat)
    if exists(out) then
      if fit then
        fit_thumb(out, fit, function() end)
      end
    elseif not jobs[out] then
      local job = {
        src = file.path,
        kind = M.kind_of(file.path),
        out = out,
        callbacks = {},
        prefetch = true,
        fit = fit,
      }
      jobs[out] = job
      table.insert(queue, job)
    end
  end
  start_next()
end

---Jobs queued or running, for tests
---@return integer
M.pending = function()
  return vim.tbl_count(jobs) + vim.tbl_count(scaling)
end

return M
