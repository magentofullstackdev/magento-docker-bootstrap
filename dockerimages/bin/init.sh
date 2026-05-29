#!/usr/bin/env bash
# =====================================================================
# Magento / MageOS Docker Bootstrap — interactive initializer
# =====================================================================
# Generates compose.yaml + .env tailored to the chosen Magento version,
# PHP, database, search and (optional) Varnish + Node.js.
#
# OS detection: on macOS we drop static IPv4 assignments (Docker Desktop
# does not honour `ipv4_address` reliably on Mac) and rely on
# service-name DNS + extra_hosts. On Linux we keep static IPs.
# =====================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEMPLATES_DIR="${REPO_ROOT}/dockerimages/templates"
ENV_FILE="${REPO_ROOT}/.env"
COMPOSE_FILE="${REPO_ROOT}/compose.yaml"

# ---------- colours ------------------------------------------------------
# Use tput to query the terminal's terminfo database for actual escape
# sequences. Returns real ESC bytes (not the literal string "\033"), so
# the variables work consistently in `cat <<EOF` heredocs, `printf`,
# `echo`, anywhere — without depending on shell-specific quoting rules
# or whether the consumer interprets backslash escapes.
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && [[ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]]; then
    C_BOLD="$(tput bold)"
    C_DIM="$(tput dim)"
    C_GREEN="$(tput setaf 2)"
    C_YELLOW="$(tput setaf 3)"
    C_BLUE="$(tput setaf 4)"
    C_RED="$(tput setaf 1)"
    C_RESET="$(tput sgr0)"
else
    C_BOLD=''; C_DIM=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_RED=''; C_RESET=''
fi

say()  { printf "${C_BLUE}>>${C_RESET} %s\n" "$*"; }
ok()   { printf "${C_GREEN}✓${C_RESET}  %s\n" "$*"; }
warn() { printf "${C_YELLOW}!${C_RESET}  %s\n" "$*"; }
die()  { printf "${C_RED}✗${C_RESET}  %s\n" "$*" >&2; exit 1; }

# ---------- OS detection -------------------------------------------------
detect_os() {
    case "$(uname -s)" in
        Darwin*) echo "mac" ;;
        Linux*)  echo "linux" ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        *)       echo "unknown" ;;
    esac
}
HOST_OS="$(detect_os)"

# ---------- subnet detection (Linux only) -------------------------------
# We always use 10.10.X.0/24 — only the third octet (X) varies. Container
# IPs are derived as <X>.2 = db, .3 = redis, .4 = web, .5 = php-fpm, etc.
# This keeps the layout predictable across projects.
#
# Candidates: 10.10.5, .10, .15, … .250  (step of 5 → 50 slots, plenty
# even for setups with many parallel projects).
SUBNET_CANDIDATES=()
for i in $(seq 5 5 250); do SUBNET_CANDIDATES+=("$i"); done

# Returns 0 if subnet 10.10.X.0/24 collides with any existing Docker network
# OR with a route on the host. Returns 1 if it looks free.
subnet_in_use() {
    local third="$1"
    local needle="10.10.${third}."

    # Check Docker bridge networks
    if command -v docker >/dev/null 2>&1; then
        local used
        used="$(docker network ls -q 2>/dev/null \
                  | xargs -r docker network inspect 2>/dev/null \
                  | grep -oE '"Subnet": *"[^"]+"' \
                  | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+' || true)"
        if grep -q "^${needle}" <<<"$used"; then return 0; fi
    fi

    # Check host routes (catches VPNs, physical LAN, etc.)
    if command -v ip >/dev/null 2>&1; then
        if ip route 2>/dev/null | grep -q "^${needle}0/24"; then return 0; fi
    fi

    return 1
}

pick_subnet() {
    # Only meaningful on Linux — Mac/Windows don't use static IPs.
    if [[ "$HOST_OS" != "linux" ]]; then
        echo "5"  # placeholder, won't be written into compose
        return
    fi

    # If docker isn't installed yet, just return the first candidate.
    if ! command -v docker >/dev/null 2>&1; then
        echo "5"; return
    fi

    for third in "${SUBNET_CANDIDATES[@]}"; do
        if ! subnet_in_use "$third"; then
            echo "$third"
            return
        fi
    done

    # Everything in our preferred range is taken — fall back to .5 with
    # a warning. The user can edit DOCKER_SUBNET_BASE in .env and re-render.
    warn "all 10.10.{5..250} subnets are in use — defaulting to 10.10.5."
    warn "edit DOCKER_SUBNET_BASE in .env if you hit a conflict."
    echo "5"
}

