# =====================================================================
# Magento / MageOS Docker Bootstrap — Makefile
#
# Run `make help` for a list of targets.
# =====================================================================

SHELL          := /usr/bin/env bash
.SHELLFLAGS    := -eu -o pipefail -c
.DEFAULT_GOAL  := help

# Use docker compose (v2) where available, fall back to docker-compose.
DC := $(shell command -v docker >/dev/null && docker compose version >/dev/null 2>&1 && echo "docker compose" || echo "docker-compose")

# Pull project name + site host from .env if present.
ifneq (,$(wildcard ./.env))
    include .env
    export
endif

PROJECT       ?= $(COMPOSE_PROJECT_NAME)
SITE_HOST     ?= magento.local
PHP_EXEC      := $(DC) exec -u www-data php-fpm
PHP_EXEC_ROOT := $(DC) exec php-fpm

# Pretty banner shown after `up` / `start` / `init` / `rebuild`.
define BANNER
@echo ""
@echo "===================== OK ====================="
@echo ""
@echo "      Accedi:"
@echo ""
@echo "      Web server:   https://$(SITE_HOST)/"
@echo "      PHPMyAdmin:   http://localhost:8080"
@echo "      Local emails: http://localhost:8025"
@if [ "$(USE_VARNISH)" = "yes" ]; then echo "      Varnish:      http://localhost:8081"; fi
@echo ""
@echo "===================== OK ====================="
@echo ""
endef

# ---------------------------------------------------------------------
.PHONY: help
help:  ## Show this help
	@printf "\n\033[1mMagento / MageOS Docker Bootstrap\033[0m\n\n"
	@awk 'BEGIN {FS = ":.*##"} \
	      /^[a-zA-Z_-]+:.*##/ { printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2 } \
	      /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)
	@echo ""

##@ Setup (run these once after cloning)
.PHONY: configure rebuild-config check
configure:  ## Configure the stack. Interactive by default, or pass FILE=path/to/answers.env for non-interactive
	@if [[ -n "$(FILE)" ]]; then \
	    CONFIG_FILE="$(FILE)" bash dockerimages/bin/init.sh; \
	else \
	    bash dockerimages/bin/init.sh; \
	fi

rebuild-config:  ## Re-render compose.yaml from current .env (no questions asked)
	@bash dockerimages/bin/render-compose.sh

check:  ## Verify .env + compose.yaml exist
	@test -f .env         || (echo "✗ .env missing — run 'make configure'" && exit 1)
	@test -f compose.yaml || (echo "✗ compose.yaml missing — run 'make configure'" && exit 1)
	@echo "✓ .env + compose.yaml present"

# Shared across projects so Composer cache survives between Magento stacks.
# `docker volume create` is idempotent — silently succeeds if it already exists.
ensure-volumes:  ## Ensure external Docker volumes exist (idempotent)
	@docker volume create magento-composer-cache >/dev/null

##@ Container lifecycle (mirrors the original `project` script)
.PHONY: init up start stop restart kill rebuild build logs ps ensure-volumes
init: check ensure-volumes  ## Build with --no-cache and start (use after first `configure`)
	@$(DC) build --no-cache
	@$(DC) up -d
	$(BANNER)

up: check ensure-volumes  ## Start containers (build if needed)
	@$(DC) up -d --build
	$(BANNER)

start: check ensure-volumes  ## Start already-built containers
	@$(DC) start
	$(BANNER)

stop:  ## Stop containers (keep data)
	@$(DC) stop

restart:  ## Restart all containers
	@$(DC) restart
	@echo "DONE --- All containers were successfully restarted"

kill:  ## Stop + remove containers AND volumes (destroys DB!)
	@$(DC) stop
	@$(DC) down -v

rebuild: check ensure-volumes  ## kill + build --no-cache + up (full reset, destroys DB!)
	@$(DC) stop
	@$(DC) down -v
	@$(DC) build --no-cache
	@$(DC) up -d
	$(BANNER)

build: check  ## Build images (with cache)
	@$(DC) build

logs:  ## Tail logs from all containers
	@$(DC) logs -f --tail=200

