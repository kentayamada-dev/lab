COMPOSE   := docker compose
COMPOSE_ALL := $(COMPOSE) --profile tools
RUN       := $(COMPOSE) run --rm
API_RUN_FLAGS ?=
WEB_RUN_FLAGS ?=
ATLAS_ENV := local
ATLAS_SRC := file:///workspace/api/schema.sql
ATLAS_DIR := file:///workspace/db/migrations

RUN_ATLAS := $(RUN) --env ATLAS_SRC='$(ATLAS_SRC)' --env ATLAS_DIR='$(ATLAS_DIR)' atlas

BASE_REF        := origin/main
BUF_AGAINST_REF := $(BASE_REF)
BUF_AGAINST     := .git\#ref=$(BUF_AGAINST_REF)

GEN_CONFIG_SCRIPT := scripts/gen-buf-config.sh
GEN_CHECK_DIR     := .gen-check.tmp

# The connect-openapi buf plugin has no runtime library whose version it could
# follow (unlike the other plugins in the script), so it is pinned here, in the
# form Renovate's makefileVersions preset reads (docs/renovate.md). Exported so
# every invocation of the script sees it.
# renovate: datasource=github-releases depName=sudorandom/protoc-gen-connect-openapi
CONNECT_OPENAPI_VERSION := v0.25.8
export CONNECT_OPENAPI_VERSION