# ---------- compatibility matrix ----------------------------------------
# Format per Magento version (pipe-separated key=value pairs):
#   php                       : space-separated PHP candidates
#   recommended (PHP)         : sensible default
#   mariadb / mysql           : compatible DB tags. `mysql=` may be absent
#                               when Adobe no longer certifies any MySQL
#                               version for that release (2.4.6, 2.4.7 on
#                               on-prem after MySQL 8.0 EOS - 30 Apr 2026).
#   opensearch                : space-separated OpenSearch versions (uses
#                               opensearchproject/opensearch images)
#   opensearch_recommended    : default OpenSearch version
#   composer                  : "1" or "2"
#   redis                     : Redis tag for redis:TAG-alpine.
#                               Absent on 2.4.9 - Adobe drops Redis support
#                               entirely there in favour of Valkey.
#   valkey                    : Valkey tag for valkey/valkey:TAG-alpine.
#                               Adobe added Valkey to the certified matrix
#                               from 2.4.6-p11 / 2.4.7-p5 / 2.4.8 / 2.4.9
#                               (Redis 7.2 EOS + license change).
#   valkey_recommended        : default Valkey tag - used when CACHE_ENGINE
#                               is unset / "valkey"
#   varnish                   : Varnish tag
#
# Sources: Adobe Commerce system-requirements (experienceleague.adobe.com)
# and MageOS upstream (mage-os.org).
# ------------------------------------------------------------------------
# Cache engine (Redis vs Valkey) is exposed as an interactive choice in the
# wizard when both are listed in the spec. Default is `valkey` because Adobe
# has stopped certifying Redis on every current patch (Valkey 8/8.1/9 is the
# new baseline). Redis stays selectable for installations that still pin to
# a pre-Valkey patch level (e.g. 2.4.6 baseline through 2.4.6-p10) - users
# can switch back via CACHE_ENGINE=redis in .env.
# ------------------------------------------------------------------------
# OpenSearch / Varnish ranges follow Adobe's per-patch tables:
#   - 2.4.6-p15: OS 2.19/3, Varnish 8
#   - 2.4.7-p10: OS 2.19/3, Varnish 8
#   - 2.4.8-p5:  OS 3,      Varnish 7.7 (Adobe deliberately did not bump
#                                        2.4.8 to Varnish 8 - VCL quirk)
#   - 2.4.9:     OS 3 only, Varnish 8
# We standardise on OpenSearch 2.x+ so the official image installs the
# analysis-icu / analysis-phonetic plugins via OPENSEARCH_PLUGINS env var.
# ------------------------------------------------------------------------
# 2.4.9 (released 12 May 2026) significantly tightens supported versions:
# PHP 8.4/8.5 only (8.3 upgrade-only, 8.2 dropped), MariaDB 11.4 / 11.8,
# MySQL 8.4 only, OpenSearch 3.x only, Valkey 9 only (no Redis).
declare -A MAGENTO_VERSIONS=(
    [2.4.6]="php=8.1 8.2|recommended=8.2|mariadb=10.11 11.8|opensearch=2.19.0 3.0.0|opensearch_recommended=2.19.0|composer=2|redis=7.0|valkey=8.1|valkey_recommended=8.1|varnish=8"
    [2.4.7]="php=8.2 8.3|recommended=8.3|mariadb=10.11 11.8|opensearch=2.19.0 3.0.0|opensearch_recommended=2.19.0|composer=2|redis=7.2|valkey=8.1|valkey_recommended=8.1|varnish=8"
    [2.4.8]="php=8.3 8.4|recommended=8.4|mariadb=10.6 11.4 11.8|mysql=8.4|opensearch=2.19.0 3.0.0|opensearch_recommended=3.0.0|composer=2|redis=7.4|valkey=8.1|valkey_recommended=8.1|varnish=7.7"
    [2.4.9]="php=8.4 8.5|recommended=8.4|mariadb=11.4 11.8|mysql=8.4|opensearch=3.0.0|opensearch_recommended=3.0.0|composer=2|valkey=9|valkey_recommended=9|varnish=8"
)

# MageOS is API-compatible with Magento Open Source - same matrix shape.
# MageOS versions track Magento upstream: 2.3.0 is the rebuild of the
# Magento 2.4.8-p5 codebase (final 2.x release before MageOS 3.0 / Magento
# 2.4.9); the 2.2.x line tracks 2.4.8, and 2.1 / 2.0 track 2.4.8-p3.
# The compatibility matrix below mirrors the official MageOS one at
# https://mage-os.org/get-started/system-requirements/. MageOS upstream
# moves more slowly than Adobe: Varnish 7.7 stays (no Varnish 8 yet),
# Valkey 8.0 baseline (8.1 on the newer 2.2.x / 2.3.0 because they track
# 2.4.8-p5 which Adobe certifies on Valkey 8.1), PHP 8.3-8.4 only (8.2
# dropped from MageOS docs as of May 2026), MySQL 8.4 only (8.0 dropped
# after Apr 2026 EOS).
declare -A MAGEOS_VERSIONS=(
    [2.3.0]="php=8.3 8.4|recommended=8.4|mariadb=10.6 10.11 11.4 11.8|mysql=8.4|opensearch=2.19.0 3.0.0|opensearch_recommended=3.0.0|composer=2|redis=7.4|valkey=8.1|valkey_recommended=8.1|varnish=7.7"
    [2.2.2]="php=8.3 8.4|recommended=8.4|mariadb=10.6 10.11 11.4 11.8|mysql=8.4|opensearch=2.19.0 3.0.0|opensearch_recommended=3.0.0|composer=2|redis=7.4|valkey=8.1|valkey_recommended=8.1|varnish=7.7"
    [2.2.1]="php=8.3 8.4|recommended=8.4|mariadb=10.6 10.11 11.4 11.8|mysql=8.4|opensearch=2.19.0 3.0.0|opensearch_recommended=3.0.0|composer=2|redis=7.4|valkey=8.1|valkey_recommended=8.1|varnish=7.7"
    [2.2.0]="php=8.3 8.4|recommended=8.4|mariadb=10.6 10.11 11.4 11.8|mysql=8.4|opensearch=2.19.0 3.0.0|opensearch_recommended=3.0.0|composer=2|redis=7.4|valkey=8.1|valkey_recommended=8.1|varnish=7.7"
    [2.1.0]="php=8.3 8.4|recommended=8.4|mariadb=10.6 10.11 11.4|mysql=8.4|opensearch=2.19.0|opensearch_recommended=2.19.0|composer=2|redis=7.4|valkey=8.0|valkey_recommended=8.0|varnish=7.6"
    [2.0.0]="php=8.3 8.4|recommended=8.4|mariadb=10.6 10.11 11.4|mysql=8.4|opensearch=2.19.0|opensearch_recommended=2.19.0|composer=2|redis=7.4|valkey=8.0|valkey_recommended=8.0|varnish=7.6"
)

