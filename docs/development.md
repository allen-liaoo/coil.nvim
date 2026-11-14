# Development

## Dev shell

`nix develop` (or `direnv allow`, using `.envrc`) gives you:

| Tool / variable | Purpose |
|---|---|
| `nvim` | The maintainer's nvimx editor with its Lua preset |
| `COIL_NVIM` | A clean, unconfigured `neovim-unwrapped`. Tests run on this, so editor config never affects results. |
| `COIL_OIL_PATH` | The pinned oil.nvim source (flake input `oil-nvim`) |
| `COIL_PLENARY_PATH` | plenary.nvim, the test runner |
| `stylua`, `lua-language-server`, `make` | Formatting, language server, task runner |

## Make targets

| Target | Does |
|---|---|
| `make test` | Runs the headless test suite with `COIL_NVIM` |
| `make dev` | Opens `nvim` (your editor) with this working copy of coil, the pinned oil and image.nvim loaded |
| `make dev-clean` | The same in a clean Neovim without your config |
| `make dev-standalone` | `make dev` in standalone mode, as `coil` would start it. Directories and other Neovim arguments go in `ARGS`, for example `make dev-standalone ARGS="~/a ~/b"`, or `ARGS="--cmd \"let g:coil_cwd_file = '/tmp/cwd'\""` for cd on exit |
| `make dev-standalone-clean` | The same in a clean Neovim |
| `make fmt` / `make fmt-check` | Format, or check formatting of, `lua/`, `plugin/`, `scripts/` and `tests/` with stylua |
| `make help` | Lists the targets |

`make dev` runs `nvim --cmd "luafile scripts/dev.lua"`. The script runs before plugin scripts load:
it adds the repository, `COIL_OIL_PATH` and `COIL_IMAGE_PATH` to the runtimepath and calls
`oil.setup()` and `coil.setup()`. image.nvim is set up on `VimEnter`, after your config, with
the standalone build's options, unless your config set it up already. Adding the repository to
the runtimepath of an editor that is already running
isn't enough, because plugin scripts only load at startup. The standalone targets put
`--cmd "let g:coil_standalone = 1"` before it, so `coil.setup()` already sees standalone mode.

Nix files are formatted with `nix fmt` (nixfmt). `nix flake check` evaluates every flake output.

## Tests

The tests use plenary.nvim's busted runner. Each `*_spec.lua` file runs in its own headless Neovim,
started with `tests/minimal_init.lua`. That file adds the repository, the pinned oil.nvim and
plenary to the runtimepath. Test files run with `--noplugin`, so it also loads `plugin/coil.lua`
explicitly.

| File | Covers |
|---|---|
| `tests/env_spec.lua` | The dev environment: Neovim version, oil loads |
| `tests/config_spec.lua` | Defaults, merging, type errors, unknown-option warnings |
| `tests/oil_bridge_spec.lua` | Listing (filtering, oil's sort order, hidden marking, oil's cache untouched), cursor targets, display paths |
| `tests/preview/classify_spec.lua` | Classification of text, binary, large, media, missing and remote targets |
| `tests/preview/preview_spec.lua` | Text previews, messages for files without one, buffer wiping, `'winfixbuf'`, directory listing, stale results dropped |
| `tests/split_preview_spec.lua` | `:CoilPreview` |
| `tests/view/layout_spec.lua` | Width maths |
| `tests/view/view_spec.lua` | Opening, sizing, resizing, closing in every way, focus kept when side panes update in the background, opening from inside an autocommand |
| `tests/view/sync_spec.lua` | Parent listing and highlight, preview following the cursor, navigation (coil's and oil's), root, refresh after saving, hidden directories, pane options and titles, tab title |
| `tests/view/keys_spec.lua` | Every key, split keys after oil reloads and in visual mode, editing-tab routing, fallback outside the column view, the focus bounce, `g.` keeping the cursor |

`tests/helpers.lua` has shared helpers: `setup_oil` (which also resets oil's sort and hidden-file
settings, because `oil.setup()` doesn't undo `oil.set_sort()` or a toggle), temporary directories
with resolved paths, opening oil or
the column view and waiting for it to list (`open_view`), waiting for a window's lines
(`wait_lines`), reading highlights (`selected_lines`, `line_highlights`), and typing keys so that
mappings run (`press`).

Many operations are asynchronous (listings, oil's reloads, debounced updates), so tests wait for
conditions with `vim.wait` instead of sleeping for fixed times. When a test checks behaviour after
an oil reload, it waits for oil's `OilEnter` from that reload, because before then the old state is
still in place.

Behaviour that clean-Neovim tests can't show is worth checking with `make dev` in a real editor
too: highlighting, how images are drawn, interactions with your own config and mappings.
