# coil internals

Notes for whoever changes coil, human or agent. They hold what reading the code won't tell you:
why things are the way they are, the Neovim, oil.nvim and image.nvim behaviours coil works
around, alternatives that were tried or turned down, and measurements. Each module's header
comment and docstrings say what it does; these pages don't repeat them. User-facing behaviour
is in the [README](../../README.md); options and their defaults are in `lua/coil/config.lua`;
the Lua API and highlight groups are in [`doc/api.md`](../api.md) and
[`doc/highlights.md`](../highlights.md). `:help coil` (`doc/coil.txt`) is a copy of these
for reading in Neovim: change the source first, then the help.

| Page | Read it before changing |
|---|---|
| [Architecture](architecture.md) | How the panes stay in sync, keys, typed commands, where files open |
| [Neovim](neovim.md) | Anything about windows, window options, autocmds or tabs |
| [oil.nvim](oil.md) | Anything that calls oil, or relies on how oil renders, loads or names buffers |
| [Preview](preview.md) | Previews, images, thumbnails, remote files |
| [Standalone](standalone.md) | Standalone mode, the launcher, the Nix packages and nixvim module |
| [Development](development.md) | Tests, the dev shell, reproducing bugs without a real terminal |

## Rules that hold everywhere

- **The middle pane's oil buffer and cursor are the only state.** Never track "the current
  directory" separately; derive it from `nvim_win_get_buf(view.panes.current)`.
- **Only `oil_bridge.lua` requires oil**, including oil's public `oil.*` API. If you need
  something new from oil, add it to the bridge.
- **`preview/` knows nothing about oil or the column view.** Directory listing and downloading
  are passed in (`list_dir`, `fetch`). Keep it that way so `:CoilPreview` and the panes can share it.
- **Plain oil must stay unchanged.** Outside a column view's middle pane, every key, command and
  oil buffer behaves as if coil weren't installed. coil never hijacks `:Oil` or `:e`.
- **Standalone-only behaviour is opt-in** through the `standalone` options or the Nix build,
  never forced on plugin users.

## Terms

- **pane**: one of a view's three windows, `parent`, `current` (the middle pane) and `preview`.
  Each window carries `vim.w.coil_pane`. "Pane" rather than "column", to avoid confusion with:
- **oil column**: oil's per-line fields (icon, permissions, size, mtime).
- **editing window / editing tab**: where files open. It starts as the window `:Coil` was run
  from (`view.origin`) and moves to wherever the last file opened.
- **side panes**: the parent and preview panes.
