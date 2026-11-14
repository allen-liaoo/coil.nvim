-- Local copies of remote files (SSH, S3, ...) for previews. The copy is made by an injected
-- `fetch`, so this module knows nothing about oil. Copies live in this Neovim's temporary folder,
-- which Neovim deletes when it exits, and the least recently used go first past a size limit.
local uv = vim.uv or vim.loop
local M = {}

---Download `url` to the local file `dest`, calling `cb` on the main loop when done. Returns a
---function that stops the download (cb may still be called, with an error).
---@alias coil.Fetch fun(url: string, dest: string, cb: fun(err?: string)): nil|fun()

---@class (exact) coil.RemoteCopy
---@field path string
---@field size integer
---@field used integer When it was last used (a counter, not a time)

---@class (exact) coil.RemoteJob
---@field callbacks table<integer, fun(path?: string, err?: string)>
---@field cancel? fun()

---@type integer|false
local max_bytes = 100 * 1024 * 1024
---@type nil|string
local dir = nil
---@type table<string, coil.RemoteCopy>
local copies = {}
---@type table<string, coil.RemoteJob>
local jobs = {}
local total = 0
local clock = 0
local next_id = 0

---@param opts? {max_bytes?: integer|false} Size limit of all copies (false for none)
M.setup = function(opts)
  opts = opts or {}
  if opts.max_bytes ~= nil then
    max_bytes = opts.max_bytes
  end
end

---Identifies one version of a remote file: a changed size or time gets a new copy
---@param target coil.PreviewTarget
---@return string
M.key = function(target)
  return table.concat({ target.url, tostring(target.size), tostring(target.mtime) }, "|")
end

---@param copy coil.RemoteCopy
local function remove(copy)
  uv.fs_unlink(copy.path)
  uv.fs_rmdir(vim.fs.dirname(copy.path))
  total = total - copy.size
end

---Delete the least recently used copies until the rest fit the size limit
---@param keep string The key of the copy just made
local function evict(keep)
  if not max_bytes or total <= max_bytes then
    return
  end
  local keys = vim.tbl_keys(copies)
  table.sort(keys, function(a, b)
    return copies[a].used < copies[b].used
  end)
  for _, key in ipairs(keys) do
    if total <= max_bytes then
      break
    end
    if key ~= keep then
      remove(copies[key])
      copies[key] = nil
    end
  end
end

---The local copy of `target`, if one has been downloaded
---@param target coil.PreviewTarget
---@return nil|string path
M.cached = function(target)
  local key = M.key(target)
  local copy = copies[key]
  if copy and not uv.fs_stat(copy.path) then
    total = total - copy.size
    copies[key] = nil
    copy = nil
  end
  if copy then
    clock = clock + 1
    copy.used = clock
    return copy.path
  end
end

---@param key string
---@param job coil.RemoteJob
---@param part string
---@param dest string
---@param err? string
local function finish(key, job, part, dest, err)
  if jobs[key] == job then
    jobs[key] = nil
  end
  local stat = not err and uv.fs_stat(part)
  if stat and uv.fs_rename(part, dest) then
    if copies[key] then
      remove(copies[key])
    end
    clock = clock + 1
    copies[key] = { path = dest, size = stat.size, used = clock }
    total = total + stat.size
    evict(key)
  else
    uv.fs_unlink(part)
    err = err or "the download left no file"
  end
  for _, cb in pairs(job.callbacks) do
    if err then
      cb(nil, err)
    else
      cb(dest)
    end
  end
end

---Get a local copy of `target`, downloading it unless it is already there. Asking again for a
---file that is still downloading waits for the same download. Returns a function to call when the
---copy is no longer wanted; the download stops once nobody wants it.
---@param target coil.PreviewTarget
---@param fetch coil.Fetch
---@param cb fun(path?: string, err?: string)
---@return fun() release
M.download = function(target, fetch, cb)
  local cached = M.cached(target)
  if cached then
    cb(cached)
    return function() end
  end
  local key = M.key(target)
  next_id = next_id + 1
  local id = next_id
  local job = jobs[key]
  if job then
    job.callbacks[id] = cb
  else
    dir = dir or vim.fn.tempname() .. "-coil-remote"
    -- A folder per copy, so the copy keeps the file's name (filetype detection uses it)
    local folder = dir .. "/" .. vim.fn.sha256(key):sub(1, 16)
    vim.fn.mkdir(folder, "p")
    local dest = folder .. "/" .. target.name
    -- A cancelled download may still be writing its own part file
    local part = string.format("%s/.part%d", folder, id)
    job = { callbacks = { [id] = cb } }
    jobs[key] = job
    local cancel = fetch(target.url, part, function(err)
      finish(key, job, part, dest, err)
    end)
    -- fetch may have finished already
    if jobs[key] == job then
      job.cancel = cancel
    end
  end
  return function()
    if not job.callbacks[id] then
      return
    end
    job.callbacks[id] = nil
    if next(job.callbacks) == nil and jobs[key] == job then
      jobs[key] = nil
      if job.cancel then
        job.cancel()
      end
    end
  end
end

---Forget every copy and download, and delete the files (for tests)
M.clear = function()
  for _, copy in pairs(copies) do
    remove(copy)
  end
  copies = {}
  jobs = {}
  total = 0
end

return M
