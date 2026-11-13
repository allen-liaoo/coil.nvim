-- The only module that touches oil.nvim internals. oil's adapter API is documented as unstable,
-- so everything coil needs from oil goes through here.
local M = {}

local FIELD_NAME = 2
local FIELD_TYPE = 3
local FIELD_META = 4

---@param bufnr integer
---@return boolean
M.is_oil_buffer = function(bufnr)
  -- is_oil_bufnr returns true for loaded oil buffers, but the adapter name (e.g. "files") for
  -- ones oil hasn't loaded yet
  return vim.api.nvim_buf_is_valid(bufnr) and not not require("oil.util").is_oil_bufnr(bufnr)
end

---An oil directory listing (not a remote file, which also has an oil URL)
---@param bufnr integer
---@return boolean
M.is_oil_dir = function(bufnr)
  return M.is_oil_buffer(bufnr) and vim.endswith(vim.api.nvim_buf_get_name(bufnr), "/")
end

---Run `cb` once an oil buffer has finished its first listing
---@param bufnr integer
---@param cb fun()
M.on_ready = function(bufnr, cb)
  require("oil.util").run_after_load(bufnr, cb)
end

---@param entry oil.InternalEntry
---@return boolean
local function is_dir_entry(entry)
  local entry_type = entry[FIELD_TYPE]
  if entry_type == "directory" then
    return true
  end
  local meta = entry[FIELD_META]
  return entry_type == "link"
    and meta ~= nil
    and meta.link_stat ~= nil
    and meta.link_stat.type == "directory"
end

---oil's sort config, with oil's fallback when it is empty
---@return oil.SortSpec[]
local function sort_config()
  local sort = require("oil.config").view_options.sort
  if vim.tbl_isempty(sort) then
    return { { "type", "asc" }, { "name", "asc" } }
  end
  return sort
end

---The adapter's columns the sort uses (e.g. "size", "mtime"). Listing with these makes the
---adapter fetch what they need, as oil does for its own buffers: the files adapter only stats
---entries when a requested column requires it.
---@param adapter oil.Adapter
---@return string[]
local function sort_columns(adapter)
  local cols = {}
  for _, pair in ipairs(sort_config()) do
    if adapter.get_column and adapter.get_column(pair[1]) then
      table.insert(cols, pair[1])
    end
  end
  return cols
end

---A string that changes whenever oil's settings for what a listing shows, or in which order, change
---(sort, hidden-file rules, case and number handling). Compare two to detect `gs`, `g.`,
---`oil.set_sort()`, `oil.set_is_hidden_file()` and the like.
---@return string
M.listing_signature = function()
  local vo = require("oil.config").view_options
  return table.concat({
    vim.inspect(vo.sort),
    tostring(vo.show_hidden),
    tostring(vo.is_hidden_file),
    tostring(vo.is_always_hidden),
    tostring(vo.case_insensitive),
    tostring(vo.natural_order),
  }, "|")
end

