# Neovim behaviours coil works around

Each was confirmed in Neovim 0.12, headless; most have a regression test.

## Why split windows in a tab, not floats

The panes are plain splits in a dedicated tab. `nvim_open_win(buf, false, {split = ...})` and
`nvim_win_set_buf` place them and swap their buffers without moving focus, `<C-w>` moves work, and
each pane gets a normal status line. The view can stay open while you edit in another tab.

Floats would need their own geometry, their own keys to move between panes (`<C-w>h`/`l` don't
move between floats), and hiding and restoring whenever a file opens. `view/layout.lua` is the
only module that knows the panes are splits, so a float layout could replace it.

## Sizing

The parent and middle panes have `winfixwidth`, so the preview pane absorbs width changes when
other windows open or close. The ratio is re-applied on `VimResized` only, from the panes'
combined width rather than the screen's, so a window opened beside the panes keeps its size and a
dragged separator stays until the next terminal resize.

## `winfixbuf` refuses `nvim_win_set_buf` too

The side panes have `winfixbuf` so `:edit` and friends can't replace their buffer (E1513). It also
makes `nvim_win_set_buf` fail, so `preview/buffer.set_win_buf` turns it off around coil's own
swaps. Anything else that swaps buffers in those windows fails the same way, including oil itself
(see [oil.nvim](oil.md#links-and-winfixbuf)). The middle pane doesn't have it: oil's navigation
changes its buffer.

## Window options are per window and buffer

An option set like `:setlocal` only holds for the buffer the window shows at that moment; at the
next swap the window falls back to its own values. coil swaps side-pane buffers constantly, so
`util.set_win_options` sets them like `:set` run in that window (`nvim_set_option_value` with
`win` and no `scope`). Otherwise a config with `number` on would grow line numbers in the side
panes after their first update.

Side panes showing an oil buffer get oil's window options (sign column for git status, conceal);
`side.release` puts `cursorline`, `conceallevel` and `signcolumn` back before anything else goes
in.

### `winbar` is global-local

A window's own `winbar` only lasts until its buffer changes, and setting the global value titles
every window in Neovim. So `view/sync.lua` remembers each pane's title and re-applies it on
`BufWinEnter`, and directly after swaps coil makes (which may run inside an autocmd, where
`BufWinEnter` doesn't fire).

## Autocmds inside autocmds

Inside an autocmd that isn't `nested`, Neovim fires no other autocmds. `:Coil` run from one
(`autocmd VimEnter * Coil`, standalone startup) would get none of the events coil and oil rely on:
oil loads directories from `BufReadCmd`, so the middle pane stayed empty, and coil fills the side
panes from `BufWinEnter`. So:

- `oil_bridge` loads a directory buffer itself when oil's loader didn't run, as oil does for its
  own preview window.
- `view.open` fills the side panes and wraps the keys once the directory is ready, instead of
  relying only on autocmds.
- Titles are re-applied right after coil's own swaps.
- Standalone startup's `VimEnter` autocmd is `nested`.

## Background tabs remember the wrong window

Swapping a window's buffer runs `BufEnter` inside that window. If the window's tab is in the
background, an autocmd running there (oil's global `BufEnter` handler does) can leave the tab
remembering that window as its focused one. It happened when a side pane updated while the user
was in another tab, e.g. a directory preview finishing after a file opened in the editing tab;
coming back put focus in the preview pane. `set_win_buf` notes the tab's focused window before
each swap and restores it with `nvim_tabpage_set_win`.

## `TextChanged` only fires for the current buffer

Plugins that redecorate a buffer after it changes (oil-git-status) never hear about changes to a
buffer that isn't current, which a side pane's never is. coil fires it for them (see
[Architecture](architecture.md#side-panes-are-oil-buffers)).

## Cursor after a buffer enters a window

An oil buffer a side pane already showed arrives in the middle pane with the cursor where the side
pane left it (column 0, since side panes set `{lnum, 0}`), not on the name. Nothing moves it: oil
isn't rendering, and oil's `CursorMoved` constraint didn't take effect in the repro either (see
[Architecture](architecture.md#the-middle-pane-drives-everything)).
