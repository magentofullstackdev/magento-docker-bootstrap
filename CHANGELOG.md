# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] — 2026-05-29

Tracks Adobe's May 2026 system-requirements refresh: Valkey replaces Redis
across the certified 2.4.x line, MariaDB 11.8 is added, MySQL 8.0 hits EOS,
Varnish bumps to 8 on most releases.

### Added

- **Valkey as the default cache backend** on every release where Adobe now
  certifies it (2.4.6-p11+, 2.4.7-p5+, 2.4.8 all patches, 2.4.9). New
  `CACHE_ENGINE` variable in `.env` (`redis` | `valkey`) drives the choice;
  the wizard asks it as a new Q5.5, defaulting to `valkey`. On 2.4.9 the
  question is skipped entirely – Adobe dropped Redis from the certified
  matrix, so `CACHE_ENGINE=valkey` is forced. The Docker service NAME stays
  `redis` in both branches so phpredis hostnames in `app/etc/env.php` keep
  working unchanged (Valkey is RESP-protocol-compatible). New
  `VALKEY_VERSION` env var, auto-selected from the per-release matrix.
- **`render-compose.sh` branches on `CACHE_ENGINE`** to swap the image
  (`valkey/valkey:${VALKEY_VERSION}-alpine` vs `redis:${REDIS_VERSION}-alpine`)
  and the healthcheck (`valkey-cli ping` vs `redis-cli ping`). Both image
  versions are written to `.env` so flipping the engine after the fact only
  takes editing one line.
- **MariaDB 11.8** added to the matrix for 2.4.6, 2.4.7, 2.4.8, 2.4.9 and
  MageOS 2.2.x / 2.3.0 (tracking Adobe's 2.4.6-p13+ / 2.4.7-p10 / 2.4.8-all
  certification). 2.4.9 keeps 11.4 alongside.
- **Varnish 8** on 2.4.6 / 2.4.7 / 2.4.9 (tracks Adobe's 2.4.6-p15 /
  2.4.7-p10 / 2.4.9 on-prem matrix). 2.4.8 stays on 7.7 (Adobe deliberately
  did not bump 2.4.8 - documented VCL behavior difference). MageOS 2.2.x /
  2.3.0 stay on 7.7 (MageOS upstream not on Varnish 8 yet).
- **New preset `magento-current`**: Magento 2.4.8 + PHP 8.4 + MariaDB 11.8
  + OpenSearch 3.0 + Valkey 8.1 + Varnish 7.7. The "production today"
  baseline, between `magento-latest` (2.4.9 bleeding edge) and
  `magento-legacy` (2.4.6 pre-Valkey). Surfaced by `make presets` and the
  Quick wizard.
- **New fixture `tests/fixtures/valkey.env`**: exercises `CACHE_ENGINE=valkey`
  explicitly on 2.4.7 (a release where both engines are available), so the
  validator's "valkey on a both-engines release" path stays covered in CI.

### Changed

- **MySQL dropped from 2.4.6 and 2.4.7 entirely** (Adobe on-prem no longer
  certifies any MySQL version after MySQL 8.0 EOS, 30 Apr 2026). The wizard
  auto-picks MariaDB on those releases and explains why; `CONFIG_FILE`
  validation rejects `DB_ENGINE=mysql` with a clear error.
- **MySQL 8.0 dropped from 2.4.8, 2.4.9 and every MageOS release** (EOS
  reached). Only MySQL 8.4 remains on the releases that still offer MySQL.
- **OpenSearch tightened** to track Adobe's current per-patch table:
  - 2.4.6: 2.5.0 / 2.12.0 -> 2.19.0 / 3.0.0
  - 2.4.7: 2.12.0 / 2.19.0 -> 2.19.0 / 3.0.0
  - 2.4.8: 2.12.0 / 2.19.0 / 3.0.0 -> 2.19.0 / 3.0.0 (drop 2.12)
  - 2.4.9: 2.19.0 / 3.0.0 -> 3.0.0 only
- **MariaDB 10.4 dropped from 2.4.6** (Adobe last certified it on
  2.4.6-p10; current 2.4.6-p15 is 10.11+).
