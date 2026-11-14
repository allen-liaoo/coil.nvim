# Architecture

coil.nvim adds two things to oil.nvim:

- **The column view**, a dedicated tab with three panes: parent | current | preview. You navigate
  in the middle pane, and the side panes follow it.
- **The preview module**, which shows a file's text or a picture of it, or a directory, in any window. The
  column view uses it, and `:CoilPreview` uses it on its own.

## Modules

```
plugin/coil.lua            :Coil, :CoilClose, :CoilPreview
lua/coil/
  init.lua                 public API: setup(opts), open(dir), close()
  config.lua               defaults, merging and validation of setup options
  oil_bridge.lua           the only module that uses oil.nvim (see oil-integration.md)
  util.lua                 debounce, window options for panes
  split_preview.lua        :CoilPreview, a preview split that follows any oil window
  view/                    the column view
    init.lua               open / close, lifecycle autocommands
    state.lua              the one open view: tab, pane windows, origin
    layout.lua             creates the side panes, sizes them by ratio
    sync.lua               keeps the side panes in step with the middle pane; titles
    side.lua               oil buffers in the side panes, showing only icons and names
    keys.lua               coil's keys, the parent-pane focus bounce
    commands.lua           commands typed in the middle pane that open something run in the editing tab
    open.lua               opens files in the editing tab
  preview/                 standalone preview module (no oil, no panes; see preview.md)
    init.lua               show(win, target) / clear(win)
    classify.lua           decides what kind of preview a target gets
    buffer.lua             scratch buffers, swapping buffers into windows
    image.lua              draws images with image.nvim, when it is set up
    providers/text.lua     text files
    providers/directory.lua  directory listings (also used by the parent pane)
```

The dependencies run one way. `preview/` depends on nothing else in coil. `view/` uses
`preview/` and `oil_bridge`. Only `oil_bridge` requires oil.nvim, including oil's public `oil.*`
API.

## The view's state

There is at most one column view per Neovim instance. `view/state.lua` holds it:

| Field | Meaning |
|---|---|
| `tab` | The view's tabpage |
| `panes` | Window IDs: `parent`, `current`, `preview` |
| `origin` | `{tab, win}`: where files open. Starts as the window `:Coil` was run from, and moves to wherever the last file opened. |
| `group` | The autocommand group for this view; deleted when the view closes |
| `cleanup` | Functions run once when the view goes away (e.g. stopping the debounce timer) |

Each pane window also carries `vim.w.coil_pane = "parent" | "current" | "preview"`.
`state.role_of(win)` answers which pane a window is.

## The middle pane is the source of truth

The side panes are derived from one thing: the oil buffer in the middle pane and its cursor.
coil never tracks "the current directory" separately. Whatever puts a directory in the middle
pane drives the same refresh: coil's `L`/`H`, oil's own `-` or `<CR>`, `:e oil://…`, or `:Coil dir`.

`view/sync.lua` does the refresh:

- **Parent pane:** shows the middle directory's parent as its oil buffer, with the cursorline on
  the middle directory (drawn with `CoilParentSelected`), scrolled into view. At the root it is
  empty.
- **Preview pane:** shows the entry under the middle pane's cursor: a directory as its oil buffer,
  anything else through the preview module.

The side panes' directories are oil's own buffers (`view/side.lua`), so oil's hidden-file rules,
sort, highlights and redraws apply to them as to any oil buffer, and `g.` shows or hides hidden
files in all three panes at once. They show only each entry's icon and name. oil's columns are
global, and oil keeps one buffer per directory, which the middle pane of this or another view may
show at the same time, so the other columns can't be left out of the buffer. They are hidden in
the side window only, by a conceal match (`matchaddpos`, which is per window) over the byte ranges
oil's line parser reports for each column (`oil_bridge.column_positions`). It is recomputed
whenever oil redraws the buffer. When a side pane shows a directory whose buffer oil already has,
coil has oil list it again, since oil would otherwise show the listing from when it was last
loaded.

Differences from the plain name lists the side panes used to be:

- A hidden current directory isn't in its parent's buffer while hidden files are hidden, so the
  parent pane then has no selection.
- With hidden files shown, oil lists `../` at the top of the side panes too.
- An empty directory's preview is blank: oil shows nothing for it.

It runs on these triggers:

