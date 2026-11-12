-- The only module that touches oil.nvim internals. oil's adapter API is documented as unstable,
-- so everything coil needs from oil goes through here.
local M = {}

local FIELD_NAME = 2
local FIELD_TYPE = 3
local FIELD_META = 4

---@param bufnr integer
---@return boolean
M.is_oil_buffer = function(bufnr)
  return vim.api.nvim_buf_is_valid(bufnr) and require("oil.util").is_oil_bufnr(bufnr) == true
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

---Sort entries exactly like oil does, by rebuilding its comparator from the sort config and
---oil's column sort functions (oil's own sort function is private to its view module).
---@param adapter oil.Adapter
---@param entries oil.InternalEntry[]
local function sort_entries(adapter, entries)
  local columns = require("oil.columns")
  local config = require("oil.config")
  local sort_config = config.view_options.sort
  if vim.tbl_isempty(sort_config) then
    sort_config = { { "type", "asc" }, { "name", "asc" } }
  end
  local keys = {}
  for _, pair in ipairs(sort_config) do
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
---@param opts? {bufnr?: integer} Buffer passed to oil's is_hidden_file callbacks
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
    local visible = vim.tbl_filter(function(entry)
      return (view.should_display(entry[FIELD_NAME], opts.bufnr or 0))
    end, raw)
    sort_entries(adapter, visible)
    ---@type coil.ListEntry[]
    local entries = {}
    for _, entry in ipairs(visible) do
      table.insert(entries, {
        name = entry[FIELD_NAME],
        type = entry[FIELD_TYPE] or "file",
        is_dir = is_dir_entry(entry),
      })
    end
    cb(nil, entries)
  end)

  adapter.list(url, {}, function(err, batch, fetch_more)
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

return M