DEVCONTAINER_DIR := $(CURDIR)/.devcontainer
DEVCONTAINERS    := $(patsubst .devcontainer/%-container/devcontainer.json,%,\
                      $(wildcard .devcontainer/*-container/devcontainer.json))

check-service = @list=$$($(1) config --services) \
                  || { if [ -e .env ]; then \
                         echo "cannot list the services, is docker running? (try: $(1) config --services)" >&2; \
                       else \
                         echo ".env is missing, run 'make init' first" >&2; \
                       fi; \
                       exit 1; }; \
                for s in $$list; do [ "$$s" = "$*" ] && exit 0; done; \
                echo "no service '$*' (available: $$(echo $$list))" >&2; exit 1

require-service     = $(call check-service,$(COMPOSE))
require-any-service = $(call check-service,$(COMPOSE_ALL))

.DEFAULT_GOAL := help

.PHONY: help up down restart build rebuild clean logs \
        proto-check proto-lint proto-fmt proto-fmt-check proto-breaking \
        gen gen-check gen-config-check gen-code-check \
        db-check db-inspect db-validate db-diff db-diff-check db-lint db-migrate \
        init code run-api run-web

# ---- Setup -------------------------------------------------------------------
init: ## Create .env from .env.example if it is missing
	@if [ -e .env ]; then \
	  echo ".env already exists, leaving it untouched" >&2; \
	else \
	  cp .env.example .env \
	    && echo "created .env from .env.example, review the values before continuing" >&2; \
	fi

# ---- Service operations ------------------------------------------------------
up: ## Start every service in the background
	$(COMPOSE) up --detach
up-%: FORCE ## Start one service
	$(require-service)
	$(COMPOSE) up --detach $*
down: ## Stop and remove every service
	$(COMPOSE_ALL) down --remove-orphans
down-%: FORCE ## Stop and remove one service
	$(require-any-service)
	$(COMPOSE_ALL) down $*
restart: ## Restart every service
	$(COMPOSE) restart
restart-%: FORCE ## Restart one service
	$(require-service)
	$(COMPOSE) restart $*
build: ## Build every service image
	$(COMPOSE) build
build-%: FORCE ## Build one service image
	$(require-service)
	$(COMPOSE) build $*
rebuild: build ## Rebuild every image and start the services
	$(COMPOSE) up --detach
rebuild-%: FORCE ## Rebuild one image and start the service
	$(require-service)
	$(COMPOSE) build $*
	$(COMPOSE) up --detach $*
logs: ## Follow the logs of every service
	$(COMPOSE) logs --follow
logs-%: FORCE ## Follow the logs of one service
	$(require-service)
	$(COMPOSE) logs --follow $*
clean: ## Remove containers, volumes and locally built images
	$(COMPOSE_ALL) down --volumes --rmi local --remove-orphans

# ---- Run ---------------------------------------------------------------------
run-api: ## Run the api server in the api container started by 'make up'
	$(COMPOSE) exec --workdir /workspace/api api make run
run-web: ## Run the web dev server in the web container started by 'make up'
	$(COMPOSE) exec --workdir /workspace/web web make dev

# ---- Proto -------------------------------------------------------------------
proto-check: proto-fmt-check proto-lint proto-breaking ## Run every proto check
proto-lint: ## Lint the proto files
	$(RUN) buf lint
proto-fmt: ## Format the proto files
	$(RUN) buf format --write
proto-fmt-check: ## Fail if the proto files are not formatted
	$(RUN) buf format --diff --exit-code
proto-breaking: ## Fail if the proto files break the API, override with BUF_AGAINST_REF=
	@if git rev-parse --quiet --verify '$(BUF_AGAINST_REF):proto' >/dev/null; then \
	  echo "$(RUN) buf breaking --against '$(BUF_AGAINST)'"; \
	  $(RUN) buf breaking --against '$(BUF_AGAINST)'; \
	else \
	  echo "skipping the breaking check: '$(BUF_AGAINST_REF)' has no proto directory (or the ref is missing)" >&2; \
	fi

# ---- Code generation ---------------------------------------------------------
gen: buf.gen.yaml ## Regenerate buf.gen.yaml and run buf generate
	$(RUN) buf generate
gen-check: gen-config-check gen-code-check ## Run every code generation check
gen-config-check: ## Fail if buf.gen.yaml is out of date
	@tmp=$$(mktemp "$${TMPDIR:-/tmp}/buf.gen.yaml.XXXXXX") || exit 1; \
	trap 'rm -f "$$tmp"' EXIT; \
	trap 'exit 1' HUP INT TERM; \
	./$(GEN_CONFIG_SCRIPT) > "$$tmp" || exit 1; \
	diff -u -L buf.gen.yaml -L buf.gen.yaml.expected buf.gen.yaml "$$tmp" \
	  || { echo "buf.gen.yaml is out of date. Run 'make gen' and commit the result." >&2; exit 1; }
gen-code-check: ## Fail if the generated code is out of date
	@dirs=$$(./$(GEN_CONFIG_SCRIPT) --out-dirs) || exit $$?; \
	dirs=$$(printf '%s\n' "$$dirs" | sort -u); \
	[ -n "$$dirs" ] \
	  || { echo "cannot read the output directories from $(GEN_CONFIG_SCRIPT)" >&2; exit 1; }; \
	trap 'rm -rf $(GEN_CHECK_DIR)' EXIT; \
	trap 'exit 1' HUP INT TERM; \
	rm -rf $(GEN_CHECK_DIR); \
	$(RUN) buf generate --output $(GEN_CHECK_DIR) || exit $$?; \
	rc=0; \
	for d in $$dirs; do \
	  diff -ru "$$d" "$(GEN_CHECK_DIR)/$$d" || rc=1; \
	done; \
	test $$rc -eq 0 \
	  || { echo "generated code is out of date. Run 'make gen' and commit the result." >&2; exit 1; }
buf.gen.yaml: $(GEN_CONFIG_SCRIPT) Makefile api/go.mod web/package.json
	./$(GEN_CONFIG_SCRIPT) > $@.tmp || { rm -f $@.tmp; exit 1; }
	mv -f $@.tmp $@

# ---- DB ------------------------------------------------------------------------
db-check: db-validate db-diff-check db-lint ## Run every DB check
db-inspect: ## Print the current schema as SQL
	$(RUN_ATLAS) schema inspect --env $(ATLAS_ENV) --format '{{ sql . }}'
db-validate: ## Fail if the migrations do not match atlas.sum
	$(RUN_ATLAS) migrate validate --env $(ATLAS_ENV)
unexport NAME
db-diff: export MIGRATION_NAME := $(value NAME)
db-diff: ## Write a new migration, requires NAME=add_users_table
ifndef NAME
	$(error NAME is required. Usage: make $@ NAME=add_users_table)
endif
	@export LC_ALL=C; case "$$MIGRATION_NAME" in \
	  '' | *[!a-z0-9_]*) \
	    echo "NAME must be lower_snake_case (got: '$$MIGRATION_NAME')" >&2; exit 1 ;; \
	esac
	$(RUN_ATLAS) migrate diff "$$MIGRATION_NAME" --env $(ATLAS_ENV)
db-diff-check: ## Fail if schema.sql and the migrations have diverged
	@out="$$($(RUN_ATLAS) schema diff --env $(ATLAS_ENV) \
	  --from '$(ATLAS_DIR)' --to '$(ATLAS_SRC)' --format '{{ sql . "  " }}')" || exit $$?; \
	[ -z "$$out" ] || { \
	  printf '%s\n' "$$out"; \
	  echo "schema.sql and db/migrations have diverged. Run 'make db-diff NAME=<name>' and commit the result." >&2; \
	  exit 1; }
# The atlas image has no git, so the files added since the base ref are counted
# here and passed as --latest (the directory is version-ordered, so the newest N
# files are the added ones). Counted against the checkout rather than the index
# so a freshly generated, not yet added migration is linted too.
db-lint: ## Fail if the migrations added since the base ref make dangerous changes, override with BASE_REF=
	@if ! git rev-parse --quiet --verify '$(BASE_REF)^{commit}' >/dev/null; then \
	  echo "skipping the migration lint: '$(BASE_REF)' is missing" >&2; exit 0; \
	fi; \
	n=0; \
	for f in db/migrations/*.sql; do \
	  git cat-file -e '$(BASE_REF):'"$$f" 2>/dev/null || n=$$((n + 1)); \
	done; \
	if [ "$$n" -eq 0 ]; then \
	  echo "skipping the migration lint: no migration added since '$(BASE_REF)'" >&2; exit 0; \
	fi; \
	echo "$(RUN_ATLAS) migrate lint --env $(ATLAS_ENV) --latest $$n"; \
	$(RUN_ATLAS) migrate lint --env $(ATLAS_ENV) --latest "$$n"
db-migrate: ## Apply the pending migrations
	$(RUN_ATLAS) migrate apply --env $(ATLAS_ENV)

# ---- API -------------------------------------------------------------------------
api-%: FORCE ## Run one api/Makefile target inside the api container, pass compose run flags with API_RUN_FLAGS=
	$(COMPOSE) run --rm$(if $(API_RUN_FLAGS), $(API_RUN_FLAGS)) --workdir /workspace/api api make $*

# ---- Web -------------------------------------------------------------------------
web-%: FORCE ## Run one web/Makefile target inside the web container, pass compose run flags with WEB_RUN_FLAGS=
	$(COMPOSE) run --rm$(if $(WEB_RUN_FLAGS), $(WEB_RUN_FLAGS)) --workdir /workspace/web web make $*

# ---- Development environment ---------------------------------------------------
code: $(addprefix code-,$(DEVCONTAINERS)) ## Open every devcontainer in the editor
	@test -n "$(DEVCONTAINERS)" \
	  || { echo "no devcontainer found under $(DEVCONTAINER_DIR)" >&2; exit 1; }
code-%: FORCE ## Open one devcontainer in the editor
	@test -f "$(DEVCONTAINER_DIR)/$*-container/devcontainer.json" \
	  || { echo "no devcontainer for '$*' (available: $(DEVCONTAINERS))" >&2; exit 1; }
	vscli open --config "$(DEVCONTAINER_DIR)/$*-container/devcontainer.json" .

# ---- Help ----------------------------------------------------------------------
help: ## List the available targets
	@awk 'BEGIN { FS = ":.*## *"; w = 0 } \
	     /^# ---- / { s = $$0; sub(/^# ---- /, "", s); sub(/ *-+$$/, "", s); next } \
	     /^[a-zA-Z0-9_%.-]+:.*## / { \
	       t = $$1; ph = "<service>"; \
	       if (t ~ /^code-/) ph = "<container>"; \
	       if (t ~ /^api-/ || t ~ /^web-/) ph = "<target>"; \
	       sub(/%/, ph, t); \
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
.PHONY: FORCE
FORCE:
