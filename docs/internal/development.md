# Development

The Makefile (`make help`) and `scripts/dev.lua`'s header cover the targets. What isn't obvious:

## Dev shell

- `nvim` on the dev shell's `PATH` is the maintainer's nvimx editor. Tests run on `COIL_NVIM`, a
  clean `neovim-unwrapped`, so no editor config affects results.
- Plugins come in through `COIL_*_PATH` variables (oil, plenary, image.nvim, oil-git-status), all
  from nixpkgs. A shell entered before a flake change lacks newer variables, and their specs then
  fail with "… is not set" (for example `git_status_spec.lua` without
  `COIL_OIL_GIT_STATUS_PATH`). Reload direnv, or run `nix develop -c make test`.
- `make dev` loads the working copy with `--cmd` because plugin scripts only load at startup;
  adding the repo to a running editor's runtimepath isn't enough. Without `make dev`, an editor
  runs whatever coil its config pins (the maintainer's nvimx pins the GitHub flake input), so an
  unpushed fix "doesn't work" there.

## Tests

- `make test` runs every spec, each in its own headless Neovim (about 12 s). Running one spec file
  directly with plenary fails to `require("tests.helpers")`; use the whole suite.
- `tests/minimal_init.lua` runs specs with `--noplugin`, so it loads `plugin/coil.lua` itself.
- **Wait for conditions, never sleep:** listings, oil reloads and debounced updates are
  asynchronous; use `h.wait` / `h.wait_lines`. After an oil reload, wait for that reload's
  `OilEnter`: until then the old state is still in place.
- **`h.setup_oil` resets oil's sort and `show_hidden`**, which `oil.setup()` doesn't undo, or sort
  tests leak into later ones. Pass options to it to test other oil configs; the cursor test uses
  `columns = { "icon", "permissions" }`, because oil's default (icon only) hides cursor bugs that an
  editable column before the name shows.
- **`h.press` types keys with mappings** (`feedkeys` with `"mx"`). `nvim_win_set_cursor` fires no
  `CursorMoved`; tests fire it themselves where the preview should follow.
- **`h.win_lines` reads what a side pane shows**, with coil's conceal and oil's IDs removed.
- Headless Neovim gets no mouse input and draws no images: click tests call `keys.jump_to_click`
  with `getmousepos()`-shaped tables, and image tests use a stand-in for image.nvim, plus one test
  that loads the real one to check the API coil uses still exists.

## Reproducing what reaches the terminal

For bugs in what the terminal shows (image placeholders, offsets, leftover cells), without a
display or the user's terminal:

1. Run coil inside a headless Neovim's `:terminal` (`jobstart(cmd, {term = true})`, keys with
   `chansend`), and read the screen from the terminal buffer's lines. image.nvim works there:
   with no pixel size from the pty it falls back to 8×16 cells. libvterm prints kitty graphics
   payloads as text, so don't trust its screen around images.
2. Wrap the inner Neovim in `script -q -O raw.log -c …` to record the exact bytes. Splitting on
   ESC (`sed 's/\x1b/\n<ESC>/g'`) shows every cursor move and where each draw lands.
3. Replay the bytes through kitty's real screen model with `kitty +runpy`: `set_options(defaults)`,
   `Screen(callbacks, lines, cols, 0, 10, 20, 0, callbacks)` with a stub callbacks object, and feed
   data with `test_create_write_buffer` / `test_commit_write_buffer` / `test_parse_written_data`
   (kitty doesn't ship its tests, which have this as `parse_bytes`).

Unset `TMUX` and `TMUX_PANE` for the inner Neovim, or image.nvim wraps commands for tmux
passthrough and writes deletes to the tmux pane you're in. To see what tmux itself makes of the
output, use a private server (`tmux -L <name> -f <conf>`) and `capture-pane`, never the one
you're working in.

## Formatting and checks

stylua for Lua (`make fmt`, `make fmt-check`), nixfmt for Nix (`nix fmt`). `nix flake check`
evaluates every output and runs the nixvim module checks.
