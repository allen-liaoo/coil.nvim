-- The open column views, one per tab. Each tab can hold one view, and several can be open, like
-- yazi's tabs.
local M = {}

---@alias coil.PaneRole "parent"|"current"|"preview"

---@class (exact) coil.Panes
---@field parent integer
---@field current integer
---@field preview integer

---@class (exact) coil.View
---@field tab integer The view's tabpage
---@field panes coil.Panes Window IDs
---@field origin {tab: integer, win: integer} Where :Coil was run from; files open there
---@field group integer Autocmd group for this view
---@field cleanup fun()[] Run once when the view goes away

M.ROLES = { "parent", "current", "preview" }

---@type table<integer, coil.View>
local views = {}
-- The view used most recently, which :Coil switches back to
---@type nil|coil.View
local last = nil

---Forget views whose tab no longer exists
local function prune()
  for tab in pairs(views) do
    if not vim.api.nvim_tabpage_is_valid(tab) then
      views[tab] = nil
    end
  end
  if last and not views[last.tab] then
    last = nil
  end
end

---The view in `tab` (default: the current tab), if any
---@param tab? integer
---@return nil|coil.View
M.get = function(tab)
  prune()
  return views[tab or vim.api.nvim_get_current_tabpage()]
end

---The view used most recently, if any is still open
---@return nil|coil.View
M.last = function()
  prune()
  if last then
    return last
  end
  -- None used yet (or it was closed): any open view
  local _, view = next(views)
  return view
end

---Every open view
---@return coil.View[]
M.all = function()
  prune()
  return vim.tbl_values(views)
end

---Whether `view` is still open
---@param view coil.View
---@return boolean
M.is_open = function(view)
  prune()
  return views[view.tab] == view
end

---@param view coil.View
M.add = function(view)
  views[view.tab] = view
  last = view
end

---Remember `view` as the one used most recently
---@param view coil.View
M.touch = function(view)
  if M.is_open(view) then
    last = view
  end
end

---@param view coil.View
M.remove = function(view)
  if views[view.tab] == view then
    views[view.tab] = nil
  end
  if last == view then
    last = nil
  end
end

---The view a window belongs to, and which pane it is
---@param winid integer
---@return nil|coil.View
---@return nil|coil.PaneRole
M.find = function(winid)
  if not vim.api.nvim_win_is_valid(winid) then
    return nil
  end
  local view = M.get(vim.api.nvim_win_get_tabpage(winid))
  if not view then
    return nil
  end
  for _, role in ipairs(M.ROLES) do
    if view.panes[role] == winid then
      return view, role
    end
  end
end

---Which pane a window is, if it belongs to a view
---@param winid integer
---@return nil|coil.PaneRole
M.role_of = function(winid)
  local _, role = M.find(winid)
  return role
end

return M
