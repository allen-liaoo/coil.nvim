# coil.nvim internals

These pages explain how coil.nvim is built and why. For installing and using coil, see the
[top-level README](../README.md).

| Page | What it covers |
|---|---|
| [Architecture](architecture.md) | The modules, the column view's state, and what happens when you open, navigate, open a file and close |
| [Neovim windows](neovim-windows.md) | How the three panes are plain Neovim windows, and the window behaviours coil has to work around |
| [oil.nvim integration](oil-integration.md) | Everything coil uses from oil.nvim, kept in one bridge module, and the oil behaviours it handles |
| [Preview](preview.md) | The standalone preview module: classification, text, picture and directory previews |
| [Standalone coil](standalone.md) | The Nix packages: the `coil` file manager command and the plugin |
| [Development](development.md) | Dev shell, tests, launching the working copy, formatting |
| [TODO](todo.md) | What's planned next |

## Terms

| Term | Meaning |
|---|---|
| **pane** | One of the column view's three windows: `parent` (left), `current` (middle) and `preview` (right). coil says "pane" instead of "column" to avoid confusion with oil columns. |
| **oil column** | oil.nvim's per-line metadata fields (icon, size, permissions, mtime). Unrelated to panes. |
| **middle pane** | The `current` pane. It shows a real oil buffer; the other two show plain read-only buffers coil draws. |
| **editing tab** | Where files open: the window `:Coil` was run from, then wherever the last file opened. |
| tabpage / window / buffer | Neovim's layers. A tab holds windows, a window shows one buffer, and the same buffer can be in several windows, each with its own cursor. |
| scratch buffer | An unnamed buffer with `buftype=nofile` that is never written to disk. coil uses them for listings and previews. |
| buffer-local keymap | A mapping that only exists in one buffer. Neovim has no window-local keymaps, which shapes how coil's keys work. |
| autocommand | A callback Neovim runs on an event, such as `BufWinEnter`, `WinClosed` or `CursorMoved`. |
| extmark | A position-tracked annotation in a buffer. coil uses them to highlight lines without moving the cursor. |
| adapter | oil.nvim's backend for one kind of storage (files, ssh, s3, trash). Each lists directories with `list(url, columns, cb)`. |
| `OilEnter` | A `User` event oil fires when it has finished setting up an oil buffer and listing it. |
