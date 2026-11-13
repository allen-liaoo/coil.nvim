-- Metadata cards for anything without a text preview: the name, a rule, then aligned rows (kind,
-- size, ...) and notes. coil highlights them itself and gives them their own filetype
-- (coil_card), so a card looks the same whatever markdown or other plugins are installed, and
-- whether or not its window has focus. Image cards end with room for the image (see image.lua).
local buffer = require("coil.preview.buffer")
local dimensions = require("coil.preview.dimensions")
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

---@param kind coil.PreviewKind
---@param info coil.ClassifyInfo
---@param opts coil.PreviewOpts
---@return nil|string
local function note_for(kind, info, opts)
  if info.note then
    return info.note
  elseif kind == "binary" then
    return "No text preview for binary files."
  elseif kind == "too_large" then
    return string.format(
      "Larger than %s, so the text preview is skipped.",
      M.format_size(opts.max_bytes)
    )
  elseif kind == "special" then
    return string.format("Not a regular file (%s).", info.stat and info.stat.type or "unknown")
  elseif kind == "unreadable" then
    return "Cannot read this file: " .. (info.err or "unknown error")
  elseif kind == "remote" then
    return "Previews of remote files are not supported yet."
  end
end

local ns = vim.api.nvim_create_namespace("coil_card")
local status_ns = vim.api.nvim_create_namespace("coil_card_status")

-- `default` keeps any colours the user set
M.set_highlights = function()
  for name, target in pairs({
    CoilCardTitle = "Title",
    CoilCardRule = "WinSeparator",
    CoilCardLabel = "Identifier",
    CoilCardValue = "Normal",
    CoilCardNote = "Comment",
  }) do
    vim.api.nvim_set_hl(0, name, { link = target, default = true })
  end
end

---@class (exact) coil.CardRow
---@field label string
---@field value string

---@param target coil.PreviewTarget
---@param kind coil.PreviewKind
---@param info coil.ClassifyInfo
---@return coil.CardRow[]
local function rows_for(target, kind, info)
  local rows = { { label = "Kind", value = kind_labels[kind] or kind } }
  if kind == "image" and target.path then
    local width, height = dimensions.read(target.path)
    if width then
      table.insert(rows, { label = "Dimensions", value = string.format("%d × %d", width, height) })
    end
  end
  local stat = info.stat
  if stat then
    vim.list_extend(rows, {
      {
        label = "Size",
        value = string.format("%s (%d bytes)", M.format_size(stat.size), stat.size),
      },
      {
        label = "Modified",
        value = os.date("%Y-%m-%d %H:%M", stat.mtime.sec) --[[@as string]],
      },
      { label = "Permissions", value = M.format_permissions(stat.mode) },
    })
  end
  local location = target.path and vim.fn.fnamemodify(target.path, ":~") or target.url
  table.insert(rows, { label = "Location", value = location })
  return rows
end

---@class (exact) coil.CardMark
---@field row integer 0-based
---@field col integer
---@field end_col integer
---@field hl string

---The card's lines and where each highlight goes:
---
---  name
---  ──────────
---  Kind         Image
---  Size         3.3M (3318385 bytes)
---  ...
---
---  A note, for some kinds
---@param target coil.PreviewTarget
---@param kind coil.PreviewKind
---@param info coil.ClassifyInfo
---@param opts coil.PreviewOpts
---@param draws_image? boolean coil draws the image below the card
---@return string[] lines
---@return coil.CardMark[] marks
local function build(target, kind, info, opts, draws_image)
  local rows = rows_for(target, kind, info)
  local label_width = 0
  for _, row in ipairs(rows) do
    label_width = math.max(label_width, #row.label)
  end

  local lines, marks = {}, {}
  local function add(line, hl, col, end_col)
    table.insert(lines, line)
    if hl then
      table.insert(marks, { row = #lines - 1, col = col or 0, end_col = end_col or #line, hl = hl })
    end
  end

  add(target.name, "CoilCardTitle")
  -- As wide as the widest row, filled in below
  add("", nil)
  local rule_row = #lines
  local width = vim.fn.strdisplaywidth(target.name)
  for _, row in ipairs(rows) do
    local label = row.label .. string.rep(" ", label_width - #row.label + 2)
    local line = label .. row.value
    add(line, "CoilCardLabel", 0, #row.label)
    table.insert(marks, { row = #lines - 1, col = #label, end_col = #line, hl = "CoilCardValue" })
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end
  lines[rule_row] = string.rep("─", math.min(width, 60))
  table.insert(
    marks,
    { row = rule_row - 1, col = 0, end_col = #lines[rule_row], hl = "CoilCardRule" }
  )

  local note = note_for(kind, info, opts)
  if note then
    add("", nil)
    add(note, "CoilCardNote")
  end
  if draws_image then
    -- A blank line, then the line the image starts on (see M.image_row)
    add("", nil)
    add("", nil)
  end
  return lines, marks
end

---The card's lines, without highlights
---@param target coil.PreviewTarget
---@param kind coil.PreviewKind
---@param info coil.ClassifyInfo
---@param opts coil.PreviewOpts
---@param draws_image? boolean coil draws the image below the card
---@return string[]
M.lines = function(target, kind, info, opts, draws_image)
  return (build(target, kind, info, opts, draws_image))
end

---@param target coil.PreviewTarget
---@param kind coil.PreviewKind
---@param info coil.ClassifyInfo
---@param opts coil.PreviewOpts
---@param draws_image? boolean coil draws the image below the card
---@return integer bufnr
M.render = function(target, kind, info, opts, draws_image)
  M.set_highlights()
  local lines, marks = build(target, kind, info, opts, draws_image)
  local bufnr = buffer.scratch(lines)
  for _, mark in ipairs(marks) do
    vim.api.nvim_buf_set_extmark(
      bufnr,
      ns,
      mark.row,
      mark.col,
      { end_col = mark.end_col, hl_group = mark.hl }
    )
  end
  -- Its own filetype, so markdown and other filetype plugins leave it alone; hook FileType
  -- coil_card to change it
  vim.bo[bufnr].filetype = "coil_card"
  return bufnr
end

---Show a dimmed note on line `row` ("Loading image..."), replacing any earlier one; nil removes it
---@param bufnr integer
---@param row integer 0-based
---@param msg? string
M.set_status = function(bufnr, row, msg)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  vim.api.nvim_buf_clear_namespace(bufnr, status_ns, 0, -1)
  if msg then
    vim.api.nvim_buf_set_extmark(
      bufnr,
      status_ns,
      row,
      0,
      { virt_text = { { msg, "CoilCardNote" } } }
    )
  end
end

---The 0-based line of an image card where the drawn image starts
---@param bufnr integer
---@return integer
M.image_row = function(bufnr)
  return vim.api.nvim_buf_line_count(bufnr) - 1
end

return M