---Sort entries exactly like oil does, by rebuilding its comparator from the sort config and
---oil's column sort functions (oil's own sort function is private to its view module).
---@param adapter oil.Adapter
---@param entries oil.InternalEntry[]
local function sort_entries(adapter, entries)
  local columns = require("oil.columns")
  local keys = {}
  for _, pair in ipairs(sort_config()) do
    local col = columns.get_column(adapter, pair[1])
    local get_value = col
      and (
        col.create_sort_value_factory and col.create_sort_value_factory(#entries)
        or col.get_sort_value
      )
    if get_value then
      table.insert(keys, { get_value, pair[2] })
    end
  end
  table.sort(entries, function(a, b)
    for _, key in ipairs(keys) do
      local a_val, b_val = key[1](a), key[1](b)
      if a_val ~= b_val then
        if key[2] == "desc" then
          return a_val > b_val
        end
        return a_val < b_val
      end
    end
    return a[FIELD_NAME] < b[FIELD_NAME]
  end)
end

---List a directory through oil's adapter for its URL scheme. Results are filtered by oil's
---hidden-file settings and sorted like oil sorts. Does not touch oil's cache.
---@param url string Directory URL, e.g. "oil:///home/me/"
---@param cb fun(err?: string, entries?: coil.ListEntry[])
---@param opts? {bufnr?: integer, always_show?: string} `bufnr` is passed to oil's is_hidden_file
---callbacks; an entry named `always_show` is listed even if it is hidden
M.list_dir = function(url, cb, opts)
  opts = opts or {}
  local adapter = require("oil.config").get_adapter_by_scheme(url)
  if not adapter then
    return cb(string.format("No oil adapter for '%s'", url))
  end

  ---@type oil.InternalEntry[]
  local raw = {}
  local finished = false
  -- Adapters may call back from libuv callbacks, where most of the API is off limits
  local finish = vim.schedule_wrap(function(err)
    if err then
      return cb(err)
    end
    local view = require("oil.view")
    ---@type table<oil.InternalEntry, boolean>
    local hidden = {}
    local visible = vim.tbl_filter(function(entry)
      local name = entry[FIELD_NAME]
      local display, is_hidden = view.should_display(name, opts.bufnr or 0)
      hidden[entry] = is_hidden
      return display or name == opts.always_show
    end, raw)
    sort_entries(adapter, visible)
    ---@type coil.ListEntry[]
    local entries = {}
    for _, entry in ipairs(visible) do
      table.insert(entries, {
        name = entry[FIELD_NAME],
        type = entry[FIELD_TYPE] or "file",
        is_dir = is_dir_entry(entry),
        is_hidden = hidden[entry] == true,
      })
    end
    cb(nil, entries)
  end)

  adapter.list(url, sort_columns(adapter), function(err, batch, fetch_more)
    if finished then
      return
    end
    if err then
      finished = true
      return finish(err)
    end
    vim.list_extend(raw, batch or {})
    if fetch_more then
      fetch_more()
    else
      finished = true
      finish()
    end
  end)
end

---Build a preview target for an entry of an oil buffer
---@param bufnr integer The oil buffer the entry belongs to
---@param entry oil.Entry
---@return coil.PreviewTarget
M.entry_target = function(bufnr, entry)
  local config = require("oil.config")
  local fs = require("oil.fs")
  local util = require("oil.util")
  local is_dir = util.is_directory(entry)
  local parent_url = vim.api.nvim_buf_get_name(bufnr)
  local url = parent_url .. entry.name .. (is_dir and "/" or "")
  local scheme, path = util.parse_url(url)
  ---@type coil.PreviewTarget
  return {
    name = entry.name,
    url = url,
    path = (scheme and config.adapters[scheme] == "files" and path) and fs.posix_to_os_path(path)
      or nil,
    is_dir = is_dir,
    unsaved = entry.id == nil,
  }
end

---The oil directory URL to open for `dir`, resolved from the current window's buffer
---@param dir? string A path or oil URL; nil means the current buffer's directory
---@return string url
---@return nil|string basename The file the current buffer shows, if any
M.url_for_path = function(dir)
  -- use_oil_parent=false: from an oil buffer, stay in that directory rather than its parent
  return require("oil").get_url_for_path(dir, false)
end

---The parent directory of an oil directory URL
---@param url string
---@return nil|string parent_url nil at the root
---@return nil|string name The directory's name inside its parent
M.parent_of = function(url)
  local parent_url, name = require("oil").get_buffer_parent_url(url, true)
  -- At the root oil returns the URL itself, with no name
  if parent_url == url or not name then
    return nil
  end
  return parent_url, name
end

---Open an oil directory in the current window
---@param url string
---@param focus_name? string Entry to put the cursor on once the listing renders
M.open_dir = function(url, focus_name)
  if focus_name then
    require("oil.view").set_last_cursor(url, focus_name)
  end
  require("oil").open(url)
  -- oil loads directories from its BufReadCmd autocmd, which doesn't fire when this runs inside
  -- another, non-nested autocmd (e.g. `autocmd VimEnter * Coil`). Load the buffer ourselves then,
  -- as oil does for its own preview window.
  local bufnr = vim.api.nvim_get_current_buf()
  if
    M.is_oil_buffer(bufnr)
    and not vim.b[bufnr].oil_ready
    and not require("oil.loading").is_loading(bufnr)
  then
    require("oil").load_oil_buffer(bufnr)
  end
end

---Open the parent directory in the current window. oil puts the cursor on the directory we left.
M.open_parent = function()
  require("oil").open()
end

---Select the entry under the cursor of the current (oil) window, handing the resulting buffer to
---`cb` instead of letting oil open it. Reuses oil's URL normalization and its "save before entering
---a new directory" guard.
---@param cb fun(bufnr: integer, is_dir: boolean)
M.select = function(cb)
  require("oil").select({
    handle_buffer_callback = function(bufnr)
      -- oil names directory buffers with a trailing slash. (Remote files have an oil scheme too,
      -- so the scheme alone doesn't tell.)
      cb(bufnr, vim.endswith(vim.api.nvim_buf_get_name(bufnr), "/"))
    end,
  })
end

---Toggle hidden files, keeping the cursor of `winid` (an oil window) on the same entry. oil itself
---keeps the cursor on the same line number, which lands on a different entry once hidden entries
---appear or disappear above it.
---@param winid integer
M.toggle_hidden = function(winid)
  local oil = require("oil")
  local view = require("oil.view")
  for _, bufnr in ipairs(view.get_all_buffers()) do
    if vim.bo[bufnr].modified then
      -- oil refuses to toggle with unsaved changes; let it explain
      return oil.toggle_hidden()
    end
  end

  local bufnr = vim.api.nvim_win_get_buf(winid)
  local hiding = require("oil.config").view_options.show_hidden
  local lnum = vim.api.nvim_win_get_cursor(winid)[1]
  local line_count = vim.api.nvim_buf_line_count(bufnr)

  ---@param l integer
  ---@return nil|string name The entry on line `l` if it stays visible after the toggle
  local function survivor(l)
    if l < 1 or l > line_count then
      return nil
    end
    local entry = oil.get_entry_on_line(bufnr, l)
    if not entry or entry.name == ".." then
      return nil
    end
    local _, is_hidden = view.should_display(entry.name, bufnr)
    if hiding and is_hidden then
      return nil
    end
    return entry.name
  end

  -- The entry under the cursor, or if it is about to be hidden, the nearest one below, then above
  local name = survivor(lnum)
  for offset = 1, line_count do
    name = name or survivor(lnum + offset) or survivor(lnum - offset)
    if name then
      break
    end
  end
  if name then
    -- oil's re-render moves the cursor to this entry
    view.set_last_cursor(vim.api.nvim_buf_get_name(bufnr), name)
  end
  oil.toggle_hidden()
end

---How a directory URL should read in a title: ~/path for local directories, the URL otherwise
---@param url string
---@return string
M.display_path = function(url)
  local config = require("oil.config")
  local scheme, path = require("oil.util").parse_url(url)
  if scheme and path and config.adapters[scheme] == "files" then
    return vim.fn.fnamemodify(require("oil.fs").posix_to_os_path(path), ":~")
  end
  return url
end

---The preview target for the entry under a window's cursor
---@param winid integer A window showing an oil buffer
---@return nil|coil.PreviewTarget
M.cursor_target = function(winid)
  local bufnr = vim.api.nvim_win_get_buf(winid)
  if not M.is_oil_buffer(bufnr) then
    return nil
  end
  local lnum = vim.api.nvim_win_get_cursor(winid)[1]
  local entry = require("oil").get_entry_on_line(bufnr, lnum)
  if not entry or entry.name == ".." then
    return nil
  end
  return M.entry_target(bufnr, entry)
end

---Preview targets for the entries around a window's cursor, nearest first (below before above):
---the lines at distance 1, then 2, and so on. The cursor's own entry isn't included.
---@param winid integer A window showing an oil buffer
---@param distance integer How many lines above and below the cursor
---@return coil.PreviewTarget[]
M.targets_near = function(winid, distance)
  local bufnr = vim.api.nvim_win_get_buf(winid)
  if not M.is_oil_buffer(bufnr) then
    return {}
  end
  local oil = require("oil")
  local lnum = vim.api.nvim_win_get_cursor(winid)[1]
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local targets = {}
  for d = 1, distance do
    for _, line in ipairs({ lnum + d, lnum - d }) do
      local entry = line >= 1 and line <= line_count and oil.get_entry_on_line(bufnr, line)
      if entry and entry.name ~= ".." then
        table.insert(targets, M.entry_target(bufnr, entry))
      end
    end
  end
  return targets
end

return M
