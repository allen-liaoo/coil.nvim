#!@shell@
# bin/coil of the Nix `coil` (./coil.nix): starts the bundled Neovim as a file manager.
#
#   coil [--cwd-file <path>] [nvim arguments...]
#
# --cwd-file <path>: on exit, write the last directory to <path> (see docs/shell-integration.md).
# Everything else goes to Neovim.
set -euo pipefail

nvim_args=(--cmd "let g:coil_standalone = 1")

# The build's own config and state (~/.config/coil, ...), whatever NVIM_APPNAME the user has.
# Editors coil starts get the user's value back (g:coil_editor_env; empty means Neovim's default),
# so a Neovim editor loads the user's own config. Copied out of the environment, like --cwd-file.
export COIL_USER_NVIM_APPNAME="${NVIM_APPNAME-}"
export NVIM_APPNAME=coil
nvim_args+=(--cmd 'let g:coil_editor_env = {"NVIM_APPNAME": $COIL_USER_NVIM_APPNAME}'\
' | unlet $COIL_USER_NVIM_APPNAME')

args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --cwd-file | --cwd-file=*)
      if [ "$1" = --cwd-file ]; then
        if [ $# -lt 2 ]; then
          echo "coil: --cwd-file needs a path" >&2
          exit 2
        fi
        cwd_file="$2"
        shift 2
      else
        cwd_file="${1#*=}"
        shift
      fi
      # The path goes through the environment, so it never has to be escaped into a Vim string,
      # and is removed again as soon as it's copied, so child processes don't inherit it
      export COIL_CWD_FILE="$cwd_file"
      nvim_args+=(--cmd 'let g:coil_cwd_file = $COIL_CWD_FILE | unlet $COIL_CWD_FILE')
      ;;
    --)
      args+=("$@")
      break
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done

exec @nvim@ "${nvim_args[@]}" ${args[@]+"${args[@]}"}
