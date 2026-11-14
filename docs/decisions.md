# Decisions to review

Choices made while working through the TODO list without checking in. Each says what was decided,
why, and what the alternative was, so it can be changed.

## Side panes follow a sort change

- **Detection is generic, not tied to `gs`.** coil watches the middle buffer for oil's re-render
  and compares oil's listing settings (sort, hidden-file rules, case, natural order) with the ones
  the side panes were drawn with. This also catches `g.` pressed in a plain oil window and
  `oil.set_sort()` / `oil.set_is_hidden_file()` called from config.
  *Alternative:* wrap only the `gs` key. Rejected, because `gs` finishes asynchronously
  (two `vim.ui.select` prompts) and other ways of changing the sort would be missed.
- **Side-pane listings fetch the sort's columns.** With `size` or `mtime` in the sort, the files
  adapter now `stat`s each entry in side-pane listings, like oil does for its own buffers. Without
  it the side panes would be in a different order from the middle pane. The cost only applies when
  such a sort is active.
- **Tests reset oil's sort and `show_hidden` in `setup_oil`.** `oil.setup()` doesn't undo
  `oil.set_sort()` or a toggle (they change oil's default `view_options` table in place), which made
  sort tests leak into later tests. This is oil behaviour coil can't change.

## Click to jump

- **What a click does:** the middle pane moves to the directory *containing* the clicked entry,
  with the cursor on it. Clicking `zdir/` in the parent pane makes `zdir/` the current entry (its
  contents show in the preview); it does not enter `zdir/`. Clicking an entry in a directory
  preview enters the previewed directory with the cursor on that entry. This keeps "the clicked
  thing becomes the selection" consistent for files and directories.
  *Alternative:* clicking a directory enters it directly (one level further). Easy to switch in
  `keys.jump_to_click`.
- **Detection with `vim.on_key`, not mappings.** Mouse mappings are looked up in the buffer focused
  before the click, so buffer-local `<LeftMouse>` maps in the side panes never run; a global
  mapping would affect every window. `vim.on_key` observes the click without changing what it does
  anywhere else.
- **Only left clicks on listing rows react.** Text previews, messages, the empty rows below a
  listing and the middle pane behave as usual. Focus moves to the middle pane after a jump.
- **Not unit-tested end to end:** headless Neovim doesn't receive simulated mouse input, so the
  tests call `keys.jump_to_click` with `getmousepos()`-shaped tables. The real path was checked in
  a terminal (tmux, xterm mouse sequences): parent-pane click, directory-preview click, and a click
  on the empty rows (ignored).

## Image previews

- **coil calls image.nvim itself** instead of relying on its markdown integration to draw the
  card's `![](path)`. That way coil decides the size (the rest of the pane, rather than
  image.nvim's default cap of half the window's height), when to draw (after the cursor rests,
  `image_delay_ms`, because image.nvim blocks while ImageMagick converts and resizes), and when to
  remove it. The embed line is left out when coil draws, so the markdown integration doesn't draw a
  second copy.
  *Alternative:* keep the embed and leave all drawing to image.nvim's markdown integration (zero
  coupling, but no control over size or timing).
