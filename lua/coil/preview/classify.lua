-- Decide how to preview a target without relying on external tools like file(1).
local uv = vim.uv or vim.loop
local M = {}

---@alias coil.PreviewKind "directory"|"text"|"image"|"video"|"audio"|"pdf"|"archive"|"binary"|"too_large"|"special"|"unreadable"|"remote"

---@class (exact) coil.ClassifyInfo
---@field stat? uv.fs_stat.result
---@field err? string
---@field note? string Shown on the card (e.g. a tool to install)

local function set(list)
  local ret = {}
  for _, v in ipairs(list) do
    ret[v] = true
  end
  return ret
end

-- Formats recognized by extension. These never get a text preview, whatever their size.
local by_extension = {
  image = set({
    "png",
    "jpg",
    "jpeg",
    "gif",
    "webp",
    "bmp",
    "tif",
    "tiff",
    "ico",
    "avif",
    "heic",
    "svg",
  }),
  video = set({ "mp4", "mkv", "webm", "mov", "avi", "m4v", "flv", "wmv" }),
  audio = set({ "mp3", "flac", "wav", "ogg", "opus", "m4a", "aac" }),
  pdf = set({ "pdf" }),
  archive = set({ "zip", "tar", "gz", "tgz", "xz", "bz2", "zst", "7z", "rar" }),
}

---@param name string
---@return nil|string
local function extension(name)
  local ext = name:match("%.([^.]+)$")
  return ext and ext:lower()
end

---@param path string
---@param nbytes integer
---@return nil|string data
---@return nil|string err
local function read_head(path, nbytes)
  local fd, open_err = uv.fs_open(path, "r", 0)
  if not fd then
    return nil, open_err
  end
  local data, read_err = uv.fs_read(fd, nbytes, 0)
  uv.fs_close(fd)
  return data, read_err
end

---The kind a file name's extension alone decides, if any (image, video, ...)
---@param name string
---@return nil|coil.PreviewKind
M.kind_by_name = function(name)
  local ext = extension(name)
  for kind, exts in pairs(by_extension) do
    if ext and exts[ext] then
      return kind
    end
  end
end

---@param target coil.PreviewTarget
---@param opts coil.PreviewOpts
---@return coil.PreviewKind
---@return coil.ClassifyInfo
M.classify = function(target, opts)
  if not target.path then
    return "remote", {}
  end
  local stat, stat_err = uv.fs_stat(target.path)
  if not stat then
    return "unreadable", { err = stat_err }
  end
  if stat.type == "directory" then
    return "directory", { stat = stat }
  elseif stat.type ~= "file" then
    -- Reading a fifo or device could block, so never open one
    return "special", { stat = stat }
  end

  local kind = M.kind_by_name(target.name)
  if kind then
    return kind, { stat = stat }
  end

  if stat.size > opts.max_bytes then
    return "too_large", { stat = stat }
  end
  local head, read_err = read_head(target.path, opts.sniff_bytes)
  if not head then
    return "unreadable", { stat = stat, err = read_err }
  end
  if head:find("\0", 1, true) then
    return "binary", { stat = stat }
  end
  return "text", { stat = stat }
end

return M
