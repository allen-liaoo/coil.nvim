-- An image's width and height, read from its file header: a few bytes for PNG, GIF, BMP and WebP,
-- and a walk over the segment headers for JPEG. No external tools, and nothing is decoded.
local uv = vim.uv or vim.loop
local M = {}

-- JPEG segments to step over before giving up (EXIF data, thumbnails, ICC profiles, ...)
local MAX_JPEG_SEGMENTS = 64

---@param fd integer
---@param offset integer
---@param n integer
---@return string
local function read(fd, offset, n)
  return uv.fs_read(fd, n, offset) or ""
end

---Unsigned integer from `n` bytes of `data` starting at `i` (1-based)
---@param data string
---@param i integer
---@param n integer
---@param little? boolean Little-endian
---@return integer
local function uint(data, i, n, little)
  local value = 0
  for k = 0, n - 1 do
    local byte = data:byte(little and (i + n - 1 - k) or (i + k)) or 0
    value = value * 256 + byte
  end
  return value
end

---@param fd integer
---@return nil|integer width
---@return nil|integer height
local function jpeg(fd)
  local offset = 2
  for _ = 1, MAX_JPEG_SEGMENTS do
    local header = read(fd, offset, 9)
    if #header < 4 or header:byte(1) ~= 0xFF then
      return nil
    end
    local marker = header:byte(2)
    -- Start of frame (SOF0-SOF15), except DHT (C4), JPG (C8) and DAC (CC)
    if
      marker >= 0xC0
      and marker <= 0xCF
      and marker ~= 0xC4
      and marker ~= 0xC8
      and marker ~= 0xCC
    then
      if #header < 9 then
        return nil
      end
      return uint(header, 8, 2), uint(header, 6, 2)
    end
    offset = offset + 2 + uint(header, 3, 2)
  end
end

---@param data string The first 30 bytes of a RIFF/WEBP file
---@return nil|integer width
---@return nil|integer height
local function webp(data)
  local chunk = data:sub(13, 16)
  if chunk == "VP8 " then
    return uint(data, 27, 2, true) % 0x4000, uint(data, 29, 2, true) % 0x4000
  elseif chunk == "VP8L" then
    local b1, b2, b3, b4 = data:byte(22, 25)
    if not b4 then
      return nil
    end
    local width = 1 + b1 + (b2 % 64) * 256
    local height = 1 + math.floor(b2 / 64) + b3 * 4 + (b4 % 16) * 1024
    return width, height
  elseif chunk == "VP8X" then
    return 1 + uint(data, 25, 3, true), 1 + uint(data, 28, 3, true)
  end
end

---The width and height of the image at `path`, if its format is one of PNG, JPEG, GIF, BMP and
---WebP and its header can be read. JPEGs report their stored size, before any EXIF rotation.
---@param path string
---@return nil|integer width
---@return nil|integer height
M.read = function(path)
  local fd = uv.fs_open(path, "r", 0)
  if not fd then
    return nil
  end
  local data = read(fd, 0, 30)
  local width, height
  if data:sub(1, 8) == "\137PNG\r\n\26\n" and #data >= 24 then
    width, height = uint(data, 17, 4), uint(data, 21, 4)
  elseif (data:sub(1, 6) == "GIF87a" or data:sub(1, 6) == "GIF89a") and #data >= 10 then
    width, height = uint(data, 7, 2, true), uint(data, 9, 2, true)
  elseif data:sub(1, 2) == "BM" and #data >= 26 then
    width, height = uint(data, 19, 4, true), uint(data, 23, 4, true)
    -- A negative height (stored top-down) as a 32-bit signed number
    if height >= 0x80000000 then
      height = 0x100000000 - height
    end
  elseif data:sub(1, 4) == "RIFF" and data:sub(9, 12) == "WEBP" then
    width, height = webp(data)
  elseif data:sub(1, 2) == "\255\216" then
    width, height = jpeg(fd)
  end
  uv.fs_close(fd)
  if width and height and width > 0 and height > 0 then
    return width, height
  end
  return nil
end

return M
