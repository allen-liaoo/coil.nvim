-- Metadata "cards" for anything without a text preview. The card is a markdown buffer. Image cards
-- either leave room at the bottom for coil to draw the image (with image.nvim), or embed
-- `![](path)` for whatever markdown image renderer is installed.
local buffer = require("coil.preview.buffer")
local M = {}

local kind_labels = {
  image = "Image",
  video = "Video",
  audio = "Audio",
  pdf = "PDF document",
  archive = "Archive",
  binary = "Binary file",
  too_large = "Large file",
  special = "Special file",
  unreadable = "Unreadable",
  remote = "Remote file",
}

---@param size integer
---@return string
M.format_size = function(size)
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

---@param mode integer
---@return string
M.format_permissions = function(mode)
  local chars = { "r", "w", "x" }
  local out = {}
  for i = 8, 0, -1 do
    local is_set = bit.band(mode, bit.lshift(1, i)) ~= 0
    table.insert(out, is_set and chars[(8 - i) % 3 + 1] or "-")
  end
  return table.concat(out)
end

---@param path string
---@return string
local function markdown_destination(path)
  -- CommonMark allows <...> around destinations that contain spaces or parentheses
  if path:find("[%s()]") then
    return "<" .. path .. ">"
  end
  return path
end

---@param kind coil.PreviewKind
---@param info coil.ClassifyInfo
---@param opts coil.PreviewOpts
---@return nil|string
local function note_for(kind, info, opts)
  if kind == "binary" then
    return "No text preview for binary files."
  elseif kind == "too_large" then
    return string.format(
      "Larger than %s, so the text preview is skipped.",
      M.format_size(opts.max_bytes)
    )
  elseif kind == "video" or kind == "pdf" then
    return "Thumbnail preview is not available yet."
  elseif kind == "special" then
    return string.format("Not a regular file (%s).", info.stat and info.stat.type or "unknown")
  elseif kind == "unreadable" then
    return "Cannot read this file: " .. (info.err or "unknown error")
  elseif kind == "remote" then
    return "Previews of remote files are not supported yet."
  end
end

---@param target coil.PreviewTarget
---@param kind coil.PreviewKind
---@param info coil.ClassifyInfo
---@param opts coil.PreviewOpts
---@param draws_image? boolean coil draws the image below the card
---@return string[]
M.lines = function(target, kind, info, opts, draws_image)
  local lines = { "# " .. target.name, "" }
  table.insert(lines, string.format("- **Kind:** %s", kind_labels[kind] or kind))
  local stat = info.stat
  if stat then
    table.insert(
      lines,
      string.format("- **Size:** %s (%d bytes)", M.format_size(stat.size), stat.size)
    )
    table.insert(
      lines,
      string.format("- **Modified:** %s", os.date("%Y-%m-%d %H:%M", stat.mtime.sec))
    )
    table.insert(lines, string.format("- **Permissions:** %s", M.format_permissions(stat.mode)))
  end
  table.insert(lines, string.format("- **Location:** `%s`", target.path or target.url))

  local note = note_for(kind, info, opts)
  if note then
    vim.list_extend(lines, { "", note })
  end
  if draws_image then
    -- A blank line, then the line the image starts on (see M.image_row)
    vim.list_extend(lines, { "", "" })
  elseif kind == "image" and target.path then
    vim.list_extend(lines, {
      "",
      string.format("![%s](%s)", target.name, markdown_destination(target.path)),
    })
  end
  return lines
end

---@param target coil.PreviewTarget
---@param kind coil.PreviewKind
---@param info coil.ClassifyInfo
---@param opts coil.PreviewOpts
---@param draws_image? boolean coil draws the image below the card
---@return integer bufnr
M.render = function(target, kind, info, opts, draws_image)
  local bufnr = buffer.scratch(M.lines(target, kind, info, opts, draws_image))
  if opts.card_filetype then
    vim.bo[bufnr].filetype = opts.card_filetype
  end
  return bufnr
end

---The 0-based line of an image card where the drawn image starts
---@param bufnr integer
---@return integer
M.image_row = function(bufnr)
  return vim.api.nvim_buf_line_count(bufnr) - 1
end

return M
