# Architecture

## Shape

- `view/` is the column view: a dedicated tab per view, with three split windows. Several views
  can be open, one per tab. `view/state.lua` keys them by tabpage and remembers the one used last
  (updated on `TabEnter`), which `:Coil` and `:CoilClose` fall back to when run outside a view.
- `preview/` previews a target in any window. The view's preview pane and `:CoilPreview`
  (`split_preview.lua`) both use it.
- `oil_bridge.lua` is the only door to oil. `startup.lua` and `editor.lua` serve standalone mode
  (see [Standalone](standalone.md)).

Dependencies run one way: `view/` uses `preview/` and the bridge; `preview/` uses neither.

## The middle pane drives everything

`view/sync.lua` derives both side panes from the middle pane's oil buffer and cursor:

- **Parent pane:** the middle directory's parent, with the cursor (and a window-local cursorline,
  highlighted `CoilParentSelected` through `winhighlight`) on the middle directory. At the root it
  is empty.
- **Preview pane:** the entry under the middle cursor. A directory is shown as its oil buffer
  (`view/side.lua`); anything else goes through `preview/`.

Whatever puts a directory in the middle pane triggers the same refresh: coil's `L`/`H`, oil's own
`-` or `<CR>`, `:Coil dir`. The triggers, and why each exists:

