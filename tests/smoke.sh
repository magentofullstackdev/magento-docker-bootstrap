#!/usr/bin/env bash
# =====================================================================
# Smoke test for magento-docker-bootstrap.
#
# Modes:
#   ./tests/smoke.sh             # fast: configure + validate YAML, no docker run
#   ./tests/smoke.sh --full      # full: also pulls images, ups stack, curls
#
# Exit code: 0 if all scenarios pass, 1 if any fail.
# =====================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

MODE="${1:-fast}"
FIXTURES_DIR="$REPO_ROOT/tests/fixtures"
TEMPLATES_DIR="$REPO_ROOT/dockerimages/templates"
PASSED=0
FAILED=0
FAILED_NAMES=()

# ---- colours -------------------------------------------------------------
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && [[ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]]; then
    GREEN="$(tput setaf 2)"; RED="$(tput setaf 1)"; YELLOW="$(tput setaf 3)"
    BOLD="$(tput bold)"; RESET="$(tput sgr0)"
else
    GREEN=''; RED=''; YELLOW=''; BOLD=''; RESET=''
fi

pass() { printf "${GREEN}✓${RESET} %s\n" "$*"; PASSED=$((PASSED+1)); }
fail() { printf "${RED}✗${RESET} %s\n" "$*"; FAILED=$((FAILED+1)); FAILED_NAMES+=("$1"); }
info() { printf "${YELLOW}>>${RESET} %s\n" "$*"; }
hdr()  { printf "\n${BOLD}=== %s ===${RESET}\n" "$*"; }

# ---- prerequisites -------------------------------------------------------
hdr "checking prerequisites"

command -v bash >/dev/null   || { echo "✗ bash required"; exit 1; }

if command -v docker >/dev/null 2>&1; then
    HAS_DOCKER=1
    pass "docker available"
else
    HAS_DOCKER=0
    info "docker not available — 'docker compose config' check + full mode will be skipped"
fi

if command -v python3 >/dev/null && python3 -c "import yaml" 2>/dev/null; then
    pass "python3 + pyyaml available for YAML validation"
    HAS_YAML=1
else
    info "pyyaml not available — YAML structural check skipped (still parsed by docker)"
    HAS_YAML=0
fi
echo

# ---- fixture-driven test runner ------------------------------------------
run_scenario() {
    local fixture_name="$1"
    local fixture_path="$FIXTURES_DIR/${fixture_name}.env"

    hdr "scenario: $fixture_name"

    [[ -f "$fixture_path" ]] || { fail "$fixture_name (fixture not found)"; return; }

    # 1. clean slate
    rm -f "$REPO_ROOT/.env" "$REPO_ROOT/compose.yaml"
    if [[ "$HAS_DOCKER" -eq 1 ]]; then
        docker compose -p smoketest down -v --remove-orphans 2>/dev/null || true
    fi

    # 2. configure (non-interactive)
    if ! CONFIG_FILE="$fixture_path" bash dockerimages/bin/init.sh > /tmp/smoke-configure.log 2>&1; then
        fail "$fixture_name (configure failed)"
        sed 's/^/    /' /tmp/smoke-configure.log
        return
    fi
    pass "configure produced .env + compose.yaml"

    # 3. validate YAML structure
    if [[ "$HAS_YAML" -eq 1 ]]; then
        if python3 -c "
import yaml, sys
d = yaml.safe_load(open('compose.yaml'))
assert 'services' in d, 'no services key'
assert 'db' in d['services'], 'no db service'
assert 'php-fpm' in d['services'], 'no php-fpm service'
assert 'web' in d['services'], 'no web service'
assert 'opensearch' in d['services'], 'no opensearch service'
print('services:', sorted(d['services'].keys()))
" > /tmp/smoke-yaml.log 2>&1; then
            pass "compose.yaml structurally valid ($(grep services: /tmp/smoke-yaml.log | head -1))"
        else
            fail "$fixture_name (YAML validation failed)"
            sed 's/^/    /' /tmp/smoke-yaml.log
            return
        fi
    fi

    # 4. ask docker compose to validate too (catches compose-specific errors)
    if [[ "$HAS_DOCKER" -eq 1 ]]; then
        if docker compose config -q > /tmp/smoke-config.log 2>&1; then
            pass "docker compose config -q passes"
        else
            fail "$fixture_name (docker compose config failed)"
            sed 's/^/    /' /tmp/smoke-config.log
            return
        fi
    fi

    # 5. fast mode stops here. full mode actually brings the stack up.
    if [[ "$MODE" != "--full" ]]; then
        pass "$fixture_name (fast mode passed)"
        return
    fi
    if [[ "$HAS_DOCKER" -eq 0 ]]; then
        fail "$fixture_name (--full requested but docker not available)"
        return
    fi

    info "full mode — bringing stack up (this takes a few minutes the first time)"

    # 6. external volume prerequisite — compose.yaml declares
    # `magento-composer-cache` as external so it can be shared across
    # projects. On a fresh CI runner the volume doesn't exist yet, which
    # makes `docker compose up` fail with "external volume not found".
    # `docker volume create` is idempotent.
    docker volume create magento-composer-cache > /dev/null 2>&1 || true

    # 7. up
    if ! docker compose up -d --build > /tmp/smoke-up.log 2>&1; then
        fail "$fixture_name (docker compose up failed)"
        tail -30 /tmp/smoke-up.log | sed 's/^/    /'
        docker compose down -v --remove-orphans > /dev/null 2>&1 || true
        return
    fi
    pass "containers built + started"

    # 7. wait for php-fpm to be reachable + nginx alive
    info "waiting up to 60s for nginx to respond"
    local got_response=0
    for _ in $(seq 1 30); do
        sleep 2
        if docker compose exec -T web wget -q -O /dev/null --no-check-certificate https://localhost/ 2>/dev/null \
           || docker compose exec -T web curl -sk -o /dev/null https://localhost/ 2>/dev/null; then
            got_response=1; break
        fi
    done
    if [[ $got_response -eq 1 ]]; then
        pass "nginx responding inside the network"
    else
        fail "$fixture_name (nginx did not respond after 60s)"
        docker compose ps | sed 's/^/    /'
        docker compose logs --tail=30 web | sed 's/^/    /'
    fi

    # 8. tear down
    info "tearing stack down"
    docker compose down -v --remove-orphans > /dev/null 2>&1 || true
    pass "$fixture_name (full mode completed)"
}