| Trigger | Refreshes |
|---|---|
| A buffer enters the middle pane (`BufWinEnter`), once oil has listed it | Both side panes |
| The cursor moves in the middle pane (`CursorMoved`, debounced by `debounce_ms`, skipped in visual mode) | Preview only, and only if the entry under the cursor changed |
| oil finishes writing changes (`User OilMutationComplete`) | Both |
| Returning to the column view's tab (`TabEnter`) | Both |
| `g.` (toggle hidden files) in the middle pane | Both |
| oil's listing settings change — `gs` (sort), hidden files, `oil.set_sort()`, `oil.set_is_hidden_file()` — noticed when oil re-renders the middle buffer | Both |
| `:Coil` itself, once the middle directory is ready | Both (needed when `:Coil` runs inside another autocommand; see [Neovim windows](neovim-windows.md#autocommands-inside-autocommands)) |

Parent listings are asynchronous. Each one carries a generation number, and a listing that
finishes after a newer one started is dropped. The preview module does the same per window.

Commands typed in the middle pane are decided before they run (`view/commands.lua`). On
`CmdlineLeave`, the line is parsed with `nvim_parse_cmd`. If it opens something (`:Oil`, `:edit`
with a name, `:buffer`, `:split`, ...), it is cancelled and run again in the editing window, with
`%` and the like expanded where it was typed. So the middle pane only moves with coil's and oil's
keys and `:Coil`, and `:Oil` or `:e` on the middle pane's own directory still opens plain oil.
Telling commands apart from the buffer that lands in the middle pane doesn't work: oil keeps one
buffer per directory, so `:e <this dir>` looks just like a reload.

If something other than a directory still lands in the middle pane (a plugin, a `<Cmd>`
mapping), the file moves to the editing tab and the last directory comes back
(`open.redirect_from_middle`).

## Flows

### Opening: `:Coil [dir]`

1. If a column view is already open, switch to its tab and middle pane, and open `dir` there if
   given. Done.
2. Otherwise resolve `dir` while the original buffer is still current: no argument means the
   current buffer's directory, and if that buffer is a file, the cursor will land on it.
3. Remember the current window as `origin`.
4. `tabnew`. The new window becomes the middle pane. Its empty buffer is set to be wiped once
   replaced.
5. `layout.open` creates the parent pane (split left) and preview pane (split right) without
   moving focus. This happens before oil opens, so the side panes don't copy oil's window options.
6. Register the view's autocommands (lifecycle, sync, keys), then open the directory in the middle
   pane and apply the width ratio.
7. Once oil has listed the directory, fill the side panes and wrap the keys.

### Navigating

- `L` / `<CR>` on a directory: oil's `select` resolves the entry, and coil puts the resulting
  buffer into the middle pane. The sync above follows.
- `H`: oil's own "open parent", which puts the cursor back on the directory you came from.
- oil's own keys (`-`, `<CR>` outside coil, `_`, …) work too, because sync only watches the middle
  pane's buffer.

### Opening files

`L`, `<CR>`, `<C-s>`, `<C-h>` and `<C-t>` on a file go through `open.in_editing_tab`:

1. Pick the editing window: `origin` if it still exists outside the column view's tab, otherwise
   the current window of any other tab, otherwise a new tab.
2. Switch there and show the file: in place, in a vertical or horizontal split, or in a new tab.
3. Record that window as the new `origin`, so the next file opens next to this one.

The column view stays open in its tab. In visual mode, the open keys open every selected entry this
way.

### Closing

`:CoilClose`, `q`, closing any pane window, or closing the tab all end the view:

1. Forget the view and run its cleanup: stop timers, delete its autocommand group.
2. Close the tab. If it is the only tab, open a spare one first, because Neovim can't close the
   last tab.
3. Return to the origin window.

## Keys

Neovim has no window-local keymaps, and the middle pane's buffer is an ordinary oil buffer that
can also be shown in other windows. So coil wraps keys in each oil buffer that enters the middle
pane. When pressed, a wrapper checks which window it is in:

- In the column view's middle pane, it runs the coil action.
- Anywhere else, it runs what the key did before: oil's mapping if there was one, a global mapping,
  or Vim's built-in key (with its count).

| Action (config key) | Default | In the middle pane |
|---|---|---|
| `go_in` | `L` | Enter a directory; open a file in the editing tab |
| `go_out` | `H` | Parent directory |
| `open` | `<CR>` | Same as `go_in`; also in visual mode |
| `open_vsplit` / `open_split` / `open_tab` | `<C-s>` / `<C-h>` / `<C-t>` | Open in the editing tab as a split or tab; also in visual mode |
| `focus_preview` | `<C-p>` | Jump into the preview pane (pressed there, jump back) |
| `toggle_hidden` | `g.` | Toggle hidden files, keep the cursor on its entry, refresh the side panes |
| `close` | `q` | Close the view (also mapped in the preview pane) |

`L` and `H` are not wrapped in visual mode, so they stay Vim's motions for extending a selection.
See [oil.nvim integration](oil-integration.md#keymaps) for how wrapping survives oil reloading a
buffer.

The parent pane is display-only: entering it with `<C-w>h` bounces focus back to the middle pane
with a message. So is the preview pane while it shows a directory. Those are oil buffers, which
`modifiable` can't protect per window: the same buffer may be the middle pane of another view,
which must stay editable. So the panes can't be entered, and nothing can be edited in them.
Otherwise the preview pane can be entered to scroll or copy, and its buffers are read-only.

### Clicking

Clicking an entry in the parent pane, or in a preview that shows a directory, moves the middle
pane to the directory containing that entry, with the cursor on it. Clicking a sibling in the
parent pane makes it the current entry; clicking an entry in a directory preview goes into that
directory with the cursor on the entry.

Mouse mappings are looked up in the buffer that has focus before the click, so a mapping in the
parent pane's buffer would never run. Instead `keys.attach` watches for `<LeftMouse>` with
`vim.on_key` and, once the click has been processed, reads where it landed with `getmousepos()`.
Listing buffers record the directory they list in `b:coil_dir_url`, so only real listings react;
text previews and messages ignore clicks. A click is only accepted on a row that actually shows
an entry, not on the empty rows below the text.

## Titles

- **Tab title** (`tab_title`, on by default): the view's tab gets the tab variable `tabname` set
  to the middle directory as `~/path/`. Tab lines that read `tabname`, such as lualine's `tabs`
  component, show it. Neovim's built-in tab line does not.
- **Pane titles** (`winbar`, off by default): each pane gets a winbar with its path, or the entry
  name for the preview. Empty titles are kept as a blank line so the panes' rows stay aligned.