- **MariaDB 10.6 dropped from 2.4.7** (Adobe 2.4.7-p10 baseline is 10.11+).
- **PHP 8.2 dropped from MageOS** (MageOS upstream removed it from their
  matrix in May 2026; 8.3 and 8.4 remain).
- **Presets updated** to the new matrix:
  - `magento-latest`: MariaDB 11.4 -> 11.8, Varnish 7.7 -> 8, explicit
    `CACHE_ENGINE=valkey`, `VALKEY_VERSION=9`. Description string updated.
  - `magento-legacy`: MariaDB 10.6 -> 10.11, OpenSearch 2.5 -> 2.19,
    Varnish 7.1 -> 8, explicit `CACHE_ENGINE=redis` (legacy path).
    Description string updated.
  - `mageos-latest`: MariaDB 11.4 -> 11.8, explicit `CACHE_ENGINE=valkey`.
    Description string updated.
- **Test fixtures updated** to match the new matrix:
  - `minimal.env`: MariaDB 10.6 -> 10.11, OpenSearch 2.12 -> 2.19, add
    `CACHE_ENGINE=redis` (exercises Redis path).
  - `full-stack.env`: add `CACHE_ENGINE=valkey`.
  - `mageos.env`: add `CACHE_ENGINE=valkey`.
  - `magento-249.env`: MariaDB 11.4 -> 11.8, deliberately omit
    `CACHE_ENGINE` to exercise the auto-default path in the validator.

### Removed

- Stale comment in `render-compose.sh` pointing at `valkey/valkey:8-alpine`
  as a "drop-in" replacement - the renderer now handles Valkey natively, so
  the comment is obsolete.

### Notes

