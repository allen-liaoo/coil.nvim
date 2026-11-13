# Shell integration

## Change directory on exit

A program can't change its shell's working directory, so coil writes the directory to change to
in a file, and a shell function `cd`s there. On exit, coil writes the directory shown in the
column view of the current tab (or the one used last, or the last directory any column view
showed), without a trailing newline. It writes nothing if no column view showed a local
directory, for example after only browsing over SSH.

Add one of these functions to your shell's config, and run `cl` instead of `coil`. The name is up
to you.

### With the Nix `coil`

It takes the file to write to as `--cwd-file <path>`.

bash and zsh:

```sh
cl() {
  local tmp cwd
  tmp="$(mktemp -t coil-cwd.XXXXXX)"
  coil --cwd-file "$tmp" "$@"
  if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
    builtin cd -- "$cwd"
  fi
  rm -f -- "$tmp"
}
```

fish:

```fish
function cl
    set tmp (mktemp -t coil-cwd.XXXXXX)
    coil --cwd-file $tmp $argv
    if set cwd (command cat -- $tmp); and test -n "$cwd"; and test "$cwd" != "$PWD"
        builtin cd -- $cwd
    end
    rm -f -- $tmp
end
```

### With your own Neovim

coil writes to the file named by `g:coil_cwd_file`, set with `--cmd` like `g:coil_standalone`.
`mktemp`'s file names never contain a `'`, so they can go straight into the command.

bash and zsh:

```sh
cl() {
  local tmp cwd
  tmp="$(mktemp -t coil-cwd.XXXXXX)"
  nvim --cmd "let g:coil_standalone = 1" --cmd "let g:coil_cwd_file = '$tmp'" "$@"
  if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
    builtin cd -- "$cwd"
  fi
  rm -f -- "$tmp"
}
```

fish:

```fish
function cl
    set tmp (mktemp -t coil-cwd.XXXXXX)
    nvim --cmd "let g:coil_standalone = 1" --cmd "let g:coil_cwd_file = '$tmp'" $argv
    if set cwd (command cat -- $tmp); and test -n "$cwd"; and test "$cwd" != "$PWD"
        builtin cd -- $cwd
    end
    rm -f -- $tmp
end
```
