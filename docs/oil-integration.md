# oil.nvim integration

coil builds on oil.nvim rather than replacing it. The middle pane is a real oil buffer, and the
side panes list directories through oil's adapters. coil also reaches into some of oil's internals,
and oil's adapter API is documented as unstable. So everything coil uses from oil goes through one
module, `lua/coil/oil_bridge.lua`.

coil is developed and tested against oil.nvim commit
[`d3733d9`](https://github.com/stevearc/oil.nvim/tree/d3733d933833a0e59b813ecec99341527adf0c28),
which the flake pins.

## What the bridge provides

| Function | What it does | oil pieces used |
|---|---|---|
| `is_oil_buffer(buf)` | Is this an oil buffer, loaded or not | `oil.util.is_oil_bufnr` |
| `is_oil_dir(buf)` | An oil directory, as opposed to a remote file (which also has an oil URL) | name ends in `/` |
| `on_ready(buf, cb)` | Run `cb` once oil has listed the buffer | `oil.util.run_after_load` |
| `list_dir(url, cb, opts)` | List a directory as plain entries, filtered and sorted like oil | adapter `list`, `oil.view.should_display`, `oil.columns` sort functions |
| `entry_target(buf, entry)` / `cursor_target(win)` | Turn an oil entry into a preview target | `oil.get_entry_on_line`, `oil.util.is_directory` |
| `url_for_path(dir)` | The oil URL to open for a path | `oil.get_url_for_path` |
| `parent_of(url)` | Parent URL and name, or nothing at the root | `oil.get_buffer_parent_url` |
| `open_dir(url, focus)` | Open a directory in the current window, cursor on `focus` | `oil.open`, `oil.view.set_last_cursor`, `oil.load_oil_buffer` |
| `open_parent()` | oil's "go to parent" | `oil.open` |
| `select(cb)` | Resolve the entry (or visual selection) under the cursor, hand each buffer to `cb` | `oil.select{ handle_buffer_callback }` |
| `toggle_hidden(win)` | Toggle hidden files, keeping the cursor on its entry | `oil.toggle_hidden`, `oil.view.set_last_cursor` |
| `display_path(url)` | `~/path/` for local directories, the URL otherwise | `oil.util.parse_url`, `oil.fs` |

## Listing directories for the side panes

The parent pane and directory previews are plain name lists, not oil buffers. `list_dir`:

- **Calls the URL's adapter directly** (`adapter.list(url, {}, cb)`), so local, SSH, S3 and trash
  directories all work. It requests only the oil columns your sort uses (for example `size` or
  `mtime`), so local listings skip `stat` calls unless the sort needs them (oil still stats
  symlinks, and entries `readdir` couldn't type). Results stream in batches, and coil keeps
  requesting more until the adapter is done. It never touches oil's cache, so oil's own buffers
  are unaffected.
- **Filters with oil's hidden-file rules** (`show_hidden`, `is_hidden_file`, `is_always_hidden`)
  through `oil.view.should_display`, and marks hidden entries, which the side panes grey out.
  `always_show` lists one named entry even if hidden: the parent pane uses it for the directory
  you're in.
- **Sorts exactly like oil.** oil's comparator is private, so the bridge rebuilds it from your
  `view_options.sort` and oil's column sort functions (`create_sort_value_factory` /
  `get_sort_value`). A directory preview is therefore in the same order you'll see after entering
  it.
- **Calls back on Neovim's main loop.** Adapters may call back from libuv callbacks, where most of
  the API is off limits.

A missing directory lists as empty, as it does in oil.

### Following oil's listing settings

oil applies a sort change (`gs`, `oil.set_sort()`), a hidden-files toggle or new hidden-file rules
by re-rendering its own buffers, and fires no event. coil watches the middle buffer's lines
(`nvim_buf_attach`). When they change, it compares `listing_signature()` — oil's sort, hidden-file
settings, case and number handling — with the one the side panes were drawn with, and refreshes
them if it differs. Ordinary edits in the middle pane leave the signature unchanged, so they cost
one string comparison.

## Keymaps

oil sets its keymaps per buffer when it sets a buffer up. coil wraps its own keys on top, once oil
is done:

- When an oil directory enters the middle pane, coil waits for oil to have listed it (`on_ready`),
  then wraps.
- **After every oil setup** (`User OilEnter`) of the buffer in the middle pane, coil wraps again.
  Reloading a buffer — `<C-l>` (refresh), `:e`, or `:Coil` on the directory already shown — re-runs
  oil's setup, which sets oil's keymaps over coil's. Without re-wrapping, `<C-s>` and friends would
  split the middle pane until the next directory change.
- Wrapping is idempotent: a key already wrapped by coil (recognised by its `coil: ` description) is
  left alone, and the original mapping is saved with `maparg()` for the fallback.
- The open keys are wrapped in visual mode too, because oil's versions act on a selection.

## Opening entries

coil never re-implements oil's entry handling. `select` uses oil's public
`select({ handle_buffer_callback = … })`, which gives coil the resolved buffer instead of opening
it. That keeps oil's URL normalization and its safety checks, such as refusing to enter a directory
you typed but haven't saved. Directories go into the middle pane; files go to the editing tab.

oil's `select` can't tell coil whether a buffer is a directory, and a remote file's buffer has an
oil URL just like a directory. coil goes by oil's naming: directory buffers end in `/`.

## Toggling hidden files

oil's `toggle_hidden` keeps the cursor on the same line number, so when hidden entries appear or
disappear above it, the cursor lands on a different entry. coil's `g.` records the entry under the
cursor and hands it to oil's "last cursor" before toggling, and oil's re-render puts the cursor
back on it. If hiding would remove that entry, the nearest entry that stays visible (below, then
above) is used. oil refuses to toggle while any oil buffer has unsaved changes; coil then lets oil
show its message.

## oil behaviours coil handles

| oil behaviour | How coil deals with it |
|---|---|
| oil's preview (`<C-p>`) opens a split marked `'previewwindow'`, and oil's global handlers close or update such windows | coil's preview pane never sets `'previewwindow'`, and `<C-p>` in the middle pane is coil's "jump to preview" |
| `is_oil_bufnr` returns `true` for loaded oil buffers but the adapter name (e.g. `"files"`) for ones not loaded yet | `is_oil_buffer` tests truthiness, not `== true` |
| oil loads directories from `BufReadCmd`, which doesn't fire inside a non-nested autocommand | `open_dir` calls `oil.load_oil_buffer` itself when needed ([details](neovim-windows.md#autocommands-inside-autocommands)) |
| oil's global `BufEnter` handler, run during a buffer swap in a background tab, leaves that tab remembering the wrong window | the tab's focused window is restored after each swap ([details](neovim-windows.md#background-tabs-remember-the-wrong-window)) |
| `get_buffer_parent_url` returns the URL itself at the root | `parent_of` returns nothing there, and the parent pane stays empty |
| An entry typed but not saved has no listing or file | Its preview says "Not saved yet" |
| A directory argument (`nvim some/dir`) has already become an `oil:///…/` URL by `VimEnter` | the standalone build's startup code accepts oil URLs as directories |

## Plain oil is unchanged

Outside the column view's middle pane, coil changes nothing about oil: `:Oil`, floating oil,
`nvim some/dir` and every oil key behave as usual. oil's `:w` still saves every modified oil buffer
at once, inside and outside the column view.