# ---- preset-driven test runner -------------------------------------------
# Mirrors run_scenario but invokes init.sh through the PRESET= entry point.
# PROJECT_NAME / SITE_HOST / USE_NODE are passed as env vars so init.sh skips
# the prompts and validates the preset against the compatibility matrix
# exactly the way `make configure PRESET=name` would.
run_preset() {
    local preset_name="$1"
    local preset_file="$TEMPLATES_DIR/${preset_name}.env"

    hdr "preset: $preset_name"

    [[ -f "$preset_file" ]] || { fail "$preset_name (preset file not found)"; return; }

    rm -f "$REPO_ROOT/.env" "$REPO_ROOT/compose.yaml"
    if [[ "$HAS_DOCKER" -eq 1 ]]; then
        docker compose -p smoketest down -v --remove-orphans 2>/dev/null || true
    fi

    if ! PRESET="$preset_name" PROJECT_NAME=smoketest SITE_HOST=smoketest.local USE_NODE=no \
            bash dockerimages/bin/init.sh > /tmp/smoke-configure.log 2>&1; then
        fail "$preset_name (configure failed)"
        sed 's/^/    /' /tmp/smoke-configure.log
        return
    fi
    pass "preset produced .env + compose.yaml"

    if [[ "$HAS_YAML" -eq 1 ]]; then
        if python3 -c "
import yaml, sys
d = yaml.safe_load(open('compose.yaml'))
assert 'services' in d, 'no services key'
assert 'db' in d['services'], 'no db service'
assert 'php-fpm' in d['services'], 'no php-fpm service'
assert 'web' in d['services'], 'no web service'
assert 'opensearch' in d['services'], 'no opensearch service'
print('services:', sorted(d['services'].keys()))
" > /tmp/smoke-yaml.log 2>&1; then
            pass "compose.yaml structurally valid ($(grep services: /tmp/smoke-yaml.log | head -1))"
        else
            fail "$preset_name (YAML validation failed)"
            sed 's/^/    /' /tmp/smoke-yaml.log
            return
        fi
    fi

    if [[ "$HAS_DOCKER" -eq 1 ]]; then
        if docker compose config -q > /tmp/smoke-config.log 2>&1; then
            pass "docker compose config -q passes"
        else
            fail "$preset_name (docker compose config failed)"
            sed 's/^/    /' /tmp/smoke-config.log
            return
        fi
    fi

    pass "$preset_name (preset path validated)"
}

# ---- run all fixtures ----------------------------------------------------
for fixture in minimal full-stack mageos magento-249 valkey; do
    run_scenario "$fixture" || true
done

# ---- run every preset shipped under dockerimages/templates/ -------------
# Catches matrix drift: if someone updates the matrix in init.sh without
# bumping the preset (or vice versa), validation will die here.
if compgen -G "$TEMPLATES_DIR/*.env" > /dev/null; then
    for preset_file in "$TEMPLATES_DIR"/*.env; do
        run_preset "$(basename "$preset_file" .env)" || true
    done
else
    info "no presets in $TEMPLATES_DIR — skipping preset checks"
fi

# ---- final cleanup -------------------------------------------------------
rm -f "$REPO_ROOT/.env" "$REPO_ROOT/compose.yaml"

# ---- summary -------------------------------------------------------------
hdr "summary"
printf "${GREEN}passed:${RESET} %d   ${RED}failed:${RESET} %d\n" "$PASSED" "$FAILED"

if [[ $FAILED -gt 0 ]]; then
    printf "\nfailed scenarios:\n"
    for name in "${FAILED_NAMES[@]}"; do
        printf "  - %s\n" "$name"
    done
    exit 1
fi
exit 0
