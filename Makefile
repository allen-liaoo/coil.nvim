NVIM ?= $(if $(COIL_NVIM),$(COIL_NVIM),nvim)
LUA_DIRS := lua plugin scripts tests

## help: print this help message
.PHONY: help
help:
	@echo 'Usage:'
	@sed -n 's/^##//p' $(MAKEFILE_LIST) | column -t -s ':' | sed -e 's/^/ /'

## test: run the headless test suite (needs the nix dev shell)
.PHONY: test
test:
	$(NVIM) --headless --clean -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua', sequential = true}"

# Extra Neovim arguments for the dev targets, e.g. make dev-standalone ARGS="~/a ~/b"
ARGS ?=
# Standalone mode, set before scripts/dev.lua runs coil.setup()
STANDALONE := --cmd "let g:coil_standalone = 1"

## dev: open your editor (nvim on PATH) with this working copy of coil and oil loaded
.PHONY: dev
dev:
	nvim --cmd "luafile scripts/dev.lua" $(ARGS)

## dev-clean: like dev, but in a clean Neovim without your config
.PHONY: dev-clean
dev-clean:
	$(NVIM) --clean --cmd "luafile scripts/dev.lua" $(ARGS)

## dev-standalone: like dev, started as a file manager (directories in ARGS)
.PHONY: dev-standalone
dev-standalone:
	nvim $(STANDALONE) --cmd "luafile scripts/dev.lua" $(ARGS)

## dev-standalone-clean: like dev-clean, started as a file manager
.PHONY: dev-standalone-clean
dev-standalone-clean:
	$(NVIM) --clean $(STANDALONE) --cmd "luafile scripts/dev.lua" $(ARGS)

## fmt: format Lua sources with stylua
.PHONY: fmt
fmt:
	stylua $(wildcard $(LUA_DIRS))

## fmt-check: check formatting without writing
.PHONY: fmt-check
fmt-check:
	stylua --check $(wildcard $(LUA_DIRS))