# Helper: parse "k1=v1|k2=v2" into associative array `OUT`
parse_kv() {
    local input="$1"; local -n out_ref=$2
    out_ref=()
    local IFS='|'; local -a pairs=( $input )
    for pair in "${pairs[@]}"; do
        out_ref["${pair%%=*}"]="${pair#*=}"
    done
}

# Helper: interactive numbered choice. Echoes selected value to stdout.
choose() {
    local prompt="$1"; shift
    local -a opts=("$@")
    local i=1
    printf "${C_BOLD}%s${C_RESET}\n" "$prompt" >&2
    for o in "${opts[@]}"; do
        printf "  ${C_DIM}%d)${C_RESET} %s\n" "$i" "$o" >&2
        ((i++))
    done
    while true; do
        printf "  → choose [1-${#opts[@]}]: " >&2
        read -r reply
        if [[ "$reply" =~ ^[0-9]+$ ]] && (( reply >= 1 && reply <= ${#opts[@]} )); then
            echo "${opts[$((reply-1))]}"
            return
        fi
        warn "invalid choice"
    done
}

ask() {
    local prompt="$1"; local default="${2:-}"
    if [[ -n "$default" ]]; then
        printf "${C_BOLD}%s${C_RESET} ${C_DIM}[%s]${C_RESET}: " "$prompt" "$default" >&2
    else
        printf "${C_BOLD}%s${C_RESET}: " "$prompt" >&2
    fi
    read -r reply
    echo "${reply:-$default}"
}

ask_yn() {
    local prompt="$1"; local default="${2:-n}"
    local hint
    [[ "$default" == "y" ]] && hint="Y/n" || hint="y/N"
    while true; do
        printf "${C_BOLD}%s${C_RESET} ${C_DIM}[%s]${C_RESET}: " "$prompt" "$hint" >&2
        read -r reply
        reply="${reply:-$default}"
        case "$reply" in
            [Yy]*) echo "yes"; return ;;
            [Nn]*) echo "no";  return ;;
        esac
    done
}

# ---------- preset helpers ----------------------------------------------
# Presets are stack-only .env fragments shipped under dockerimages/templates.
# Each carries a leading `# Description: …` line that the wizard renders in
# the menu. PROJECT_NAME / SITE_HOST / USE_NODE are NEVER baked into a
# preset — they're per-project and collected from the wizard (or from env
# vars supplied on the command line).
list_presets() {
    local f n d
    if ! compgen -G "${TEMPLATES_DIR}/*.env" > /dev/null; then
        printf "(no presets found in %s)\n" "$TEMPLATES_DIR"
        return
    fi
    printf "${C_BOLD}Available presets:${C_RESET}\n"
    for f in "${TEMPLATES_DIR}"/*.env; do
        n="$(basename "$f" .env)"
        d="$(grep -m1 '^# Description:' "$f" | sed 's/^# Description: *//')"
        printf "  ${C_GREEN}%-20s${C_RESET} %s\n" "$n" "$d"
    done
}

# Early bail-out for `make presets`: prints the list and exits. No banner,
# no OS detection, no side effects — just the list.
if [[ "${1:-}" == "--list-presets" ]]; then
    list_presets
    exit 0
fi

# =====================================================================
# Banner
# =====================================================================
cat <<EOF

${C_BOLD}╔══════════════════════════════════════════════════════╗
║   Magento / MageOS Docker Bootstrap — make configure ║
╚══════════════════════════════════════════════════════╝${C_RESET}
${C_DIM}                            by Sergiu Ro. — magentofullstack.dev${C_RESET}

Detected host OS: ${C_GREEN}${HOST_OS}${C_RESET}
EOF

if [[ "$HOST_OS" == "mac" ]]; then
    say "macOS detected → static container IPs will be SKIPPED (Docker Desktop limitation)."
    SUBNET_BASE="5"  # not used, but keeps .env consistent
elif [[ "$HOST_OS" == "linux" ]]; then
    SUBNET_BASE=$(pick_subnet)
    if [[ "$SUBNET_BASE" == "5" ]]; then
        say "Linux detected → using subnet ${C_GREEN}10.10.${SUBNET_BASE}.0/24${C_RESET} (first free slot)."
    else
        say "Linux detected → picked free subnet ${C_GREEN}10.10.${SUBNET_BASE}.0/24${C_RESET} (earlier slots taken)."
    fi
else
    warn "Unknown / Windows host: falling back to extra_hosts (no static IPs)."
    SUBNET_BASE="5"
fi
echo

# =====================================================================
# Preset dispatcher (Quick / Custom + PRESET= bypass)
# =====================================================================
# Two new entry points sit in front of the existing interactive flow and
# the FILE= non-interactive path:
#
#   1. PRESET=name (env var or `make configure PRESET=name`) — loads
#      dockerimages/templates/<name>.env, asks only project name + Node
#      (unless they're also supplied via env), then reuses the existing
#      CONFIG_FILE validation path below.
#   2. No flags + TTY — shows a "Quick / Custom" menu. Picking Quick
#      surfaces the preset menu (with a "Custom" escape hatch); picking
#      Custom anywhere falls through to the full interactive wizard.
#
# Both new paths converge on the existing CONFIG_FILE block by composing
# a temporary file on the fly. Validation logic stays single-sourced.
build_config_from_preset() {
    local preset_name="$1"
    local preset_file="${TEMPLATES_DIR}/${preset_name}.env"

    if [[ ! -f "$preset_file" ]]; then
        warn "preset not found: ${preset_name}"
        list_presets >&2
        die "pick one of the presets above (or omit PRESET= to use the full wizard)"
    fi

    # PROJECT_NAME: honour env-var (CLI / .env) when present, else prompt.
    if [[ -z "${PROJECT_NAME:-}" ]]; then
        local default_name
        default_name="$(basename "$REPO_ROOT" | tr -cd '[:alnum:]-_' | tr '[:upper:]' '[:lower:]')"
        [[ -z "$default_name" || "$default_name" == "magento-docker-bootstrap" ]] && default_name="myproject"
        while true; do
            PROJECT_NAME=$(ask "Project name (used for network, volumes, container prefix)" "$default_name")
            if [[ "$PROJECT_NAME" =~ ^[a-z][a-z0-9_-]{1,30}$ ]]; then break; fi
            warn "lowercase letters, digits, '-' or '_' only; must start with a letter (max 31 chars)"
        done
    fi

    # SITE_HOST: env-var wins; otherwise derive from project name.
    SITE_HOST="${SITE_HOST:-${PROJECT_NAME}.local}"

    # USE_NODE: env-var wins; otherwise prompt. Presets deliberately omit
    # USE_NODE so the wizard can ask it (most users don't need Node).
    if [[ -z "${USE_NODE:-}" ]]; then
        USE_NODE=$(ask_yn "Add Node.js container (frontend tooling, Vite HMR)?" "n")
    fi

    # Compose a synthetic CONFIG_FILE so the existing non-interactive
    # validation path runs unchanged. The temp file gets removed on EXIT
    # even if validation later die()s.
    local tmpfile
    tmpfile="$(mktemp -t magento-preset-XXXXXX.env)"
    {
        cat "$preset_file"
        printf 'PROJECT_NAME=%s\n' "$PROJECT_NAME"
        printf 'SITE_HOST=%s\n'    "$SITE_HOST"
        printf 'USE_NODE=%s\n'     "$USE_NODE"
    } > "$tmpfile"
    trap 'rm -f "'"$tmpfile"'"' EXIT

    CONFIG_FILE="$tmpfile"
    _CONFIG_FROM_PRESET="$preset_name"
}

# Path 1: PRESET= env var → straight into the preset path.
if [[ -n "${PRESET:-}" && -z "${CONFIG_FILE:-}" ]]; then
    build_config_from_preset "$PRESET"
# Path 2: no flags + TTY → Quick / Custom dispatcher.
elif [[ -z "${CONFIG_FILE:-}" && -t 0 ]]; then
    INITIAL_CHOICE=$(choose "How do you want to set this up?" \
        "Quick    — pick a curated stack preset    (2 quick questions)" \
        "Custom   — full wizard, every option      (8 questions)")
    if [[ "$INITIAL_CHOICE" == Quick* ]]; then
        _preset_names=(); _preset_labels=()
        if compgen -G "${TEMPLATES_DIR}/*.env" > /dev/null; then
            for f in "${TEMPLATES_DIR}"/*.env; do
                _n="$(basename "$f" .env)"
                _d="$(grep -m1 '^# Description:' "$f" | sed 's/^# Description: *//')"
                _preset_names+=("$_n")
                _preset_labels+=("$(printf '%-20s %s' "$_n" "$_d")")
            done
        fi
        if [[ ${#_preset_names[@]} -eq 0 ]]; then
            warn "no presets found in ${TEMPLATES_DIR} — falling back to the custom wizard"
        else
            # Escape hatch: pick Custom from inside the preset menu and
            # we fall through to the existing interactive flow.
            _preset_labels+=("$(printf '%-20s %s' 'Custom' '— none of the above, go to full wizard')")
            echo
            PRESET_CHOICE=$(choose "Pick a preset:" "${_preset_labels[@]}")
            if [[ "$PRESET_CHOICE" != Custom* ]]; then
                # The label is `<name>  …` padded to 20 chars; first whitespace-
                # separated token is the preset name.
                _picked="${PRESET_CHOICE%% *}"
                build_config_from_preset "$_picked"
            fi
        fi
    fi
fi

# =====================================================================
# Non-interactive mode (CI / scripted setups)
# =====================================================================
# If CONFIG_FILE is set, read all answers from that file instead of
# prompting. The file is a shell-sourceable subset of .env with these
# required keys: PROJECT_NAME, SITE_HOST, FLAVOUR, MAGENTO_VERSION,
# PHP_VERSION, DB_ENGINE, DB_VERSION, USE_VARNISH, USE_NODE.
#
# Usage: CONFIG_FILE=path/to/answers.env make configure
# Or:    make configure FILE=path/to/answers.env
# (the Makefile target translates FILE into CONFIG_FILE)
#
# The preset dispatcher above can also set CONFIG_FILE to a temporary
# composed file — same validation, different origin.
# ---------------------------------------------------------------------
if [[ -n "${CONFIG_FILE:-}" ]]; then
    [[ -f "$CONFIG_FILE" ]] || die "CONFIG_FILE not found: $CONFIG_FILE"
    if [[ -n "${_CONFIG_FROM_PRESET:-}" ]]; then
        say "Using preset ${C_GREEN}${_CONFIG_FROM_PRESET}${C_RESET}"
    else
        say "Non-interactive mode → reading answers from ${C_GREEN}${CONFIG_FILE}${C_RESET}"
    fi

    # shellcheck disable=SC1090
    set -a; . "$CONFIG_FILE"; set +a

    # Validate required keys
    for required in PROJECT_NAME SITE_HOST FLAVOUR MAGENTO_VERSION \
                    PHP_VERSION DB_ENGINE DB_VERSION \
                    OPENSEARCH_VERSION USE_VARNISH USE_NODE; do
        if [[ -z "${!required:-}" ]]; then
            die "$CONFIG_FILE missing required key: $required"
        fi
    done

    # Validate PROJECT_NAME format
    [[ "$PROJECT_NAME" =~ ^[a-z][a-z0-9_-]{1,30}$ ]] \
        || die "PROJECT_NAME must match ^[a-z][a-z0-9_-]{1,30}$ (got: $PROJECT_NAME)"

    # Resolve flavour key + version map
    case "$FLAVOUR" in
        magento|"Magento Open Source"|"Magento 2"*)
            FLAVOUR_KEY="magento"; FLAVOUR="Magento 2 (Open Source / Adobe Commerce)"
            declare -n VER_MAP=MAGENTO_VERSIONS ;;
        mageos|MageOS)
            FLAVOUR_KEY="mageos"; FLAVOUR="MageOS"
            declare -n VER_MAP=MAGEOS_VERSIONS ;;
        *) die "FLAVOUR must be 'magento' or 'mageos' (got: $FLAVOUR)" ;;
    esac

    # Validate MAGENTO_VERSION exists in the chosen map
    [[ -n "${VER_MAP[$MAGENTO_VERSION]:-}" ]] \
        || die "$FLAVOUR has no version $MAGENTO_VERSION in the compatibility matrix"

    declare -A SPEC
    parse_kv "${VER_MAP[$MAGENTO_VERSION]}" SPEC

    # Validate PHP_VERSION is allowed for this Magento release
    read -ra PHP_OPTS <<< "${SPEC[php]}"
    php_ok=0
    for v in "${PHP_OPTS[@]}"; do [[ "$v" == "$PHP_VERSION" ]] && php_ok=1; done
    [[ $php_ok -eq 1 ]] || die "PHP $PHP_VERSION is not compatible with $FLAVOUR $MAGENTO_VERSION (allowed: ${PHP_OPTS[*]})"

    # Validate DB engine + version
    case "$DB_ENGINE" in
        mariadb|mysql) ;;
        *) die "DB_ENGINE must be 'mariadb' or 'mysql' (got: $DB_ENGINE)" ;;
    esac
    # MySQL was dropped from 2.4.6 / 2.4.7 after MySQL 8.0 EOS (Apr 2026).
    # Reject configs that pin DB_ENGINE=mysql for a release with no mysql=
    # entry in the SPEC.
    if [[ "$DB_ENGINE" == "mysql" && -z "${SPEC[mysql]:-}" ]]; then
        die "MySQL is not certified on $FLAVOUR $MAGENTO_VERSION (set DB_ENGINE=mariadb)"
    fi
    read -ra DB_OPTS <<< "${SPEC[$DB_ENGINE]}"
    db_ok=0
    for v in "${DB_OPTS[@]}"; do [[ "$v" == "$DB_VERSION" ]] && db_ok=1; done
    [[ $db_ok -eq 1 ]] || die "$DB_ENGINE $DB_VERSION is not compatible with $FLAVOUR $MAGENTO_VERSION (allowed: ${DB_OPTS[*]})"

    # Validate OpenSearch version
    read -ra OS_OPTS <<< "${SPEC[opensearch]}"
    os_ok=0
    for v in "${OS_OPTS[@]}"; do [[ "$v" == "$OPENSEARCH_VERSION" ]] && os_ok=1; done
    [[ $os_ok -eq 1 ]] || die "OpenSearch $OPENSEARCH_VERSION is not compatible with $FLAVOUR $MAGENTO_VERSION (allowed: ${OS_OPTS[*]})"

    # Validate CACHE_ENGINE (optional - defaults to valkey when available,
    # otherwise redis). Reject mismatches against the SPEC: e.g. setting
    # CACHE_ENGINE=redis on 2.4.9 (where Adobe certifies only Valkey) is
    # the kind of drift we want to catch in fixtures.
    if [[ -z "${CACHE_ENGINE:-}" ]]; then
        if [[ -n "${SPEC[valkey]:-}" ]]; then CACHE_ENGINE="valkey"; else CACHE_ENGINE="redis"; fi
    fi
    case "$CACHE_ENGINE" in
        redis)
            [[ -n "${SPEC[redis]:-}" ]] \
                || die "CACHE_ENGINE=redis is not certified on $FLAVOUR $MAGENTO_VERSION (Adobe dropped Redis - use CACHE_ENGINE=valkey)" ;;
        valkey)
            [[ -n "${SPEC[valkey]:-}" ]] \
                || die "CACHE_ENGINE=valkey is not available on $FLAVOUR $MAGENTO_VERSION (use CACHE_ENGINE=redis)" ;;
        *)
            die "CACHE_ENGINE must be 'redis' or 'valkey' (got: $CACHE_ENGINE)" ;;
    esac

    # Normalise yes/no values
    case "$USE_VARNISH" in y|yes|Y|YES|true|1)  USE_VARNISH=yes ;; *) USE_VARNISH=no ;; esac
    case "$USE_NODE"    in y|yes|Y|YES|true|1)  USE_NODE=yes    ;; *) USE_NODE=no    ;; esac

    # Derived values that the interactive flow computes
    SITE_NAME="$(echo "${PROJECT_NAME:0:1}" | tr '[:lower:]' '[:upper:]')${PROJECT_NAME:1}"

    ok "validated config: ${FLAVOUR} ${MAGENTO_VERSION} / PHP ${PHP_VERSION} / ${DB_ENGINE}:${DB_VERSION} / OpenSearch ${OPENSEARCH_VERSION} / cache ${CACHE_ENGINE}"

    # Skip ahead to the .env writing step
    SKIP_INTERVIEW=1
