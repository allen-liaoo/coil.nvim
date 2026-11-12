NVIM ?= $(if $(COIL_NVIM),$(COIL_NVIM),nvim)
LUA_DIRS := lua plugin tests

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

## fmt: format Lua sources with stylua
.PHONY: fmt
fmt:
	stylua $(wildcard $(LUA_DIRS))

## fmt-check: check formatting without writing
.PHONY: fmt-check
fmt-check:
	stylua --check $(wildcard $(LUA_DIRS))