| Trigger | Why |
|---|---|
| `BufWinEnter` in the middle pane, then `on_ready` | A new directory. Waits for oil's listing, since the parent pane's cursor and the preview need entries. |
| `CursorMoved` in the middle pane, debounced (`debounce_ms`, 30) | Preview only, and only if the entry changed. Skipped in visual mode (selecting is editing, and redraws would flicker). |
| `User OilMutationComplete` | Files changed by `:w` in any oil buffer. |
| `TabEnter` into the view's tab | Files may have changed while away. |
| Lines of the middle buffer change and oil's `listing_signature()` differs | oil applies `gs`, `g.`, `oil.set_sort()` and `oil.set_is_hidden_file()` by re-rendering its buffers and fires no event. Comparing settings, rather than wrapping `gs`, also catches changes made from config or a plain oil window. `gs` finishes asynchronously (two `vim.ui.select` prompts), so wrapping it would be fiddly anyway. Ordinary edits cost one string comparison. |
| `view.open` once the directory is ready | `:Coil` run inside a non-nested autocmd gets no `BufWinEnter` (see [Neovim](neovim.md#autocmds-inside-autocmds)). |

A directory preview of a link is resolved through oil's adapter first, asynchronously, so the
preview pane shows the target's buffer itself (see [oil.nvim](oil.md#links-and-winfixbuf)).
Results that arrive after the cursor moved on are dropped (`st.preview_url` check).

When a directory enters the middle pane, `bridge.cursor_to_name` moves the cursor right to the
entry's name. oil only does that when it renders a buffer, and a buffer that a side pane already
rendered isn't rendered again, so it would arrive with the cursor at column 0. oil's
`constrain_cursor` option is no substitute: its default, `"editable"`, stops at the first
editable column (permissions, for example).

## Side panes are oil buffers

The parent pane and directory previews show oil's own buffer for the directory, so oil's
hidden-file rules, sort, highlights, `watch_for_changes` redraws and extensions such as
oil-git-status apply there too, and `g.` changes all three panes at once. (They used to be plain
name lists built from oil's adapter; `:CoilPreview` still uses those.)

Constraints that come from sharing buffers:

- **Only icon and name show, per window.** oil's columns are global and oil keeps one buffer per
  directory, which may be the middle pane of this or another view at the same time. So the other
  columns can't be left out of the buffer. Each side window hides them with its own conceal match
  (`matchaddpos`, per window) over the byte ranges oil's line parser reports
  (`bridge.column_positions`), recomputed whenever oil redraws the buffer.
- **A side pane can't be entered while it shows a directory.** `modifiable` is per buffer, and the
  buffer may be another view's middle pane, which must stay editable. So `WinEnter` bounces focus
  back to the middle pane with a message. The user accepted that a side pane shows unsaved edits
  made to the same directory in another window.
- **Redraws are watched with `nvim_buf_attach`.** `on_lines` runs inside oil's own
  `nvim_buf_set_lines`, so it only schedules work: an error there would abort oil's render.
- **`TextChanged` is fired by hand** for a side pane's buffer after oil redraws it. Neovim fires it
  only for the current buffer, and oil-git-status puts its signs back from it.
- **A directory shown again is listed again** (`refresh_dir`), since oil shows a hidden buffer's
  listing from when it was last loaded. Not when it has unsaved edits.

Visible differences from the old name lists: a hidden current directory has no selection while
hidden files are hidden (it isn't in the buffer), oil lists `../` when hidden files are shown,
and an empty directory's preview is blank.

## Keys

Neovim has no window-local keymaps, and the middle pane's buffer is an ordinary oil buffer that
other windows can show. So `view/keys.lua` wraps keys in each oil buffer that enters the middle
pane. A wrapper checks the window it runs in: in a view's middle pane it runs coil's action,
anywhere else what the key did before (oil's mapping, a global one, or the built-in key with its
count). The original is saved with `maparg()`; a key already wrapped (`desc` starts `coil: `) is
left alone, so wrapping is idempotent.

- **Wrap after oil, every time.** oil sets its keymaps when it sets a buffer up, and a reload
  (`<C-l>`, `:edit`, `:Coil` on the same directory) sets them up again over coil's. So keys are
  wrapped on `on_ready` after `BufWinEnter`, and again on every `User OilEnter` for the middle
  buffer. Without that, `<C-s>` would split the middle pane after a reload.
- **oil's own keys are read from oil's config** (`require("oil.config").keymaps`): those mapped
  to `actions.select` (with its `vertical`/`horizontal`/`tab` opts, and the
  `select_vsplit`/`select_split`/`select_tab` aliases), `actions.preview`,
  `actions.toggle_hidden` and `actions.close` get coil's version. Keys mapped to functions or
  commands are left alone. A key that is both coil's and oil's gets coil's action. Modes follow
  oil's mapping (oil's default mode `""` covers normal and visual).
- **`L` and `H` aren't wrapped in visual mode**, so they stay motions for extending a selection.
  The open keys are, because oil's versions act on a selection.
- **`g.` keeps the cursor on its entry.** oil's toggle keeps the line number, which lands on
  another entry once hidden entries appear above. coil hands the entry to oil's "last cursor"
  before toggling; if the entry is about to be hidden, the nearest one that stays (below, then
  above). oil refuses to toggle with unsaved oil buffers and says so itself.

### Clicks

Clicking an entry in the parent pane or a directory preview moves the middle pane to the
directory *containing* it, with the cursor on it: a sibling becomes the current entry, and an
entry in a preview is entered into its directory. Clicking a directory doesn't enter it (one
level further); that is a one-line change in `keys.jump_to_click` if wanted.

Mouse mappings are looked up in the buffer focused *before* the click, so a buffer-local
`<LeftMouse>` in a side pane would never run, and a global one would affect every window. So
`vim.on_key` watches for `<LeftMouse>` and, after the click is processed, reads `getmousepos()`.
Only rows that show an entry count. Headless Neovim gets no mouse input, so tests call
`jump_to_click` with `getmousepos()`-shaped tables; the real path was checked by hand.

## Commands typed in the middle pane

`view/commands.lua` decides a typed command before it runs. On `CmdlineLeave` the line is parsed
with `nvim_parse_cmd`; one that opens something (`:Oil`, `:edit` with a name, `:buffer`,
`:split`, ...) is cancelled and re-run in the editing window, with `%` and friends expanded where
it was typed. `:edit` without a name still reloads the middle pane, and other commands run there.

Why not look at what lands in the middle pane instead: oil keeps one buffer per directory, so
`:e <this dir>` looks exactly like a reload. That approach was tried and reverted. If something
other than a directory still lands in the middle pane (a plugin, a `<Cmd>` mapping),
`open.redirect_from_middle` moves it to the editing tab and puts the last directory back.

## Opening files

`open.in_editing_tab` picks the editing window: `origin` if it still exists outside every view,
otherwise the current window of a tab that isn't a view, otherwise a new tab. Files never open in
another view's tab. That window becomes the new `origin`, so the next file opens beside this one.
The view stays open in its tab.

`open_external` and `edit_here` are decided inside oil's `select` callback, not before calling
oil: oil only `bufadd`s the file before handing over the buffer, so a video is never read, and a
visual selection is sorted file by file for free. The buffer oil added is deleted unless the file
was already loaded. The split and tab keys always open in this Neovim: that is the way to edit a
binary file, or edit here, on purpose. External openers go through `vim.ui.open` on the path coil
already has; oil's `actions.open_external` only works on the cursor entry.

## Closing

`:CoilClose`, the close key, closing any pane, or closing the tab all end the view: its state is
forgotten, its autocmd group and timers go, and the tab closes. Neovim can't close its last tab,
so a spare one is opened first when the view's tab is the only one.

## Titles

- **Tab title:** the tab variable `tabname`, which tab lines such as lualine's `tabs` component
  show. Neovim's own tab line ignores it. Tab lines would otherwise name the tab after the focused
  buffer, which for an oil directory comes out empty, and for the preview pane's buffer is none.
- **Pane titles** (`winbar`): an empty title is kept as a blank line, so the panes' rows stay
  aligned. See [Neovim](neovim.md#winbar-is-global-local) for why titles are re-applied after every
  swap.
