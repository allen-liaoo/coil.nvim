-- The single column view. There is at most one per Neovim instance.
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

---@type nil|coil.View
local view = nil

---The open view, if its tab still exists
---@return nil|coil.View
M.get = function()
  if view and not vim.api.nvim_tabpage_is_valid(view.tab) then
    view = nil
  end
  return view
end

---@param new coil.View
M.set = function(new)
  view = new
end

M.clear = function()
  view = nil
end

---Which pane a window is, if it belongs to the open view
---@param winid integer
---@return nil|coil.PaneRole
M.role_of = function(winid)
  local v = M.get()
  if not v then
    return nil
  end
  for _, role in ipairs(M.ROLES) do
    if v.panes[role] == winid then
      return role
    end
  end
end

return M
