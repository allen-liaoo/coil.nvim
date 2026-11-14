# Neovim windows

The column view's three panes are ordinary Neovim split windows in a dedicated tab. This page
describes the window machinery coil relies on, and the Neovim behaviours it works around. Each
of these was confirmed by running Neovim 0.12 headless; most have a regression test.

## Why split windows in a tab

Everything needed is in Neovim's API since 0.10:

- `nvim_open_win(buf, false, { split = "left" | "right", win = middle })` creates the side panes
  without moving focus.
- `nvim_win_set_buf(win, buf)` swaps a pane's buffer without focusing it.
- `nvim_win_set_width` and `'winfixwidth'` handle sizing.
- `WinClosed`, `TabClosed` and `VimResized` cover the lifecycle.

A dedicated tab keeps the column view out of your editing layout, so it can stay open while you
edit files in another tab. Real windows also mean `<C-w>` moves work, and each pane gets a normal
status line.

Floating windows were the alternative. They would need their own geometry, their own keys to move
between panes (`<C-w>h`/`l` don't move between floats), and hiding and restoring whenever a file
opens in the editing window. `view/layout.lua` is the only module that knows the panes are splits,
so a floating version could replace it later (see [TODO](todo.md)).

## Sizing

`layout.compute_widths(total, ratio)` splits the panes' combined width, minus the two separators,
by `ratio` (default `{1, 4, 3}`). Every width is at least 1.

- The parent and middle panes have `'winfixwidth'`, so when other windows open or close, the
  preview pane absorbs the change.
- The ratio is re-applied on `VimResized`. It uses the panes' combined width rather than the
  screen width, so a window you opened beside the panes keeps its size. If you drag a separator,
  your width stays until the next terminal resize.

## Keeping a pane's buffer: `'winfixbuf'`

The parent and preview panes have `'winfixbuf'`, which makes `:edit`, `:buffer` and similar
commands refuse to replace their buffer (error E1513). But `nvim_win_set_buf` refuses too, so
`preview/buffer.set_win_buf` turns the option off around coil's own swaps and back on after.

The middle pane doesn't have it, because oil's own navigation changes its buffer.

## Window options belong to a window and a buffer

A window option set like `:setlocal` only holds for the buffer the window shows at that moment.
At the next buffer swap the window falls back to its own defaults. Since coil swaps the side panes'
buffers constantly, `util.set_win_options` sets pane options like `:set` in that window
(`nvim_set_option_value` with a `win` and no scope). Then they hold for every buffer the pane
shows. Without this, a config with `number` on would grow line numbers in the side panes after
their first update.

The side panes use `number=false`, `relativenumber=false`, `signcolumn=no`, `foldcolumn=0`,
`wrap=false` and `winfixbuf`. The middle pane only gets `winfixwidth`; oil sets its own options
there (concealing the entry IDs, for example).

### `'winbar'` is different

`'winbar'` is a global-local option. A window's own value lasts only until its buffer changes,
and the global value would put a title on every window in Neovim. So `view/sync.lua` remembers
each pane's title and re-applies it after every buffer swap, from a `BufWinEnter` handler and
directly after swaps coil makes itself.

## No window-local keymaps

Neovim only has global and buffer-local keymaps. The middle pane's buffer is an ordinary oil
buffer, which can be shown in other windows and tabs at the same time. So coil's keys are
buffer-local wrappers that check, when pressed, whether they're in the column view's middle pane.
See [Architecture](architecture.md#keys).

## Autocommands inside autocommands

Inside an autocommand that isn't marked `nested`, Neovim doesn't fire any other autocommands.
`:Coil` run from one, such as `autocmd VimEnter * Coil` or the standalone build's startup code,
would therefore get none of the events coil and oil rely on:

- oil loads a directory from its `BufReadCmd` autocommand, so the middle pane stayed empty.
- coil fills the side panes from the middle pane's `BufWinEnter`, so they stayed empty.

coil handles this itself:

- `oil_bridge.open_dir` loads the directory explicitly when oil's loader didn't run, as oil does
  for its own preview window.
- `view.open` fills the side panes and wraps the keys directly once the directory is ready,
  instead of relying only on autocommands.
- Titles are re-applied right after swaps coil makes, not only from `BufWinEnter`.

The standalone build also marks its startup autocommand `nested`.

## Background tabs remember the wrong window

Swapping a window's buffer runs `BufEnter` inside that window. When the window's tab is in the
background, an autocommand that runs there can leave the tab remembering that window as its
focused one. oil's global `BufEnter` handler does this. It happened when a side pane updated
while you were in another tab, for example a directory preview finishing after a file opened in
the editing tab. Coming back to the column view then put focus in the preview or parent pane.

`preview/buffer.set_win_buf` notes the tab's focused window before each swap and restores it
afterwards with `nvim_tabpage_set_win` if it moved.

## Closing the last tab

Neovim can't close its last tab. When the column view's tab is the only one left, closing the view
opens a spare tab first.