fi

if [[ "${SKIP_INTERVIEW:-0}" -ne 1 ]]; then

# =====================================================================
# Q1: project name
# =====================================================================
DEFAULT_NAME="$(basename "$REPO_ROOT" | tr -cd '[:alnum:]-_' | tr '[:upper:]' '[:lower:]')"
[[ -z "$DEFAULT_NAME" || "$DEFAULT_NAME" == "magento-docker-bootstrap" ]] && DEFAULT_NAME="myproject"

while true; do
    PROJECT_NAME=$(ask "Project name (used for network, volumes, container prefix)" "$DEFAULT_NAME")
    if [[ "$PROJECT_NAME" =~ ^[a-z][a-z0-9_-]{1,30}$ ]]; then break; fi
    warn "lowercase letters, digits, '-' or '_' only; must start with a letter (max 31 chars)"
done

# =====================================================================
# Q2: local domain
# =====================================================================
SITE_HOST=$(ask "Local domain" "${PROJECT_NAME}.local")
SITE_NAME="$(echo "${PROJECT_NAME:0:1}" | tr '[:lower:]' '[:upper:]')${PROJECT_NAME:1}"

# =====================================================================
# Q3: Magento flavour + version
# =====================================================================
echo
FLAVOUR=$(choose "Which platform do you want?" "Magento 2 (Open Source / Adobe Commerce)" "MageOS")
case "$FLAVOUR" in
    "Magento 2"*)         declare -n VER_MAP=MAGENTO_VERSIONS; FLAVOUR_KEY="magento" ;;
    "MageOS")             declare -n VER_MAP=MAGEOS_VERSIONS;  FLAVOUR_KEY="mageos"  ;;
