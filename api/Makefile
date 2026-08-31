MODULE = $(eval MODULE := $(shell go list -m))$(or $(MODULE),$(error cannot determine the module path, does 'go list -m' work here?))

SQLC         := go tool sqlc
STATICCHECK  := go tool staticcheck
GCI          := go tool gci
GOFUMPT      := go tool gofumpt
GOVULNCHECK  := go tool govulncheck

GCI_FLAGS = -s standard -s default -s "prefix($(MODULE))"

GEN_DIR := gen

FMT_FIND    := find . -path './$(GEN_DIR)' -prune -o -type f -name '*.go'

select-pkgs = $(if $(1),,$(error select-pkgs requires a directory to exclude))\
	mod="$$(go list -m)" || exit $$?; \
	pkgs="$$(go list ./...)" || exit $$?; \
	kept=''; \
	for p in $$pkgs; do \
	  case "$$p/" in "$$mod/$(1)/"*) ;; *) kept="$$kept $$p" ;; esac; \
	done; \
	pkgs="$$kept"; \
	[ -n "$$pkgs" ] || { echo "no packages matched (excluded: $$mod/$(1))" >&2; exit 1; }

run-on-pkgs = [ $$\# -gt 0 ] || { echo 'run-on-pkgs: no command given' >&2; exit 1; }; \
	$(call select-pkgs,$(GEN_DIR)); \
	set -- "$$@" $$pkgs; \
	printf '%s\n' "$$*"; \
	"$$@"

COVERAGE_OUT  := coverage.out
COVERAGE_HTML := coverage.html

.DEFAULT_GOAL := help

.PHONY: help run run-race check test cover cover-html lint fmt fmt-check \
        db-gen db-gen-check db-vet tidy tidy-check deps-check deps-update

# ---- Run -------------------------------------------------------------------
run: require-go ## Run the server
	go run ./cmd/server

run-race: require-go ## Run the server with the race detector
	go run -race ./cmd/server

# ---- CI aggregate ----------------------------------------------------------
check: fmt-check tidy-check lint db-gen-check db-vet test ## Run every CI check

# ---- Test ------------------------------------------------------------------
test: require-go ## Run the tests with the race detector
	@set -- go test -race; $(run-on-pkgs)

cover: require-go ## Run the tests and print a coverage summary
	@set -- go test -race -coverprofile=$(COVERAGE_OUT); $(run-on-pkgs)
	go tool cover -func=$(COVERAGE_OUT)

cover-html: require-go cover ## Write an HTML coverage report
	go tool cover -html=$(COVERAGE_OUT) -o $(COVERAGE_HTML)
	@echo "wrote $(COVERAGE_HTML)"

# ---- DB ----------------------------------------------------------------------
db-gen: require-go ## Generate the DB code from the queries
	$(SQLC) generate

db-gen-check: require-go ## Fail if the generated DB code is out of date
	$(SQLC) diff

db-vet: require-go ## Lint the SQL queries
	$(SQLC) vet

# ---- Dependencies --------------------------------------------------------------
tidy: require-go ## Tidy go.mod and go.sum
	go mod tidy

tidy-check: require-go ## Fail if go.mod or go.sum is not tidy
	@tidy_out="$$(go mod tidy -diff)"; tidy_rc=$$?; \
	if [ $$tidy_rc -ne 0 ] && [ -z "$$tidy_out" ]; then \
		echo 'tidy-check: go mod tidy exited with an error' >&2; \
		exit 1; \
	fi; \
	if [ -n "$$tidy_out" ]; then \
		printf '%s\n' "$$tidy_out"; \
		echo 'run: make tidy' >&2; \
		exit 1; \
	fi

deps-check: require-go ## Scan the dependencies for known vulnerabilities
	$(GOVULNCHECK) ./...

deps-update: require-go ## Update the dependencies and the tools to their latest versions
	go get -u -t ./...
	go get -u tool
	go mod tidy

# ---- Lint / Format -------------------------------------------------------------
lint: require-go ## Run go vet and staticcheck
	@set -- go vet; $(run-on-pkgs)
	@set -- $(STATICCHECK); $(run-on-pkgs)

fmt: require-go ## Format the hand-written code
	$(FMT_FIND) -exec $(GOFUMPT) -l -w {} +
	$(FMT_FIND) -exec $(GCI) write $(GCI_FLAGS) {} +

fmt-check: require-go ## Fail if the hand-written code is not formatted
	@gofumpt_out="$$($(FMT_FIND) -exec $(GOFUMPT) -l {} +)"; gofumpt_rc=$$?; \
	gci_out="$$($(FMT_FIND) -exec $(GCI) list $(GCI_FLAGS) {} +)"; gci_rc=$$?; \
	if [ $$gofumpt_rc -ne 0 ] || [ $$gci_rc -ne 0 ]; then \
		echo 'fmt-check: formatter exited with an error' >&2; \
		exit 1; \
	fi; \
	if [ -n "$$gofumpt_out$$gci_out" ]; then \
		[ -z "$$gofumpt_out" ] || echo "$$gofumpt_out"; \
		[ -z "$$gci_out" ] || echo "$$gci_out"; \
		echo 'run: make fmt' >&2; \
		exit 1; \
	fi

# ---- Help ----------------------------------------------------------------------
help: ## List the available targets
	@awk 'BEGIN { FS = ":.*## *"; w = 0 } \
	     /^# ---- / { s = $$0; sub(/^# ---- /, "", s); sub(/ *-+$$/, "", s); next } \
	     /^[a-zA-Z0-9_%.-]+:.*## / { \
	       t = $$1; \
	       sub(/%/, "<name>", t); \
	       n++; head[n] = s; s = ""; name[n] = t; desc[n] = $$2; \
	       if (length(t) > w) w = length(t) \
	     } \
	     END { \
	       fmt = "  %-" w "s  %s\n"; \
	       for (i = 1; i <= n; i++) { \
	         if (head[i] != "") printf "\n%s\n", head[i]; \
	         printf fmt, name[i], desc[i] \
	       } \
	     }' $(MAKEFILE_LIST)

# ---- Internal ------------------------------------------------------------------
.PHONY: require-go
require-go:
	@command -v go >/dev/null 2>&1 \
		|| { echo 'go not found, run this inside the api devcontainer (from the repository root: make code-api)' >&2; exit 1; }
