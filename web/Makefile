.DEFAULT_GOAL := help

.PHONY: help check install build dev

# ---- Run -------------------------------------------------------------------
dev: require-pnpm ## Run the dev server
	pnpm dev

# ---- CI aggregate ----------------------------------------------------------
check: install build ## Run every CI check

# ---- Build -----------------------------------------------------------------
install: require-pnpm ## Install the dependencies exactly as the lockfile records
	pnpm install --frozen-lockfile

build: require-pnpm ## Type-check and build the app
	pnpm build

# ---- Help ----------------------------------------------------------------------
help: ## List the available targets
	@awk 'BEGIN { FS = ":.*## *"; w = 0 } \
	     /^# ---- / { s = $$0; sub(/^# ---- /, "", s); sub(/ *-+$$/, "", s); next } \
	     /^[a-zA-Z0-9_%.-]+:.*## / { \
	       t = $$1; \
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
.PHONY: require-pnpm
require-pnpm:
	@command -v pnpm >/dev/null 2>&1 \
		|| { echo 'pnpm not found, run this inside the web devcontainer (from the repository root: make code-web)' >&2; exit 1; }