- **Not yet certified, deliberately deferred**: MariaDB 12.3 (Adobe says
  "compatibility will be confirmed following the official release of MariaDB
  12.3, anticipated in the May-June timeframe" - we wait for confirmation);
  RabbitMQ 4.2 (stack does not ship RabbitMQ at all today); Composer 2.9.3+
  explicit pin (the `composer:2.9` image already resolves to the current
  2.9.x).
- **PHP 8.5 on 2.4.8**: Adobe certifies PHP 8.4 / 8.3 only on 2.4.8 -
  PHP 8.5 stays exclusive to 2.4.9.
- **No service rename**: the cache container is still named `redis` in
  `compose.yaml` even when running Valkey. Renaming would force every
  existing `env.php` to update - intentional trade-off.

## [1.1.0] — 2026-05-20

### Added

- Curated stack presets under `dockerimages/templates/`. Each preset is a
  stack-only `.env` fragment (no `PROJECT_NAME` / `SITE_HOST` / `USE_NODE` —
  those stay per-project) with a leading `# Description:` line that the
  wizard surfaces in the menu. Three presets ship:
  - `magento-latest` — Magento 2.4.9 + PHP 8.4 + MariaDB 11.4 +
    OpenSearch 3.0 + Varnish.
  - `magento-legacy` — Magento 2.4.6 + PHP 8.2 + MariaDB 10.6 +
    OpenSearch 2.5 + Varnish.
  - `mageos-latest`  — MageOS 2.3.0 + PHP 8.4 + MariaDB 11.4 +
    OpenSearch 3.0 + Varnish.
- `make configure` now opens with a **Quick / Custom** menu. *Quick* shows
  the preset list and asks only for project name + Node; picking *Custom*
  from inside the preset menu falls through into the original
  eight-question wizard, so a misclick never forces an abort. *Custom* from
  the top-level menu goes straight into the full wizard. Both paths
  converge on the existing CONFIG_FILE validation block by composing a
  synthetic config file on the fly — the compatibility-matrix validation
  stays single-sourced.
- `PRESET=<name>` bypass for `make configure`: skips the menu and loads a
  preset directly. With `PROJECT_NAME=…`, `DOMAIN=…` and `USE_NODE=yes|no`
  also supplied, the entire setup runs zero-prompt — suitable for scripted
  onboarding and CI. Bad preset names fail fast with the preset list
  printed to stderr.
- `make presets` target (and `init.sh --list-presets` for direct invocation)
  prints the shipped presets with their `# Description:` lines. The
  `--list-presets` entry point short-circuits before banner / OS detection
  so it has no side effects.
- `tests/smoke.sh` exercises every preset under
  `dockerimages/templates/*.env` via the `PRESET=` entry point on top of
  the existing fixtures. Catches matrix drift: a matrix change in
  `init.sh` that invalidates a shipped preset (or vice versa) now fails
  CI on the fast job.
- `docs/INSTALL.md`, `README.md` and `CLAUDE.md` updated with the three
  setup paths (Quick wizard, `PRESET=` bypass, `FILE=` config), the
  shipped-presets table and the `dockerimages/templates/` row in the
  "files that matter" reference.

### Changed

- `make configure` help text now documents `PRESET=`, `PROJECT_NAME=`,
  `DOMAIN=`, `USE_NODE=` and `FILE=` as alternative non-interactive
  entry points.

### Fixed

- CI: `tests/smoke.sh --full` now pre-creates the shared
  `magento-composer-cache` external Docker volume before each fixture so
  the full job no longer races against `make ensure-volumes` on a clean
  runner.
- Removed unused `TEMPLATES` variable from `dockerimages/bin/render-compose.sh`
  (left over from the renderer's earlier templated-fragment iteration; the
  current renderer reads templates inline).

## [1.0.0] — 2026-05-17

First public release.

### Added

- Interactive `make configure` initializer with a curated compatibility matrix
  for Magento Open Source 2.4.6 / 2.4.7 / 2.4.8 / 2.4.9 and MageOS
  2.3.0 / 2.2.2 / 2.2.1 / 2.2.0 / 2.1.0 / 2.0.0 — only valid PHP / database /
  OpenSearch combinations are offered for each release. The MageOS line
  tracks the official compatibility matrix at
  https://mage-os.org/get-started/system-requirements/: PHP 8.2–8.4
  (recommended 8.4 for 2.3.0, 8.3 for older 2.x), MariaDB 10.6 / 10.11 / 11.4,
  MySQL 8.0 / 8.4, OpenSearch 2.12 / 2.19 / 3.0 (2.3.0 is the rebuild of the
  Magento 2.4.8-p5 codebase and is the final 2.x release before MageOS 3.0;
  2.2.x rebuilds 2.4.8; 2.0 / 2.1 track 2.4.8-p3). For MageOS 2.2.x and 2.3.0
  the interactive flow surfaces an extra hint that OpenSearch 3 is the
  preferred engine for new installations.
  Magento 2.4.9 tightens supported versions significantly: PHP 8.4 / 8.5 only
  (PHP 8.3 is upgrade-only and not offered for fresh installs), MariaDB 11.4
  only, MySQL 8.4 only, and OpenSearch 3.x recommended (OpenSearch 2.19 kept
  as a migration path).
- Redis and Varnish image tags are auto-selected per Magento / MageOS release
  from the same compatibility matrix that drives PHP / DB / OpenSearch — no
  extra prompt. The matrix follows Adobe's and MageOS's published system
  requirements: Magento 2.4.6 → Redis 7.0 / Varnish 7.1, 2.4.7 → 7.2 / 7.4,
  2.4.8 → 7.4 / 7.6, 2.4.9 → 7.4 / 7.7; MageOS 2.0 / 2.1 → 7.4 / 7.6,
  MageOS 2.2.x and 2.3.0 → 7.4 / 7.7. The selected tags are written into `.env` as
  `REDIS_VERSION` / `VARNISH_VERSION` so they can be overridden by hand if
  needed.
- Pinned remaining service versions to match the MageOS recommended baseline:
  nginx 1.28, Composer 2.9. The Redis service block in the generated
  `compose.yaml` carries a comment pointing at `valkey/valkey:8-alpine` as a
  drop-in replacement for Redis.
- PHP-FPM image bundles the `redis` PECL extension (phpredis). Magento can
  use Predis as a pure-PHP fallback but the C extension is significantly
  faster and matches what production stacks usually run.
- Non-interactive mode for `make configure` via `FILE=path/to/answers.env`
  (or `CONFIG_FILE=…` env var). Validates all keys against the compatibility
  matrix before writing `.env`, so misconfigured fixtures fail fast.
- OpenSearch version selectable per Magento release (e.g. 2.4.8 → 2.12 / 2.19 / 3.0).
  Images come from the official `opensearchproject/opensearch` Docker Hub
  registry; the `analysis-icu` and `analysis-phonetic` plugins required by
  Magento are installed automatically on first start via the `OPENSEARCH_PLUGINS`
  env var. The container ships with `stop_grace_period: 5s` so `make stop`
  is snappy when frequently switching between projects.
- Auto-detection of the host OS — static container IPs on Linux,
  service-name DNS + `host.docker.internal` on macOS / Windows / WSL2.
- Auto-detection of free `10.10.X.0/24` subnets on Linux. The third octet
  varies between projects; the last octet is fixed by service (db = `.2`,
  php-fpm = `.5`, varnish = `.10`, …) so muscle memory is preserved.
- `make sethostip` — writes the running container's IP into `/etc/hosts`
  and replaces stale entries on re-runs.
- `make setdomain DOMAIN=…` — updates `.env` and re-renders `compose.yaml`
  in place.
- `make check-images` — queries Docker Hub for available OpenSearch tags.
  Useful when extending the compatibility matrix as new versions land.
- Optional Varnish 7 service with Magento 2 VCL, automatically rewiring the
  nginx vhost between "direct" and "Varnish-fronted" modes. The vhost uses
  Docker's embedded resolver (`127.0.0.11`) and a variable in `proxy_pass`,
  so the upstream is resolved lazily on first request — nginx no longer
  crashes when Varnish isn't yet registered in Docker DNS at boot.
- Optional Node.js 22 service with Vite HMR port exposed.
- PHP-FPM image with Composer 2, n98-magerun2, Xdebug 3 (zero-config),
  ImageMagick, MailHog handler, sudoers for `www-data`, persistent
  `.bash_history` mounted live.
- Magento workflow targets: `make install`, `make import-db [FILE=path]`,
  `make composer-install`, `make compile`, `make reindex`, `make cache-flush`,
  `make static-deploy`.
- DB tooling: `make db-export`, `make db-cli`, `make redis-flush`.
- Container lifecycle parity with the original `project` script:
  `init`, `up`, `start`, `stop`, `restart`, `kill`, `rebuild`. The `init` /
  `up` / `start` / `rebuild` targets depend on `ensure-volumes`, which
  idempotently creates the shared `magento-composer-cache` external Docker
  volume so the Composer download cache survives across projects and across
  `make kill`. (External volumes are not touched by `docker compose down -v`.)
- `make xdebug-on` / `make xdebug-off` / `make xdebug-status` — toggle
  Xdebug at runtime by re-registering or unloading the `zend_extension`
  (not just flipping `xdebug.mode`), so there is zero engine instrumentation
  overhead when off. State is per-running-container and resets on
  `make rebuild` / container recreation.
- PHP-FPM extension list adapts to the PHP version chosen by the
  configurator: `pspell` is skipped on PHP 8.4+ (removed from PHP core),
  and `opcache` is skipped on PHP 8.5+ (statically built into the binary).
  This makes Magento 2.4.9 / PHP 8.5 builds work out of the box.
- `.shellcheckrc` with per-rule justifications (nameref false positives,
  intentional word-splitting in `parse_kv`, dynamic `source` of
  `CONFIG_FILE`/`ENV_FILE`, `envsubst` single-quote idiom) so the CI
  `shell-lint` job is deterministic and new shell scripts inherit full
  strictness.
- `tests/smoke.sh` — fast and full smoke tests covering minimal, full-stack
  (Varnish + Node), MageOS, and Magento 2.4.9 configurations. Wrapped by
  `make test` and `make test-full`.
- GitHub Actions workflow (`smoke-test`) — runs fast smoke + shellcheck on
  every push and PR; full smoke on pushes to `main`.
- `docs/INSTALL.md` — step-by-step walkthroughs of the three setup scenarios
  (fresh Magento, fresh MageOS, clone existing project). Fresh installs use
  `composer create-project … .` (current directory) so the codebase lands
  straight in `/var/www/html` with no folder-flattening step. Includes a
  note on the Magento Marketplace `auth.json` workflow: after
  `composer create-project` saves credentials to `/var/www/.composer/auth.json`,
  copy them into the project root (`cp ../.composer/auth.json .`) so
  subsequent `composer require` / `composer update` runs don't re-prompt.
- `CLAUDE.md` — guidance for AI coding agents (Claude Code, etc.) on helping
  users with the stack — diagnostic order, destructive-command warnings,
  common requests.