- **The image goes below the metadata card**, not instead of it, so size and location stay
  visible. *Alternative:* image only, like yazi. (Since changed to image only: see
  [No file details in the preview](#no-file-details-in-the-preview).)
- **image.nvim is optional for the plugin.** `nix/coil-nvim.nix` doesn't depend on it, and the
  lazy.nvim example lists it as a dependency the user sets up. Without it, or with
  `preview.images = false`, cards embed `![](path)` as before, so snacks.nvim still works.
- **"Is image.nvim set up?" is checked through `:ImageReport`**, which image.nvim's `setup()`
  defines. image.nvim has no public check, and `from_file()` throws until setup has run.
- **The standalone `coil` includes image.nvim** (your request) with the kitty backend, and
  ImageMagick appended to `PATH`. Setup is a plain `require("image").setup()` (your edit; it was in
  `pcall` before). Inside tmux without `allow-passthrough` the kitty backend raises an error, which
  aborts the rest of the init, so the column view doesn't open (checked in tmux). Wrapping it in
  `pcall` again makes coil fall back to the card alone there. Sixel and ueberzug backends aren't chosen automatically.
- **Testing:** headless Neovim has no terminal to draw in, so most tests use a stand-in for
  image.nvim that records calls. One test loads the real image.nvim from the dev shell
  (`COIL_IMAGE_PATH`) to check that the API coil uses still exists. The real drawing was checked in
  tmux with passthrough: the image lands inside the preview pane, below the card.

## Image thumbnails

- **600×900, as you chose,** like yazi's default. image.nvim then shrinks it to the pane (about
  0.1 s, cached by image.nvim for the session).
- **JPEGs are read with a size hint in the file name (`photo.jpg[1200x1800>]`)**, not
  `-define jpeg:size=…`: the define lets libjpeg decode *larger* than the original (a 50×60 JPEG
  came out 100×120), the file-name form never enlarges. It can't be combined with the `[0]` frame
  selector, so only JPEGs get it; JPEGs have one frame anyway.
- **"Loading thumbnail..." shows until the picture is drawn**, cached or not (your request). It
  used to appear only when the thumbnail wasn't cached, so cached images didn't flash a note
  for the 100 ms delay, but then the pane was blank meanwhile.
- **`thumbnail_size` is only read by `setup()`**, not per `preview.show()` call: the thumbnail
  module and its cache are shared by every preview window.
- **Measured** in a real terminal on a 4000×3000 JPEG: first view drawn after 1.7 s, revisits
  after 0.16 s (mostly the 100 ms delay), and Neovim never stalled more than 34 ms. Before, it was
  about 13 s with Neovim frozen throughout.
- **Copies at the drawn size.** Even with a cached thumbnail, moving to a new image took about
  1 s: image.nvim scales any image whose width differs from what it will draw, and it does that
  while Neovim waits (`magick -scale`, with the PNG's default compression, which is most of the
  cost). coil now predicts that size, using image.nvim's own `image/utils/term` (cell size) and
  `image/utils/math` (`adjust_to_aspect_ratio`), and makes `<thumbnail>-WxH.png` in the
  background with light PNG compression. These are image.nvim internals, so coil only uses them
  through `pcall`: if they change or the prediction is off, image.nvim scales the image itself,
  as before. Prefetched images get these copies too, estimated from the card layout. Measured:
  moving to a prefetched photo now draws after 158 ms, of which the draw is 3 ms (it was 937 ms).
  *Alternative:* leave it to image.nvim (simple, about 1 s per new image on a large pane).
- **No prediction with fractional cell sizes** (terminal pixel size not a multiple of the
  columns): image.nvim compares widths exactly, so it would scale anyway.

## Thumbnail cache limit

- **200 MiB by default** (`preview.thumbnail_cache_mb`, `false` for no limit). A 600×900 thumbnail
  plus its pane-sized copy is roughly 0.5–1.5 MB, so that's a few hundred images.
- **Least recently used first, tracked in the files' modification times.** coil resets a
  thumbnail's modification time when it draws it; access times aren't used because many systems
  mount disks with `noatime`/`relatime`.
- **Cleanup goes down to 80% of the limit**, so it doesn't run again on every new thumbnail. It
  lists the cache folder each time it runs, which keeps the count right when several Neovims
  share the cache. The folder is listed on the main thread; for a few hundred files that's a few
  milliseconds. *Alternative:* list it asynchronously (`fs_scandir` with a callback), if large
  caches turn out to stall.
- **Leftover temporary files** (from a job that was killed) are deleted once older than an hour;
  younger ones may belong to a running job, in this or another Neovim.
- **`:CoilClearCache`** deletes every thumbnail except temporary files still being written.

## Info cards instead of markdown

(Since replaced: see [No file details in the preview](#no-file-details-in-the-preview).)

- **Why:** markdown cards depended on the user's markdown plugins (one renders badly when the
  preview isn't focused), and the `![](path)` embed left image size and timing to whichever
  plugin drew it, which undid the thumbnail work. The card is now coil's own buffer (filetype
  `coil_card`) with extmark highlights, in the spirit of grug-far's panel.
- **Layout:** name (`CoilCardTitle`), a rule as wide as the widest row up to 60 columns
  (`CoilCardRule`), aligned label/value rows (`CoilCardLabel`/`CoilCardValue`), notes
  (`CoilCardNote`). Plain text underneath, so yanking from the preview gives readable lines.
- **Location** is shown with `~` for the home directory.
- **Removed:** `preview.card_filetype` and the markdown embed. Without image.nvim, image cards show
  the details only. *Possible later:* a snacks.nvim image drawer behind `preview/image.lua`, if
  choosing the image plugin matters.
- **Dimensions** are read from the file header (PNG, JPEG, GIF, BMP, WebP) without external tools.
  JPEGs report their stored size; a phone photo with an EXIF rotation shows its width and height
  swapped compared with how it's drawn. Reading the EXIF orientation would fix that, if it matters.

## Video and PDF thumbnails

- **ffmpeg only, not ffmpegthumbnailer:** anyone with video tools almost always has ffmpeg, and
  one tool keeps the code and the "install X" note simple. `ffprobe` gets the duration first, so
  the frame is taken 10% of the way in (seeking before `-i`, which is fast: 0.12 s for both steps
  on a 20 s 1080p video), skipping black intros. Without a duration, the first frame.
- **PDF:** `pdftoppm -singlefile -scale-to-x 600 -scale-to-y -1`, the first page 600 px wide
  (0.03 s). A very tall page can come out taller than 900 px; image.nvim then fits it anyway.
- **Same pipeline as images:** cache, size limit, prefetch, exact-size copies. Each kind has a
  "maker" in thumbnail.lua; the rest is shared.
- **Missing tool → note on the card** ("Install poppler (pdftoppm) to see the first page."), shown
  only when image.nvim is set up (otherwise nothing could be drawn anyway).
- **Not in the standalone build yet:** ffmpeg-headless and poppler-utils add about 300 MB and
  150 MB with their dependencies. Added to the "fuller standalone build" TODO instead.
- **Not done:** duration or page count on the card. That needs ffprobe/pdfinfo before the card
  is drawn, or updating the card afterwards.

## oil's keys in the column view

- coil reads oil's configured `keymaps` (`require("oil.config").keymaps`) and wraps the keys mapped
  to `actions.select` (and its `vertical`/`horizontal`/`tab` opts, and the `select_vsplit`/
  `select_split`/`select_tab` aliases), `actions.preview`, `actions.toggle_hidden` and
  `actions.close`. Keys mapped to functions or custom commands aren't touched.
- **coil's own keys:** `go_in` (`L`), `go_out` (`H`) and `close` (`q`), which have no oil
  equivalent (or, for `q`, are a file-manager convention). A key that is both coil's and oil's gets
  coil's action.
- **Modes follow oil's config:** select keys are wrapped in normal and visual mode when oil maps
  them there (oil's default mode `""` covers both); the others in normal mode only.
- The preview pane maps oil's preview keys (back to the middle pane) and coil's and oil's close
  keys.
- **Old option names** (`keymaps.open_vsplit`, ...) just get the usual unknown-option warning.

## Several directories in tabs

- **`:Coil dir1 dir2 ...`** (and `require("coil").open({ dir1, dir2 })`): the first directory goes
  where `:Coil dir` would put it (the current tab's view, otherwise the one used last, otherwise a
  new one); each further directory opens another column view in a new tab. Focus ends on the
  first. *Alternative:* every directory opens a new tab even when a view is open.
- **One view per tab**, kept in `view/state.lua` by tabpage, plus the one used most recently
  (updated on `TabEnter`), which `:Coil` without arguments switches to from elsewhere.
- **No `:CoilTab` command or new-tab key:** `:Coil` with several directories covers it, and tabs
  are switched with Neovim's own keys (`gt`, `gT`).
- **Files never open in another view's tab:** the editing window is the origin window if it's
  outside every view, otherwise the current window of a tab that isn't a view, otherwise a new tab.
- **`:CoilClose`** closes the current tab's view, or the one used last when run elsewhere.
- **Standalone `coil dir1 dir2`** opens one view per directory when every argument is a directory
  (any file among them: plain Neovim). The tab Neovim started with is closed afterwards, for plain
  `coil` too, so the views are the only tabs; the first file opened goes into a new tab. Its
  start buffers (including oil's buffer for the first directory argument, unless a view reuses
  it) are deleted. The arglist is cleared.

## Standalone config file

- **`~/.config/coil/init.lua`** (`stdpath("config")` with `NVIM_APPNAME=coil`; the app name was
  `coil-nvim`, which moved state and history to new directories).
- **Plain Lua that may return setup options** `{ oil = ..., coil = ..., image = ... }`, deep-merged
  into the build's defaults (`require("coil.standalone").defaults`), so each plugin's `setup()`
  runs once. `image = false` skips image.nvim. *Alternative:* let the file call the `setup()`s
  itself (more freedom, but the build's defaults would be lost or set up twice).
- **Errors** in the file are reported with a warning, and the defaults are used.
- **The startup moved into `lua/coil/standalone.lua`** (shipped with the plugin, only called by the
  standalone build), so it's tested with the rest; `nix/coil.nix` just calls `start()`.
- **Adding plugins** from the config file isn't supported; the build's plugin set is fixed.

## Delete to trash

- **Only in the standalone build** (`standalone.defaults.oil.delete_to_trash = true`). As a
  plugin, coil leaves oil's setting alone: that's the user's oil config.
- oil implements the trash itself (freedesktop trash on Linux, the macOS and Windows ones
  elsewhere), so no tool is added to the build. Opt out with `oil = { delete_to_trash = false }`.

## A fuller standalone build

- **Icons: mini.icons**, not nvim-web-devicons: oil supports both, and mini.icons needs no Nerd Font
  fallback logic of its own. `icons = false` in the config file leaves it off.
- **Tree-sitter grammars: 30 common ones** (shells, C family, web, JVM, Go, Rust, Python, Ruby, PHP,
  Nix, config formats, git files) via `nvim-treesitter.withPlugins`, which also brings their
  highlight queries. *Alternative:* `withAllGrammars` (every grammar, a much larger closure).
- **ffmpeg-headless and poppler-utils** are on the build's `PATH` (appended, so the user's own
  come first). The closure grew from 399 MB to 610 MB; the earlier 300 MB + 150 MB estimate
  ignored dependencies shared with ImageMagick and Neovim.

## Entry details

- The standalone build sets oil's `columns = { "icon", "permissions", "size", "mtime" }`; the side
  panes stay names only (they're coil's own listings).
- **Lists in the config file replace the build's** (e.g. `columns = { "icon" }`), key/value
  tables merge. `vim.tbl_deep_extend` would have merged `columns` index by index.

## `q` quits (standalone)

- **A general `quit` key** (`:confirm qall`, so unsaved buffers, including unsaved oil edits, get a
  prompt), off in the plugin and mapped to `q` by the standalone build, which unmaps `close`
  there. Also in the preview pane.
- **Quits everything,** like yazi's `q`, even with several column views or edited files open.
  Closing one view is still oil's close key (`<C-c>`) or `:CoilClose`. *Alternative:* quit only
  when the last view closes.

## cd on exit

- **`bin/coil` is now a bash script** (`writeShellScript`) that takes coil's own arguments
  (`--cwd-file <path>` / `--cwd-file=<path>`) and execs the wrapped Neovim with the rest; `--`
  passes everything after it to Neovim. It hands the path to Lua as `$COIL_CWD_FILE`. Later
  arguments (`--chooser-file`, `--help`, ...) go in the same place.
- **Which directory:** the current tab's column view, otherwise the one used last, otherwise the
  last local directory any view's middle pane showed (tracked on `BufWinEnter`). Non-local
  directories (SSH, S3) are skipped. Written without a trailing slash or newline, like yazi.
- **The shell functions** (bash/zsh and fish) live in `docs/shell-integration.md`, linked from the
  README, as asked; that doc is committed. The suggested name is `cl`. Both were checked with a
  stand-in `coil` that writes a directory.
- **Update: no Tree-sitter grammars after all.** Text previews fall back to Neovim's built-in
  regex syntax files (`syntax = <filetype>`), which cover nearly every language; Neovim also ships
  Tree-sitter for C, Lua, Markdown, Vim script and its help files. Dropping nvim-treesitter and the
  30 grammars cut the closure from 610 MB to 570 MB. Checked: Python and Nix previews highlight.

## Standalone mode in your own Neovim (2026-11-13)

One Neovim config can run both as itself and as a file manager. The mode is the global variable
`g:coil_standalone`, set by the launcher with `nvim --cmd "let g:coil_standalone = 1"`.

- **Why a global variable:** `--cmd` runs before the user's config, so a function it calls must
  already be loadable. That holds for packages (`pack/*/start`, the Nix build) but not for plugin
  managers that add plugins in init.lua (lazy.nvim). It's also the convention: Firenvim's
  `g:started_by_firenvim`, kitty-scrollback.nvim's `KITTY_SCROLLBACK_NVIM`.
- **Rejected: `nvim +Coil -- <coil args>`.** Everything after `--` is a file name to Neovim, so
  `--cwd-file` would become a buffer coil has to clean up. Fragile.
- **Rejected: `nvim +"Coil <args>"`.** Paths would have to be escaped into an Ex command line.
- **Rejected: `nvim +Coil!`** (like `nvim +Man!`). It runs after init.lua, so configs couldn't
  branch on the mode while they load.
- **The `standalone` option** applies in standalone mode, defaulting to
  `keymaps = { close = false, quit = "q" }`. Its types are checked in either mode, so mistakes
  show up before Neovim is first started as a file manager.
- **Data stays out of command strings:** the cwd file reaches Neovim as `COIL_CWD_FILE`, never
  interpolated into `--cmd` (kitty-scrollback's issue #377 shows why).
- **Layer order:** coil's defaults, coil's standalone defaults, the user's options, the user's
  standalone options. Options the user set win over coil's standalone defaults, so the Nix build's
  config file can set `coil = { keymaps = { quit = "Q" } }` without knowing about `standalone`.
- **Code layout:** `coil.standalone` is the mode (opening views for the command line, the cwd
  file), run from plugin/coil.lua in any Neovim with the variable set. `coil.standalone.build` is
  only the Nix build's setup (its config file, oil/image/icon defaults, colour scheme), which sets
  the variable itself too, so a bare run of the build's Neovim is still a file manager.
- **One launcher, `bin/coil`:** the Nix build substitutes its Neovim's path into the same script
  rather than keeping its own copy, and the plugin package ships it. It unsets an inherited
  `COIL_CWD_FILE`, and Neovim clears it once read, so `:terminal` children don't pick it up. The
  last line uses `${args[@]+...}` because bash 3.2 (macOS) treats an empty array as unset under
  `set -u`.
- **Startup only:** `coil.standalone.init()` does nothing after VimEnter, so a lazily loaded coil
  doesn't reopen views mid-session; the README tells lazy.nvim users not to lazy-load in that mode.

## The Nix `coil` only bundles (2026-11-13)

Every feature of the file manager lives in standalone mode (`bin/coil` + `g:coil_standalone`),
usable from any Neovim. The Nix package adds only what someone without Neovim needs: Neovim,
the plugins, the preview tools, and default setups for those plugins.

- **The config file is Neovim's own.** The build no longer supplies an init (`wrapRc = false`;
  the wrapper adds plugins with `--cmd "set packpath^=…"` either way), so `NVIM_APPNAME=coil`
  makes Neovim read `~/.config/coil/init.lua` as an ordinary config. The returned-table config and
  `coil.standalone.build` (load_config, merging) are gone. It also stops `VIMINIT` from leaking
  into Neovims started from `:terminal`.
- **Fallback setups, not merged defaults:** `nix/defaults/plugin/coil_defaults.lua` runs after the
  user's init and sets up only what it didn't: oil (if `:Oil` doesn't exist; with trash and the
  details columns), mini.icons (if `MiniIcons` is nil), image.nvim (if `:ImageReport` doesn't
  exist), habamax (if `g:colors_name` is nil). A user's own `oil.setup{}` is used as written, as
  setup() calls work anywhere else. Lives in nix/, since it's packaging, not coil.
- **The oil defaults stay in the build only:** `delete_to_trash` and the columns are oil options,
  so with your own Neovim they're your config's business (the README shows branching on
  `require("coil").standalone()`).
- **`NVIM_APPNAME` is the switch for a separate config,** for `bin/coil` too
  (`NVIM_APPNAME=coil coil`). Known gap: `--set-default NVIM_APPNAME` is inherited by Neovims
  started from the build's `:terminal`; clearing it inside Neovim would move stdpath() mid-session.
- **Public Lua API is `require("coil")` only** (setup, open, close, standalone). The startup code
  is the internal `coil.startup`.
- **README:** only what you can't learn by trying (install, commands, keys, options, the two
  file-manager setups); no pane drawing, behaviour list or preview details.

## g:coil_cwd_file, and no launcher in the plugin (2026-11-13)

- **Neovim refuses unknown options** (`nvim: Unknown option argument`), so an alias can't take
  `--cwd-file`; only something that parses arguments before Neovim can. The plugin doesn't ship
  one: your own Neovim uses an alias, and the cwd file is a global variable set with `--cmd`, like
  the mode. It's read at exit, and global variables aren't inherited by `:terminal` children.
- **The Nix `coil` keeps `--cwd-file`** in its own launcher, `nix/coil.sh` (placeholders `@shell@`
  and `@nvim@`, filled in by coil.nix and by the tests). It passes the path in the environment
  and runs `let g:coil_cwd_file = $COIL_CWD_FILE | unlet $COIL_CWD_FILE`: Vim reads the value as
  data, so no path needs escaping, and the variable is gone before anything else runs.
- **docs/shell-integration.md** has a `cl` function for each: `coil --cwd-file` for the Nix one,
  `--cmd "let g:coil_cwd_file = '$tmp'"` for your own Neovim (mktemp names contain no `'`).
- Superseded: `bin/coil` in the plugin, `$COIL_CWD_FILE` as coil's interface, `$COIL_NVIM_PROGRAM`.

## open_external (2026-11-13)

- **An option, on in standalone mode:** `open_external = false`, with `standalone.open_external =
  true` in coil's standalone defaults, so the file manager opens images in an image viewer while
  coil in someone's own Neovim keeps opening everything in the editor.
- **Decided in oil's select callback,** not before calling oil: oil only `bufadd`s the file before
  handing it to `handle_buffer_callback`, so a video is never read, and visual selections are
  sorted file by file for free. The buffer oil added is deleted unless the file was already loaded.
- **What goes out:** the preview's kinds image, video, audio, pdf, archive, binary, classified with
  the preview's own options (`preview.kind()`). Text, too_large (big logs belong in the editor),
  special, unreadable and remote files stay.
- **Only L and <CR>:** the split and tab keys always open in the editor, which is the way to edit
  a binary file on purpose.
- **vim.ui.open, not oil's actions.open_external:** the same call oil makes on Neovim 0.10+, but
  on a path coil already has (oil's action works on the cursor entry only). An error (no opener)
  is reported, and the file isn't opened in the editor instead.
- **Not bundled:** the Nix `coil` doesn't add xdg-utils; the opener is the desktop's.

## edit_here: text files in the system's text editor (2026-11-13)

- **An option, not detection:** `edit_here = true` (plugin default) opens text files in this
  Neovim; standalone mode defaults it to false. coil never tries to tell whether the system's
  editor is this Neovim (the user's call: wrappers make binaries incomparable, and the option
  says it directly).
- **Which editor:** XDG's default for text/plain first (`xdg-mime query default text/plain`, the
  desktop file found in $XDG_DATA_HOME / $XDG_DATA_DIRS, "-" in the ID possibly a subdirectory),
  then $VISUAL, then $EDITOR, then this Neovim. The user asked for XDG before the variables.
- **How it runs:** desktop entries with Terminal=true and $VISUAL/$EDITOR run in a `:terminal`
  in a new tab, wiped when the editor exits (Neovim's `:!` has no terminal to lend). Others start
  detached. Exec is parsed by the desktop entry spec: escapes, double quotes, %f/%F/%u/%U become
  the path, %% a percent sign, other field codes are dropped, and the path goes last if no field
  code takes it. $VISUAL/$EDITOR run through the shell, so arguments in them work.
- **Which files:** the preview's `text` and `too_large` kinds, local only; split and tab keys
  always open here. A failed start warns and opens the file here instead.
- **NVIM_APPNAME:** Neovim re-reads it on every stdpath() call, so the Nix coil can't clear it
  after startup. Its launcher now sets `NVIM_APPNAME=coil` itself (unconditionally, replacing the
  wrapper's `--set-default`, so a user's exported NVIM_APPNAME no longer takes over the build) and
  passes the user's value in `g:coil_editor_env` (copied from the environment, never escaped into a
  command). coil applies that table to editors it starts; an empty NVIM_APPNAME means Neovim's
  default. `vim.ui.open` and `:terminal` still inherit `NVIM_APPNAME=coil` (known gap).
- **Update: editors run as their own program.** Running a terminal editor in a `:terminal` tab of
  coil's Neovim nested it: it inherited Neovim's exported state (`$NVIM`, `$VIMRUNTIME`,
  `$MYVIMRC`, `$VIM`, `$NVIM_LOG_FILE`) and keys went through coil's terminal mappings first. The
  user saw their config "carry over". Terminal editors now go to a new terminal window
  (`xdg-terminal-exec`, the XDG way; otherwise `$TERMINAL -e`); a tab here is the last resort.
  Neovim can't lend its own terminal (`:!` has no tty; the TUI is a separate process).
- **`env -u`, not `clear_env`:** Neovim adds `$NVIM` to every job's environment even with
  `clear_env`, so editors start as `env -u NVIM -u … NAME=value <editor>` (GNU, BusyBox and macOS
  `env` all have `-u`). The terminal emulator gets the clean environment too.
- **`$VISUAL`/`$EDITOR` through `sh -c '<cmd> "$@"' sh <path>`,** as git runs them: arguments in
  the variable work, and the path is never escaped into the command.

## nixvim module (2026-11-13)

- **In coil's flake, not nixvim or nvimx:** `nixvimModules.default` versions with coil's options
  and is usable by any nixvim user. nixvim itself only takes plugins in nixpkgs' `vimPlugins`; once
  coil is there, the module can move upstream almost unchanged.
- **Built with `lib.nixvim.plugins.mkNeovimPlugin`,** like nixvim's own: enable, settings,
  lazyLoad for free. `package` is passed as a ready-made option defaulting to the flake's
  `coil-nvim` for the host system (the module file takes the flake's `packages`).
- **No typed settings:** `settings` is free-form, passed to setup() as it is, with an example. An
  early version typed the common options, but that was a second copy of coil's defaults and
  descriptions to maintain; the user had them removed.
- **`images.enable`** (from nvimx's former `nvimx.coil.image.enable`): image.nvim,
  `dependencies.imagemagick` (nixvim's image module only adds it for sixel), ffmpeg-headless and
  poppler-utils. `plugins.oil.enable` and the image options are `mkDefault`.
- **Checks:** nixvim's `check.mkTestDerivationFromNixvimModule`, with nixvim from nvimx's inputs
  (already locked for the dev shell). The images variant sets `test.runNvim = false`: image.nvim
  needs a terminal at startup, which nixvim's own image tests also skip.
- **tmux_show_only_in_active_window (2026-11-13):** set by the nixvim module (images.enable,
  mkDefault) and the Nix coil's defaults, not by coil's Lua: coil leaves image.nvim's setup to the
  user, and that setup is global (markdown images too). image.nvim only acts on it inside tmux
  (FocusLost/FocusGained, hiding images when the tmux window changes). The README says what tmux
  needs (allow-passthrough; visual-activity off and focus-events on for the option).
- **Module key:** `nixvimModules.coil` has `key`, so a preset and its user can both import it.
  Without it, a second import declares `plugins.coil` twice (verified; the check imports it twice).

## Images in tmux (2026-11-13)

- **Why images landed at the cursor:** image.nvim's kitty backend saves the cursor, moves it
  (`ESC[y;xH`) and places the image "at the cursor" (`a=p`). The moves aren't wrapped for tmux
  passthrough, so tmux applies them to its own screen and only updates the terminal's cursor on its
  next redraw, while the wrapped image command reaches kitty at once, at the old cursor. Positions
  are pane-relative too (no tmux pane offset in image.nvim's offsets). The user tested
  `kitty_method = "unicode-placeholders"`: it works.
- **Set by the distributions, documented for the rest:** the Nix coil's defaults plugin and the
  nixvim module (images.enable, mkDefault) set `kitty_method = "unicode-placeholders"` and
  `tmux_show_only_in_active_window = true`, unconditionally (the user's choice: the latter is a
  no-op outside tmux; placeholders cost image.nvim's cropping). The README has them, plus
  tmux's allow-passthrough, visual-activity off and focus-events on, to copy.
- **Not from coil's Lua:** image.nvim reads both in setup() only (the crop feature and the focus
  autocmds are decided there), and its setup is global and not meant to run twice. A
  `require("coil").image_options()` helper was built and dropped: the nixvim module had to name the
  keys anyway, so the user preferred plain settings in both places and docs to copy.
- **Not lazy.lua:** a lazy.nvim packspec declaring image.nvim would install it for every coil user,
  and images are optional.

## No file details in the preview

- **The preview shows a file's text or a picture of it, nothing else** (your decision, after
  first asking for the path and chosen details above every preview). The info cards are gone,
  with `providers/card.lua`, `dimensions.lua` and the `CoilCard*` highlights. File details are
  oil's job: its columns (`permissions`, `size`, `mtime`) show them in the middle pane.
- **Files with neither** (binary, audio, archives, too large, special, unreadable, remote, and
  pictures that can't be drawn) get one dimmed line saying why, like "Loading...".
- **Pictures start on the pane's second row.** image.nvim draws an image below its anchor line,
  and the anchor is the buffer's only line, which shows "Loading thumbnail..." until the picture is
  drawn. Starting on the first row would mean giving image.nvim screen coordinates instead of
  the window, so coil would have to clear the image on leaving the tab, and image.nvim would no
  longer clear it under floating windows (which-key and other popups).
- **The image is sized to the rows below the anchor.** It used to count the anchor row too, so a
  picture whose height is the limit (portrait photos, PDF pages) was one row too tall, and
  image.nvim cropped it with ImageMagick while Neovim waited.
- *Alternative considered:* a header (path, chosen details, a rule) above every preview. Above
  text it needs real buffer lines, which Tree-sitter and syntax files would parse as code, so
  highlighting would have to run on the file's text alone (a string parser) or the header would
  need its own window (a horizontal split), which brings statusline and layout problems.