esac

# sort versions descending so the newest is on top
mapfile -t VERSION_LIST < <(printf '%s\n' "${!VER_MAP[@]}" | sort -rV)
echo
MAGENTO_VERSION=$(choose "Which ${FLAVOUR} version?" "${VERSION_LIST[@]}")

declare -A SPEC
parse_kv "${VER_MAP[$MAGENTO_VERSION]}" SPEC

# =====================================================================
# Q4: PHP version
# =====================================================================
read -ra PHP_OPTS <<< "${SPEC[php]}"
PHP_RECOMMENDED="${SPEC[recommended]}"
echo
say "PHP versions compatible with ${FLAVOUR} ${MAGENTO_VERSION}: ${PHP_OPTS[*]}  (recommended: ${PHP_RECOMMENDED})"
PHP_VERSION=$(choose "Pick a PHP version" "${PHP_OPTS[@]}")

# =====================================================================
# Q5: database engine + version
# =====================================================================
# Skip the engine question on releases where Adobe / MageOS dropped MySQL
# certification (currently 2.4.6 and 2.4.7 on-prem after the MySQL 8.0
# EOS on 30 Apr 2026). When `mysql=` is missing from the spec, auto-pick
# MariaDB; the user can still override DB_VERSION below.
echo
if [[ -n "${SPEC[mysql]:-}" ]]; then
    DB_ENGINE=$(choose "Database engine" "mariadb" "mysql")
