# Lua API

`require("coil")` has these functions. Every other module under `coil.*` is internal.

```lua
local coil = require("coil")

-- Set coil's options (see the README's Options). Optional.
coil.setup(opts)

-- Like :Coil: open the column view on each directory, one tab each. `dirs` is a path or oil URL,
-- a list of them, or nil for the current buffer's directory.
coil.open(dirs)
coil.open({ "~/a", "~/b" })

-- Like :CoilClose: close the current tab's column view (otherwise the one used most recently)
coil.close()

-- Whether Neovim was started as a file manager (standalone mode). Known from the start, so your
-- config can check it while it loads.
coil.standalone()
```

For example, to send deleted files to the trash only when coil runs as a file manager:

```lua
require("oil").setup({
  delete_to_trash = require("coil").standalone(),
})
```
