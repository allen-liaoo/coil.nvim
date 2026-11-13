-- Thumbnails for image previews: a small PNG made in the background with ImageMagick and kept on
-- disk, so image.nvim only has to fit it to the window. image.nvim on its own converts every
-- image to a full-size PNG while Neovim waits, which takes seconds for a large photo.
local uv = vim.uv or vim.loop
local M = {}

---@class (exact) coil.ThumbnailConfig
---@field size integer[] Largest thumbnail, {width, height} in pixels; smaller images keep their size
---@field dir string Where thumbnails are kept
---@field max_jobs integer Thumbnails made at the same time

---@type coil.ThumbnailConfig
local defaults = {
  size = { 600, 900 },
  dir = vim.fn.stdpath("cache") .. "/coil/thumbnails",
  max_jobs = 2,
}

---@type coil.ThumbnailConfig
local config = vim.deepcopy(defaults)

---@param opts? table See coil.ThumbnailConfig
M.setup = function(opts)
  config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
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

---@return boolean
M.available = function()
  return magick() ~= nil
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

---@class (exact) coil.ThumbnailJob
---@field src string
---@field out string
---@field callbacks coil.ThumbnailCallback[]
---@field prefetch boolean Nobody is waiting for it

---Jobs waiting to start, the next one first
---@type coil.ThumbnailJob[]
local queue = {}
---Jobs queued or running, by output path
---@type table<string, coil.ThumbnailJob>
local jobs = {}
local running = 0

local start_next

---@param job coil.ThumbnailJob
---@param thumb? string
---@param err? string
local function finish(job, thumb, err)
  jobs[job.out] = nil
  running = running - 1
  for _, cb in ipairs(job.callbacks) do
    cb(thumb, err)
  end
  start_next()
end

---@param job coil.ThumbnailJob
local function run(job)
  local cmd = magick()
  if not cmd then
    jobs[job.out] = nil
    for _, cb in ipairs(job.callbacks) do
      cb(nil, "ImageMagick (magick or convert) is not installed")
    end
    return
  end
  running = running + 1
  vim.fn.mkdir(config.dir, "p")
  -- Written under a temporary name and renamed when complete, so a half-written thumbnail is
  -- never drawn (by this Neovim or another one sharing the cache)
  local tmp = string.format("%s.%d.tmp", job.out, uv.os_getpid())
  local w, h = config.size[1], config.size[2]
  local src
  if job.src:lower():match("%.jpe?g$") then
    -- Read at up to twice the thumbnail's size, which lets the JPEG decoder skip detail the
    -- thumbnail can't show (much faster for photos). Unlike `-define jpeg:size`, it never
    -- enlarges small images.
    src = string.format("%s[%dx%d>]", job.src, w * 2, h * 2)
  else
    -- The first frame of an animation or the first page of a TIFF; otherwise every frame would
    -- be written as a separate file
    src = job.src .. "[0]"
  end
  local ok, err = pcall(vim.system, {
    cmd,
    src,
    -- Phone photos store their rotation separately
    "-auto-orient",
    -- Shrink to fit, never enlarge
    "-thumbnail",
    string.format("%dx%d>", w, h),
    "png:" .. tmp,
  }, { text = true }, function(result)
    vim.schedule(function()
      if result.code == 0 and uv.fs_rename(tmp, job.out) then
        finish(job, job.out)
      else
        uv.fs_unlink(tmp)
        local msg = vim.trim(result.stderr or ""):match("^[^\n]*")
        finish(job, nil, msg ~= "" and msg or "ImageMagick failed")
      end
    end)
  end)
  if not ok then
    vim.schedule(function()
      finish(job, nil, tostring(err))
    end)
  end
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
M.get = function(path, stat, cb)
  local out = M.path_for(path, stat)
  if exists(out) then
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
    job = { src = path, out = out, callbacks = { cb }, prefetch = false }
    jobs[out] = job
    table.insert(queue, 1, job)
  end
  start_next()
end

---Make thumbnails in the background, in this order, before anyone asks for them. Replaces the
---previous prefetch's files that haven't started yet; ones already being made are finished.
---@param files {path: string, stat: uv.fs_stat.result}[]
M.prefetch = function(files)
  queue = vim.tbl_filter(function(job)
    if job.prefetch then
      jobs[job.out] = nil
      return false
    end
    return true
  end, queue)
  for _, file in ipairs(files) do
    local out = M.path_for(file.path, file.stat)
    if not jobs[out] and not exists(out) then
      local job = { src = file.path, out = out, callbacks = {}, prefetch = true }
      jobs[out] = job
      table.insert(queue, job)
    end
  end
  start_next()
end

---Jobs queued or running, for tests
---@return integer
M.pending = function()
  return vim.tbl_count(jobs)
end

return M
