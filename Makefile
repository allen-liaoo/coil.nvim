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

## dev: open your editor (nvim on PATH) with this working copy of coil and oil loaded
.PHONY: dev
dev:
	nvim --cmd "luafile scripts/dev.lua"

## dev-clean: like dev, but in a clean Neovim without your config
.PHONY: dev-clean
dev-clean:
	$(NVIM) --clean --cmd "luafile scripts/dev.lua"

## fmt: format Lua sources with stylua
.PHONY: fmt
fmt:
	stylua $(wildcard $(LUA_DIRS))

## fmt-check: check formatting without writing
.PHONY: fmt-check
fmt-check:
	stylua --check $(wildcard $(LUA_DIRS))