else
    DB_ENGINE="mariadb"
    say "MySQL is not certified on ${FLAVOUR} ${MAGENTO_VERSION} (Adobe dropped support after MySQL 8.0 EOS, Apr 2026). Auto-selecting MariaDB."
fi
read -ra DB_OPTS <<< "${SPEC[$DB_ENGINE]}"
echo
DB_VERSION=$(choose "Pick a ${DB_ENGINE} version" "${DB_OPTS[@]}")

# =====================================================================
# Q5.5: cache backend (Redis or Valkey)
# =====================================================================
# Adobe has been replacing Redis with Valkey across the 2.4.x line since
# 2.4.6-p11 (Redis 7.2 EOS + Redis license change). On 2.4.9 Adobe drops
# Redis entirely from the certified matrix (only `valkey=` in the SPEC).
# Three cases:
#   1. SPEC has both redis= and valkey= -> ask, default valkey.
#   2. SPEC has only valkey= -> auto-pick valkey, no question.
#   3. SPEC has only redis=  -> auto-pick redis, no question.
echo
if [[ -n "${SPEC[redis]:-}" && -n "${SPEC[valkey]:-}" ]]; then
    CACHE_CHOICE=$(choose "Cache backend (Valkey is Adobe's current default; Redis kept for legacy patches)" \
        "valkey   (recommended - Valkey ${SPEC[valkey_recommended]})" \
        "redis    (legacy - Redis ${SPEC[redis]})")
    case "$CACHE_CHOICE" in
        valkey*) CACHE_ENGINE="valkey" ;;
        redis*)  CACHE_ENGINE="redis"  ;;
    esac
