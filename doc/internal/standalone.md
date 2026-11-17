# Standalone mode and the Nix packages

coil is a plugin, and also a terminal file manager. Every file-manager behaviour lives in
**standalone mode**, usable from any Neovim; the Nix `coil-standalone` package only bundles what someone
without a Neovim setup needs.

## The mode switch: `g:coil_standalone`

Set with `nvim --cmd "let g:coil_standalone = 1"`, read by `require("coil").standalone()`.

- **Why a global variable:** `--cmd` runs before the user's config, so a function it called would
  have to be loadable already: true for packages (`pack/*/start`, Nix) but not for plugin managers
  that add plugins from init.lua (lazy.nvim). It's also the convention (Firenvim's
  `g:started_by_firenvim`). Configs can branch on the mode while they load.
- **Rejected:** `nvim +Coil -- <args>` (everything after `--` is a file name to Neovim, so coil
  args become buffers to clean up), `nvim +"Coil <args>"` (paths escaped into an Ex line),
  `nvim +Coil!` like `+Man!` (runs after init.lua, too late for configs to branch).
- **Option layers**, later wins: coil's defaults, coil's `standalone` defaults (`open_external`,
  `edit_here = false`, `q` quits instead of closing), the user's options, the user's
  `standalone` options. The user's plain options beat coil's standalone defaults, so a config can
  map `q` to `actions.quit` without knowing about `standalone`. `standalone`'s types are checked in
  either mode, so mistakes show before the first file-manager start.
- **Startup only** (`coil.startup`): it does nothing after `VimEnter`, so a lazily loaded coil
  doesn't open views mid-session. The README tells lazy.nvim users not to lazy-load it.

## Startup (`lua/coil/startup.lua`)

- Opens one view per argument when every argument is a directory (or none: the cwd). Any file
  among them leaves Neovim alone, except when choosing files: then a file stands for its
  directory, with the cursor on it (see below). URLs without a trailing slash are first given to
  oil's adapter (see [oil.nvim](oil.md#oil-behaviours-coil-handles)).
- The views are the only tabs: the start tab is closed, files open in a new tab, the arglist is
  cleared, and only **listed** start buffers are deleted (oil's SSH login terminal is unlisted and
  must survive).
