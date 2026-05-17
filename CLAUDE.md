# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

A configurable Docker dev environment for Magento 2 / MageOS, controlled almost entirely via `make` targets. The user runs `make configure` once to pick their stack (Magento version, PHP, database, optional Varnish/Node), then `make init` to build and start, then day-to-day `make` commands for everything else.

The full command list is in the [README](README.md#command-reference). Run `make help` inside the repo to see them grouped and described.

## How to help — the short version

**Always check the user's state before suggesting commands.** Look for:

- Does `.env` exist? (If not, they need `make configure` first.)
- Does `compose.yaml` exist? (If not, same.)
- Does `httpdocs/` have a `composer.json`? (Determines whether they can run `make install` or need to bring code in first.)
- Are containers running? (`docker compose ps` — affects whether `make start` or `make up` is right.)

**Choose the least destructive command that solves the problem.** This stack has commands that wipe the database (`make kill`, `make rebuild`, `make clean-all`). Never run those without explicit user confirmation, even when they would technically fix an issue.

**Prefer `make` targets over raw `docker compose` calls.** The Makefile encodes assumptions (working directory, user inside container, env vars). Calling Docker directly often skips those.

## Common user requests and how to handle them

### "Set up a new Magento project"

Walk through one of the three scenarios in [docs/INSTALL.md](docs/INSTALL.md), depending on what they have:

1. **Nothing yet, want fresh install** → Scenario A (fresh Magento) or B (fresh MageOS). Ask which platform; if unsure, MageOS is friendlier (no Adobe Marketplace credentials).
2. **They have a Git repo already** → Scenario C (clone existing). Make sure they put it in `httpdocs/` directly, not in a subfolder.
3. **They have a DB dump too** → After Scenario C, run `make import-db FILE=path/to/dump.sql.gz`.

### "Set this up without answering 8 questions"

`make configure FILE=path/to/answers.env` reads the same keys the interactive flow asks for. `tests/fixtures/minimal.env` is a working template. Required keys: `PROJECT_NAME`, `SITE_HOST`, `FLAVOUR`, `MAGENTO_VERSION`, `PHP_VERSION`, `DB_ENGINE`, `DB_VERSION`, `OPENSEARCH_VERSION`, `USE_VARNISH`, `USE_NODE`.

### "It's not loading at https://example.local"

Diagnose in this order:

1. `make ps` — are containers up?
2. `make myip` — does it return a valid IP?
3. Run `make sethostip` — this writes the container IP into `/etc/hosts`. Most "domain not loading" issues are missing hosts entries.
4. Check `make logs` for the `web` container.
5. If nginx logs say `host not found in upstream "varnish"` after a `make start`, that's a known race condition fixed in newer versions — see if they're on an old checkout.
6. If the user is *changing* the domain (not just first setup): `make setdomain DOMAIN=newname.local` rewrites `.env`, re-renders `compose.yaml`, and reminds them to `make sethostip`.

### "I changed `.env` and now things don't work"

`compose.yaml` is generated from `.env`. After editing `.env`, they must run:

```bash
make rebuild-config       # regenerates compose.yaml
make stop && make up      # picks up the new compose
```

Never edit `compose.yaml` directly — it gets overwritten.

### "Xdebug doesn't connect"

This stack ships Xdebug 3 in trigger mode on port 9001. The container resolves the IDE host automatically (`xdebug.discover_client_host=true`). Common fixes:

- IDE must listen on **9001** (not the default 9003).
- Path mapping: `httpdocs/` on host → `/var/www/html` in container.
- Server name in PhpStorm: `${SITE_NAME}Docker` (capitalised project name + "Docker"). Check `.env` for `SITE_NAME`.
- For browser-driven debugging, install a Xdebug helper extension and toggle it.

### "Subnet conflict / can't start the network"

The bootstrap auto-detects a free `10.10.X.0/24` subnet at `make configure` time, but conflicts can appear later (a VPN comes up, another project starts using the same range). Fix:

```bash
make subnets             # see which subnets are taken
# edit DOCKER_SUBNET_BASE in .env (any value 5–250 works)
make rebuild-config
make stop && make up
```

### "I want to upgrade Magento / change PHP version"

Edit `.env`:
- `MAGENTO_VERSION=2.4.9` (must be in the matrix — see `MAGENTO_VERSIONS` in `dockerimages/bin/init.sh`)
- For MageOS, valid `MAGENTO_VERSION` values follow 2.x semantic versioning — currently `2.3.0`, `2.2.2`, `2.2.1`, `2.2.0`, `2.1.0`, `2.0.0` (see `MAGEOS_VERSIONS`). 2.3.0 tracks Magento 2.4.8-p5 (final 2.x release before MageOS 3.0); the 2.2.x line tracks 2.4.8; 2.0 / 2.1 track 2.4.8-p3.
- `PHP_VERSION=8.4` (must be allowed for that Magento release)
- `OPENSEARCH_VERSION=3.0.0` (must be allowed for that Magento release)

Then:

```bash
make rebuild-config
make rebuild               # destroys DB, rebuilds images
# or, to keep DB:
docker compose build --no-cache php-fpm
make stop && make up
```

Always remind the user that `make rebuild` drops the database. If they need to keep data, dump it first with `make db-export`.

## Things to never do without confirmation

| Command | Why dangerous |
|---|---|
| `make kill` | Removes containers AND volumes — DB is gone. |
| `make rebuild` | Same — wipes DB before rebuilding. |
| `make clean-all` | Wipes DB + deletes `.env` and `compose.yaml`. |
| `rm` anywhere in `httpdocs/` | That's the user's actual code. |
| `rm` anywhere in `db_dumps/` | Their backups. |
| Editing `compose.yaml` directly | Overwritten on next `make rebuild-config`. |

For each of these, ask explicitly: "This will [destroy X]. Are you sure?"

## Things you can do freely

- `make shell` / `make shell-root` — drops into the php-fpm container.
- `make cache-flush`, `make reindex`, `make compile`, `make static-deploy` — Magento maintenance.
- `make logs`, `make ps`, `make myip`, `make subnets` — read-only inspection.
- `make db-export` — *creates* a dump (additive, never destructive).
- `make composer-install` — re-runs composer; idempotent.

## Testing changes

The repo has its own smoke test harness for the bootstrap itself (not for the user's Magento code):

- `make test` — fast: runs `tests/smoke.sh`, which renders `compose.yaml` from each fixture in `tests/fixtures/` (`minimal.env`, `full-stack.env`, `mageos.env`, `magento-249.env`) and validates the YAML. Requires `pyyaml`. Takes seconds.
- `make test-full` — `make test` plus actually `docker compose up`-ing each fixture and curl-ing the stack. Takes minutes; needs Docker. CI runs this on `main` pushes only.

CI (`.github/workflows/smoke.yml`) runs three jobs on every push/PR:
1. **fast** — `make test`
2. **shell-lint** — `shellcheck` on every `.sh` (`init.sh`, `render-compose.sh`, `install.sh`, `user-sudoers`, `entrypoint.sh`, `smoke.sh`)
3. **full** — `make test-full` (main only)

If you edit any bash script, run `shellcheck` locally before reporting the change complete. Scripts use `set -euo pipefail` — keep them strict.

## Files that matter

| File | Purpose | When to touch |
|---|---|---|
| `.env` | All configuration | When user wants to change PHP / Magento / DB versions, domain, subnet. |
| `compose.yaml` | Generated Docker Compose definition | Never directly. Always via `.env` + `make rebuild-config`. |
| `httpdocs/` | The user's Magento code | When bringing code in. |
| `db_dumps/` | DB import/export location | When importing a dump. |
| `dockerimages/config/php-fpm/users/.bashrc` | Aliases mounted live into the container | When adding/changing aliases. No rebuild needed. |
| `dockerimages/config/php-fpm/users/.bash_history` | Persistent shell history. | Don't edit — it grows naturally. |
| `dockerimages/bin/init.sh` | Configurator (compatibility matrix `MAGENTO_VERSIONS` + `MAGEOS_VERSIONS` lives here; MageOS tracks Magento upstream with its own 2.x semantic versioning) | Only for adding new Magento / MageOS versions. |

## Useful diagnostic commands

```bash
make ps                                          # what's running
make myip                                        # nginx container IP
make subnets                                     # all docker network subnets
docker compose logs --tail=50 <service>          # specific service logs
make shell                                       # drop into php-fpm
docker compose exec -T php-fpm php -v            # PHP version inside container
docker compose exec -T php-fpm php -m            # PHP modules
make check-images                                # query Docker Hub for OpenSearch tags (matrix extension)
```

## Conventions and assumptions

- The user's host OS is auto-detected. On macOS / Windows, static container IPs are skipped (Docker Desktop doesn't honour them); on Linux, each service gets a fixed IP in `10.10.X.0/24`.
- Magento root must be directly in `httpdocs/`, not in a subfolder.
- DB dumps go in `db_dumps/`. The default name `latest_dbdump.sql.gz` is convention; any path can be passed via `FILE=`.
- The stack assumes Compose v2 (`docker compose ...`, two words). The Makefile auto-detects v1 fallback but v2 is preferred.
- Service URLs (shown by the `make up` banner): site at `https://${SITE_HOST}/`, phpMyAdmin at `http://localhost:8080`, MailHog (test emails) at `http://localhost:8025`, Varnish (if enabled) at `http://localhost:8081`, Node/Vite HMR (if enabled) at `http://localhost:5173`.