ps:  ## Show container status
	@$(DC) ps

##@ Shells
.PHONY: shell shell-root redis db
shell: check  ## Open bash inside php-fpm as www-data (default user)
	@$(PHP_EXEC) bash

shell-root: check  ## Open bash inside php-fpm as root (when you need to install something fast)
	@$(PHP_EXEC_ROOT) bash

redis: check  ## Open bash inside the redis container as root
	@$(DC) exec --user root redis bash

db: check  ## Open bash inside the database container as root
	@$(DC) exec --user root db bash

##@ Networking helpers
.PHONY: myip sethostip setdomain subnets check-images
myip: check  ## Print the nginx (web) container IP address
	@$(DC) exec web hostname -i

subnets:  ## List all Docker network subnets currently in use (debug subnet conflicts)
	@docker network ls -q 2>/dev/null \
	    | xargs -r docker network inspect 2>/dev/null \
	    | grep -oE '"Name": *"[^"]+"|"Subnet": *"[^"]+"' \
	    | paste -d' ' - - \
	    | sed 's/"//g; s/,//g; s/Name: //; s/Subnet: / → /' \
	    || echo "(no Docker networks or docker not running)"

check-images:  ## Query Docker Hub for available OpenSearch versions (handy when extending the matrix)
	@echo "Latest 20 tags for opensearchproject/opensearch:"
	@echo "(used to extend the matrix in dockerimages/bin/init.sh)"
	@echo ""
	@if command -v jq >/dev/null 2>&1; then \
	    curl -fsSL 'https://hub.docker.com/v2/repositories/opensearchproject/opensearch/tags?page_size=20' \
	        | jq -r '.results[] | "  \(.name)\t\(.last_updated[:10])"' \
	        | sort -V; \
	else \
	    curl -fsSL 'https://hub.docker.com/v2/repositories/opensearchproject/opensearch/tags?page_size=20' \
	        | grep -oE '"name":"[^"]+"' | head -20 | sed 's/"name":"/  /; s/"$$//' | sort -V; \
	    echo ""; \
	    echo "(install 'jq' for prettier output with timestamps)"; \
	fi

sethostip: check  ## Add `<web-IP> $(SITE_HOST)` to /etc/hosts (sudo required)
	@IP="$$($(DC) exec web hostname -i | tr -d '[:space:]')"; \
	    if [[ -z "$$IP" ]]; then echo "✗ couldn't read web container IP — is it up?"; exit 1; fi; \
	    if grep -qE "[[:space:]]$(SITE_HOST)$$" /etc/hosts; then \
	        echo ">> $(SITE_HOST) already in /etc/hosts — replacing line"; \
	        sudo sed -i.bak -E "/[[:space:]]$(SITE_HOST)$$/d" /etc/hosts; \
	    fi; \
	    echo "$$IP $(SITE_HOST)" | sudo tee -a /etc/hosts >/dev/null; \
	    echo "✓ /etc/hosts → $$IP $(SITE_HOST)"

setdomain: check  ## Change the local domain (usage: make setdomain DOMAIN=newname.local)
	@if [[ -z "$(DOMAIN)" ]]; then echo "✗ usage: make setdomain DOMAIN=foo.local"; exit 1; fi
	@if [[ "$(SITE_HOST)" == "$(DOMAIN)" ]]; then \
	    echo "The domain '$(DOMAIN)' is already set."; \
	else \
	    sed -i.bak "s/^SITE_HOST=.*/SITE_HOST=$(DOMAIN)/" .env && rm -f .env.bak; \
	    bash dockerimages/bin/render-compose.sh; \
	    echo ""; \
	    echo "✓ domain updated to $(DOMAIN). Run 'make rebuild' (destroys DB) or"; \
	    echo "  'make stop && make up' (keeps DB) to apply changes to running containers."; \
	    echo "  Don't forget to update /etc/hosts — 'make sethostip' will do it for you."; \
	fi

##@ Magento workflows
.PHONY: install import-db composer-install
install: check  ## Fresh Magento setup:install (uses ADMIN_*/MYSQL_* from .env)
	@$(PHP_EXEC) bash -c 'cd /var/www/html && /usr/local/bin/install.sh'