elif [[ -n "${SPEC[valkey]:-}" ]]; then
    CACHE_ENGINE="valkey"
    say "Cache backend: ${C_GREEN}valkey ${SPEC[valkey_recommended]}${C_RESET} (Adobe does not certify Redis on ${FLAVOUR} ${MAGENTO_VERSION})."
else
    CACHE_ENGINE="redis"
    say "Cache backend: ${C_GREEN}redis ${SPEC[redis]}${C_RESET}."
fi

# =====================================================================
# Q6: OpenSearch version
# =====================================================================
read -ra OS_OPTS <<< "${SPEC[opensearch]}"
OS_RECOMMENDED="${SPEC[opensearch_recommended]}"
echo
say "OpenSearch versions compatible with ${FLAVOUR} ${MAGENTO_VERSION}: ${OS_OPTS[*]}  (recommended: ${OS_RECOMMENDED})"
# MageOS-specific hint: the official matrix marks OpenSearch 3 as the
# preferred engine for new MageOS 2.2.x installations; the matrix above
# keeps 2.19 as the recommended default to ease migrations from existing
# 2.1.x / 2.0.x setups. If we offer 3.0.0 for this MageOS release, surface
# the "fresh-install" advice so the user can make an informed choice.
if [[ "$FLAVOUR_KEY" == "mageos" ]] && [[ " ${OS_OPTS[*]} " == *" 3.0.0 "* ]]; then
    say "MageOS recommends OpenSearch 3 for new installations (https://mage-os.org/get-started/system-requirements/)."
fi
OPENSEARCH_VERSION=$(choose "Pick an OpenSearch version" "${OS_OPTS[@]}")

# =====================================================================
# Q7: Varnish?
# =====================================================================
echo
USE_VARNISH=$(ask_yn "Enable Varnish full-page cache?" "n")

# =====================================================================
# Q8: Node.js?
# =====================================================================
echo
USE_NODE=$(ask_yn "Add Node.js container (frontend tooling, Vite HMR)?" "n")

fi  # end SKIP_INTERVIEW guard — both branches converge here

# ---------------------------------------------------------------------
# Auto-select Redis / Valkey / Varnish image versions from the per-release
# spec. These are not interactive choices: Adobe / MageOS publish exact
# compat tables, and picking a mismatched cache or Varnish is the kind of
# subtle breakage we want to make impossible. Honour any explicit override
# coming from CONFIG_FILE (so a CI fixture can pin a specific tag) but
# otherwise fall back to the matrix-recommended version for the chosen
# release. REDIS_VERSION and VALKEY_VERSION are both written to .env even
# when only one is active - lets users flip CACHE_ENGINE without re-running
# the wizard.
# ---------------------------------------------------------------------
REDIS_VERSION="${REDIS_VERSION:-${SPEC[redis]:-}}"
VALKEY_VERSION="${VALKEY_VERSION:-${SPEC[valkey_recommended]:-${SPEC[valkey]:-}}}"
VARNISH_VERSION="${VARNISH_VERSION:-${SPEC[varnish]}}"

# Pick the cache summary line based on the engine actually selected, so the
# user sees the exact image tag the renderer will use.
if [[ "$CACHE_ENGINE" == "valkey" ]]; then
    CACHE_SUMMARY="valkey/valkey:${VALKEY_VERSION}-alpine"
else
    CACHE_SUMMARY="redis:${REDIS_VERSION}-alpine"
fi

# =====================================================================
# Summary + confirm
# =====================================================================
cat <<EOF