- Its `VimEnter` autocmd is `nested` (see [Neovim](neovim.md#autocmds-inside-autocmds)).
- **cd on exit:** `g:coil_cwd_file`, read at `VimLeavePre`, gets the current tab's view's directory,
  else the one used last, else the last local directory any middle pane showed. Remote
  directories are skipped. Written without trailing slash or newline, like yazi. The shell
  functions are in `doc/shell-integration.md`.
- **Cancelling skips it:** the `cancel` key (`Q` in standalone mode, like yazi's) and any exit
  with an error code (`:cq`, seen as `v:exiting` at `VimLeavePre`). `:q!` can't: it exits with 0,
  and Neovim doesn't tell autocmds about the `!` (`v:cmdbang` is for reads and writes only).
  Without this, a directory dialog (termfilechooser) couldn't be cancelled: every quit chose.

## Choosing files (`lua/coil/view/choose.lua`)

`--chooser-file` sets `g:coil_chooser_file`, which turns the middle pane's open keys into "choose":

- **Like yazi's `--chooser-file`:** a file under the cursor, or every entry of a visual selection
  (directories included), written one path per line, then `confirm qall`. A directory under the
  cursor is still entered. Nothing is written on quitting without a choice.
- **Every open key chooses**, the split and tab keys too: in a picker, opening a file anywhere
  would be a surprise.
- **Read when a key runs, not at startup,** so it works in any Neovim that sets the variable, and
  needs no setup step.
- **The visual selection is read from the lines,** not through oil's `select`: that hands over
  one entry at a time, so coil's callback would enter each directory and quit after the first
  file.
- **Local files only:** remote entries have no path another program could open.
- **A file argument opens its directory with the cursor on it,** as in yazi: file pickers'
  save dialogs (xdg-desktop-portal-termfilechooser) pass the suggested file, which may not exist
  yet. Choosing it, or another file, gives the path to save to.

### The termfilechooser wrapper (`bin/coil-termfilechooser`)

- **In coil, not the user's config:** it depends on how `--chooser-file`, `--cwd-file` and file
  arguments behave, so it changes and is tested with them. termfilechooser ships its own wrappers
  (yazi, lf, ...); coil's could go upstream once its flags settle.
- **Follows those wrappers:** the portal's five arguments, `TERMCMD`, and in directory mode a
  `--cwd-file` fallback, so quitting inside a directory chooses it.
- **No terminal assumed:** those wrappers default to kitty; coil's falls back as it does for
  terminal editors (`xdg-terminal-exec`, else `$TERMINAL -e`), and otherwise fails, saying to set
  `TERMCMD`.
- **`sh -c "$TERMCMD \"\$@\""` with coil's arguments as positional parameters,** where the
  bundled wrappers escape each argument into the command string with `sed`. `TERMCMD` stays a
  command line (it may quote its own arguments, like a title), and paths are never escaped.
- **Runs the `coil` next to it,** resolved through links, so it works without the portal's `PATH`
  and from a link in the portal's config directory.

## Data never goes into command strings

The launcher (`bin/coil`) passes values through the environment and has Vim copy them out:
`let g:coil_cwd_file = $COIL_CWD_FILE | unlet $COIL_CWD_FILE`. Vim reads the value as data, so no
path is ever escaped, and the variable is gone before any child process could inherit it.
kitty-scrollback.nvim's issue #377 shows what interpolating paths into `--cmd` breaks. Global
variables aren't inherited by `:terminal` children, which is why the cwd file is a variable, not
an environment variable.

## The launcher (`bin/coil`)

Neovim refuses unknown options (`Unknown option argument`), so only a script that parses
arguments before Neovim can take `--cwd-file`.

- **One launcher:** the plugin ships `bin/coil`, and the Nix `coil` wraps the same script, so
  arguments are parsed in one place. What differs is set through the environment: `COIL_NVIM`
  (which Neovim; default `nvim`) and `COIL_APPNAME` (run as that Neovim app). The launcher unsets
  both before starting Neovim, so a `coil` run from its `:terminal` uses the user's own settings.
- **Parsed in bash, not Lua:** the launcher is a shell script anyway, and a Lua parser would cost a
  second Neovim start (`nvim -l`) before the real one.
- **A relative `--cwd-file` is made absolute** against the shell's directory: Neovim writes it at
  exit, after any `:cd`.
- `${args[@]+"${args[@]}"}` is for bash 3.2 (macOS), which treats an empty array as unset under
  `set -u`.

### `:CoilInstallCli` (`lua/coil/cli.lua`)

- **A symlink, not a copy,** so the command changes with the plugin. Plugin managers can't add to
  `PATH` themselves (a lazy.nvim `build` step runs inside Neovim).
- **Its own command, not `:Coil install-cli`:** `:Coil` takes directories, so the subcommand
  would shadow a directory of that name.
- **Replaces only a broken link or a link to another coil.nvim's `bin/coil`** (a directory with
  `lua/coil/init.lua`): what a plugin moving to another manager or `NVIM_APPNAME` leaves behind.
  Anything else named `coil` is left alone.
- **Refuses a plugin in `/nix/store`:** its path changes with every update, so the link would
  break after garbage collection.
- **Checks `PATH` afterwards** with `exepath()`: `~/.local/bin` isn't on macOS's default `PATH`,
  and another `coil` may come first. Neovim's `PATH` is the shell's it started from, so this is
  what that shell would run.
- **`:checkhealth coil` catches links that break later:** it warns about broken `coil` links in
  any `PATH` directory (`exepath()` skips them, since they aren't executable). Another
  coil.nvim's launcher or a different `coil` (the Nix one) is only info: either still starts
  coil.

## Nix's commands (`nix/coil-cli.nix`, `nix/coil-termfilechooser.nix`)

- **`coil-cli.nix` wraps `bin/coil` for a given Neovim** (`nvim`, with no default, and an
  optional `appname`) and installs only `bin/coil`, so it can't collide with the user's own
  Neovim in one profile. The standalone `coil` is built with it.
- **`coil-termfilechooser.nix` replaces the wrapper's `coil` with a store path** to a coil-cli
  package (the standalone `coil` by default), so the portal finds it whatever its `PATH`, and
  `coil` itself needn't be installed. The `coil-standalone` package doesn't install the picker.
- **The picker's own tools (`sh`, `rm`, `cat`) are appended to its `PATH`,** so it runs under a
  portal with an empty `PATH`, while the terminal (`xdg-terminal-exec`, `$TERMINAL`) and the
  user's tools still come from the portal's.

## The Nix `coil-standalone` (`nix/coil-standalone.nix`)

- **coil-cli with a bundled Neovim** and `appname = "coil"`. The file is named apart from
  `coil-cli.nix` to avoid confusion; the flake's package is `coil-standalone` too.
- **No init of its own** (`wrapRc = false`): `COIL_APPNAME=coil` makes the launcher set
  `NVIM_APPNAME=coil`, so Neovim reads `~/.config/coil/init.lua` as an ordinary config. (An
  earlier design returned a table of
  setup options merged into the build's defaults; dropped, since setup calls work like anywhere
  else this way. It also stopped `VIMINIT` leaking into Neovims started from `:terminal`.)
- **Fallback setups, not merged defaults:** `nix/defaults/plugin/coil_defaults.lua` runs after
  the user's init and sets up only what init.lua didn't: oil (if `:Oil` doesn't exist), mini.icons,
  oil-git-status (only if oil's sign column has room), image.nvim (if `:ImageReport` doesn't
  exist), habamax (Neovim's default scheme draws keywords in the normal colour, so highlighted
  previews look plain). It's packaging, so it lives in `nix/`.
- **`NVIM_APPNAME` is forced, not defaulted:** Neovim re-reads it on every `stdpath()` call, so it
  can't be cleared after startup, and a user's exported value must not take over the build. The
  user's value is passed in `g:coil_editor_env`, which coil applies to editors it starts. Known
  gap: `vim.ui.open` and `:terminal` children still inherit `NVIM_APPNAME=coil`.
- **Preview tools are appended to `PATH`**, so the user's own versions win. With ffmpeg, poppler
  and mini.icons the closure went from 399 MB to 570 MB (610 MB while it also bundled
  nvim-treesitter's grammars, since dropped for Neovim's regex syntax files).
- **mini.icons over nvim-web-devicons:** oil supports both, and mini.icons needs no Nerd Font
  fallback logic.

## The nixvim module (`nix/nixvim.nix`)

- Lives in coil's flake, built with `lib.nixvim.plugins.mkNeovimPlugin` like nixvim's own modules,
  so it can move upstream once coil is in nixpkgs' `vimPlugins`.
- **`settings` is free-form,** passed to `setup()` as is. A typed version duplicated coil's
  defaults and descriptions; the user had it removed.
- **`images.enable`** sets up image.nvim (with `kitty_method = "unicode-placeholders"` and
  `tmux_show_only_in_active_window`, `mkDefault`) and adds ImageMagick, ffmpeg and poppler.
  image.nvim settings live here and in the Nix build's defaults, not in coil's Lua: image.nvim
  reads them in its global `setup()` only. A `require("coil").image_options()` helper was built and
  dropped, since the module had to name the keys anyway.
- **The module has a `key`**, so a preset and its user can both import it; without one, a second
  import declares `plugins.coil` twice. The flake check imports it twice on purpose.
- **Checks** use nixvim's `mkTestDerivationFromNixvimModule` (nixvim from nvimx's inputs). The
  images variant only builds (`test.runNvim = false`): image.nvim needs a terminal at startup.

## The system's text editor (`edit_here = false`)

- **An option, not detection:** coil never guesses whether the system's editor is this Neovim
  (wrappers make binaries incomparable).
- **Order:** XDG's default for `text/plain` (desktop file looked up in `$XDG_DATA_HOME` /
  `$XDG_DATA_DIRS`; a `-` in the ID may be a subdirectory), then `$VISUAL`, `$EDITOR`, then this
  Neovim. Exec is parsed per the desktop entry spec.
- **Editors run as their own program.** Running a terminal editor in a `:terminal` of coil's Neovim
  nested it: it inherited `$NVIM`, `$VIMRUNTIME`, `$MYVIMRC` and coil's terminal mappings, and the
  user saw their config "carry over". Terminal editors now open in a new terminal window
  (`xdg-terminal-exec`, else `$TERMINAL -e`); a tab here is the last resort. Neovim can't lend its
  own terminal: `:!` has no tty, and the TUI is a separate process.
- **`env -u`, not `clear_env`:** Neovim adds `$NVIM` to every job's environment even with
  `clear_env`. `$VISUAL`/`$EDITOR` run as `sh -c '<cmd> "$@"' sh <path>`, as git does, so arguments
  in them work and the path is never escaped.