import-db: check  ## Import a DB dump. Usage: make import-db [FILE=path]
	@DUMP="$${FILE:-db_dumps/latest_dbdump.sql.gz}"; \
	    test -f "$$DUMP" || (echo "✗ $$DUMP not found" && exit 1); \
	    BASENAME="$$(basename "$$DUMP")"; \
	    $(PHP_EXEC) bash -c "cd /var/www/html && n98-magerun2.phar db:import --compression=gzip /var/www/db_dumps/$$BASENAME"
	@$(PHP_EXEC) bash -c 'cd /var/www/html && bin/magento setup:upgrade && bin/magento cache:flush'
	@echo "✓ database imported and Magento upgraded"

composer-install: check  ## Run composer install inside the php-fpm container
	@$(PHP_EXEC) bash -c 'cd /var/www/html && composer install'

##@ Day-to-day shortcuts
.PHONY: cache-flush reindex compile static-deploy
cache-flush: check  ## bin/magento cache:flush
	@$(PHP_EXEC) bash -c 'cd /var/www/html && bin/magento cache:flush'

reindex: check  ## bin/magento indexer:reindex
	@$(PHP_EXEC) bash -c 'cd /var/www/html && bin/magento indexer:reindex'

compile: check  ## setup:upgrade + setup:di:compile
	@$(PHP_EXEC) bash -c 'cd /var/www/html && bin/magento setup:upgrade && bin/magento setup:di:compile'

static-deploy: check  ## setup:static-content:deploy -f
	@$(PHP_EXEC) bash -c 'cd /var/www/html && bin/magento setup:static-content:deploy -f'

##@ Database utilities
.PHONY: db-export db-cli redis-flush
db-export: check  ## Export DB to db_dumps/dump-YYYYMMDD-HHMM.sql.gz
	@$(PHP_EXEC) bash -c 'cd /var/www/html && n98-magerun2.phar db:dump --compression=gzip /var/www/db_dumps/dump-$$(date +%Y%m%d-%H%M).sql.gz'

db-cli: check  ## MySQL/MariaDB shell
	@$(DC) exec db sh -c 'mysql -u root -p"$$MYSQL_ROOT_PASSWORD" $$MYSQL_DATABASE'

redis-flush: check  ## Flush all Redis databases
	@$(DC) exec redis redis-cli FLUSHALL

##@ Debugging
# State (on/off) does not persist across container recreation:
# `make rebuild` / `make kill && make up` boot Xdebug back to enabled,
# because the image bakes `docker-php-ext-enable xdebug` at build time.
.PHONY: xdebug-on xdebug-off xdebug-status
xdebug-on: check  ## Enable Xdebug (loads zend_extension + restarts php-fpm)
	@$(DC) exec -T php-fpm docker-php-ext-enable xdebug >/dev/null
	@$(DC) restart php-fpm >/dev/null
	@echo "✓ Xdebug enabled"

xdebug-off: check  ## Disable Xdebug (unloads zend_extension + restarts php-fpm)
	@$(DC) exec -T php-fpm docker-php-ext-disable xdebug >/dev/null
	@$(DC) restart php-fpm >/dev/null
	@echo "✓ Xdebug disabled"

xdebug-status: check  ## Show current Xdebug state (on/off)
	@$(DC) exec -T php-fpm php -m | grep -qi '^xdebug$$' \
	    && echo "Xdebug: ON" \
	    || echo "Xdebug: OFF"

##@ Tests
.PHONY: test test-full
test:  ## Run fast smoke tests (configure + render + validate, no docker run)
	@bash tests/smoke.sh

test-full:  ## Run full smoke tests (also pulls images and brings stack up)
	@bash tests/smoke.sh --full

##@ Cleanup
.PHONY: clean-all
clean-all: kill  ## kill + delete .env / compose.yaml / install flag (clean checkout)
	@rm -f .env compose.yaml httpdocs/.install-done
	@echo "✓ project reset to a clean checkout"