${C_BOLD}─── Summary ──────────────────────────────────────────${C_RESET}
  Project name      : ${C_GREEN}${PROJECT_NAME}${C_RESET}
  Local domain      : ${C_GREEN}${SITE_HOST}${C_RESET}
  Platform          : ${C_GREEN}${FLAVOUR} ${MAGENTO_VERSION}${C_RESET}
  PHP               : ${C_GREEN}${PHP_VERSION}${C_RESET}
  Database          : ${C_GREEN}${DB_ENGINE}:${DB_VERSION}${C_RESET}
  OpenSearch        : ${C_GREEN}opensearchproject/opensearch:${OPENSEARCH_VERSION}${C_RESET}
  Cache (${CACHE_ENGINE})    : ${C_GREEN}${CACHE_SUMMARY}${C_RESET}
  Varnish           : ${C_GREEN}${USE_VARNISH}$([[ "$USE_VARNISH" == "yes" ]] && echo " (varnish:${VARNISH_VERSION})")${C_RESET}
  Node.js           : ${C_GREEN}${USE_NODE}${C_RESET}
  Static IPs        : ${C_GREEN}$([[ "$HOST_OS" == "linux" ]] && echo "yes (10.10.${SUBNET_BASE}.0/24)" || echo no)${C_RESET}
${C_BOLD}──────────────────────────────────────────────────────${C_RESET}

EOF

if [[ "${SKIP_INTERVIEW:-0}" -eq 1 ]]; then
    say "non-interactive mode → skipping confirmation"
else
    CONFIRM=$(ask_yn "Generate configuration with these values?" "y")
    [[ "$CONFIRM" != "yes" ]] && die "aborted by user"
fi

# =====================================================================
# Write .env
# =====================================================================
cat > "$ENV_FILE" <<EOF
# Generated by ${0##*/} on $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Edit values then re-run \`make rebuild\` to regenerate compose.yaml.
COMPOSE_PROJECT_NAME=${PROJECT_NAME}
PROJECT_NAME=${PROJECT_NAME}
SITE_HOST=${SITE_HOST}
SITE_NAME=${SITE_NAME}

FLAVOUR=${FLAVOUR_KEY}
MAGENTO_VERSION=${MAGENTO_VERSION}

PHP_VERSION=${PHP_VERSION}
DB_ENGINE=${DB_ENGINE}
DB_VERSION=${DB_VERSION}
OPENSEARCH_VERSION=${OPENSEARCH_VERSION}

# Cache backend - "valkey" (Adobe default since 2.4.6-p11) or "redis".
# render-compose.sh switches the cache service image based on this value.
# The service NAME stays "redis" in compose so phpredis hostnames in
# app/etc/env.php keep working unchanged.
CACHE_ENGINE=${CACHE_ENGINE}

# Cache + Varnish image tags - auto-selected from the per-release compat
# matrix in init.sh. Override only if you know your codebase needs a
# different version than Adobe / MageOS officially certify. REDIS_VERSION
# and VALKEY_VERSION are both written so you can flip CACHE_ENGINE without
# re-running the wizard. Lines with no value are intentional - they mean
# Adobe does not certify that engine for this Magento release.
REDIS_VERSION=${REDIS_VERSION}
VALKEY_VERSION=${VALKEY_VERSION}
VARNISH_VERSION=${VARNISH_VERSION}

USE_VARNISH=${USE_VARNISH}
USE_NODE=${USE_NODE}

HOST_OS=${HOST_OS}

# Third octet of the /24 subnet (Linux only — macOS uses service-name DNS).
# Container IPs are derived: db=.2 redis=.3 web=.4 php-fpm=.5 opensearch=.6
# nodejs=.7 mailhog=.8 phpmyadmin=.9 varnish=.10
# Edit and run \`make rebuild-config\` if you hit a subnet conflict.
DOCKER_SUBNET_BASE=${SUBNET_BASE}

# DB credentials (used by both Compose env vars and \`make install\`)
MYSQL_ROOT_PASSWORD=root
MYSQL_DATABASE=magento
MYSQL_USER=magento
MYSQL_PASSWORD=magento

# Magento admin defaults — change for shared environments
ADMIN_USER=admin
ADMIN_PASSWORD=admin123
ADMIN_EMAIL=admin@${SITE_HOST}
ADMIN_FIRSTNAME=Admin
ADMIN_LASTNAME=User
EOF
ok "wrote ${ENV_FILE}"

# =====================================================================
# Render compose.yaml from template
# =====================================================================
"${REPO_ROOT}/dockerimages/bin/render-compose.sh"
ok "wrote ${COMPOSE_FILE}"

# =====================================================================
# Hint /etc/hosts entry
# =====================================================================
cat <<EOF

${C_BOLD}─── Next steps ───────────────────────────────────────${C_RESET}

  1. Build & start containers:

       ${C_GREEN}make up${C_RESET} or ${C_GREEN}make init${C_RESET}

  2. Add the domain to your hosts file (admin / sudo required):

       ${C_GREEN}make sethostip${C_RESET}

  3. Place your Magento codebase in ${C_GREEN}./httpdocs${C_RESET}
     (or run \`make install\` for a fresh setup, or \`make import-db\`
     to import an existing dump from ./db_dumps/).

  4. Open: ${C_GREEN}https://${SITE_HOST}${C_RESET}

${C_BOLD}──────────────────────────────────────────────────────${C_RESET}

${C_DIM}magento-docker-bootstrap by Sergiu Ro. — magentofullstack.dev${C_RESET}

EOF
