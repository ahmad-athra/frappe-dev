#!/usr/bin/env bash
# =============================================================================
# setup-bench.sh — Idempotent bench bootstrap (runs INSIDE the frappe container)
# =============================================================================
#
# Why this exists
# ---------------
# Everything heavy or machine-specific under frappe-bench/ is intentionally
# git-ignored (apps/, env/, logs/, config/, sites/assets/). A fresh clone
# therefore contains only Procfile + sites/*.json, and `honcho start` fails
# (e.g. "cannot create logs/worker.log: Directory nonexistent").
# This script rebuilds that state from declarative sources:
#
#   .env                -> FRAPPE_BRANCH, SITE_NAME, DB_* (frappe core app)
#   apps.json           -> every other app (name, url, branch)
#   sites/apps.txt      -> apps that MUST be present (validated)
#   seed-data/*.sql.gz  -> site database (restored only if the DB is missing)
#
# Usage (normally via ./bench.sh setup or .\bench.ps1 setup):
#   setup-bench.sh            full, idempotent bootstrap
#   setup-bench.sh --check    readiness probe only; exit 1 if setup is needed
#
# Optional env overrides:
#   FRAPPE_REPO   (default https://github.com/frappe/frappe.git)
#   PYTHON        interpreter for the virtualenv (default: bench's default)
#   SKIP_BUILD=1  skip `bench build`
#   SKIP_SEED=1   skip the seed database restore
#
# Every step is skipped when its output already exists, so re-running is safe.
# =============================================================================
set -Eeuo pipefail

readonly WORKSPACE="/workspace"
readonly BENCH_DIR="${WORKSPACE}/frappe-bench"
readonly ENV_FILE="${WORKSPACE}/.env"
readonly APPS_MANIFEST="${WORKSPACE}/apps.json"
readonly SEED_FILE="${WORKSPACE}/seed-data/latest-seed.sql.gz"

# --- logging -----------------------------------------------------------------
log()  { printf '\033[1;36m[setup]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[setup]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[setup] WARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[setup] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }
trap 'die "step failed at line ${LINENO}: ${BASH_COMMAND}"' ERR

# --- config ------------------------------------------------------------------
# Resolve KEY from the process env first, then /workspace/.env, then default.
# .env may have CRLF line endings when edited on Windows, so strip \r.
env_value() {
    local key="$1" default="$2" value="${!1:-}"
    if [[ -z "${value}" && -f "${ENV_FILE}" ]]; then
        value="$(grep -E "^${key}=" "${ENV_FILE}" | tail -n 1 | cut -d= -f2- | tr -d '\r' || true)"
    fi
    printf '%s' "${value:-${default}}"
}

FRAPPE_BRANCH="$(env_value FRAPPE_BRANCH version-16)"
FRAPPE_REPO="$(env_value FRAPPE_REPO https://github.com/frappe/frappe.git)"
SITE_NAME="$(env_value SITE_NAME development.localhost)"
DB_HOST="$(env_value DB_HOST mariadb)"
DB_ROOT_PASSWORD="$(env_value DB_ROOT_PASSWORD 123)"

cd "${BENCH_DIR}"

# --- helpers -----------------------------------------------------------------
required_apps() {
    tr -d '\r' < sites/apps.txt | sed '/^[[:space:]]*$/d'
}

venv_ok() {
    [[ -x env/bin/python ]] && env/bin/python -c 'import frappe' >/dev/null 2>&1
}

# Prints the names of required apps that are missing or not importable.
missing_apps() {
    local app
    while read -r app; do
        if [[ ! -d "apps/${app}/.git" && ! -f "apps/${app}/pyproject.toml" ]]; then
            echo "${app}"
        fi
    done < <(required_apps)
}

# Readiness probe used by `bench.sh start` so failures are explicit, not cryptic.
check_ready() {
    local problems=()
    [[ -d logs ]] || problems+=("logs/ directory missing")
    [[ -n "$(missing_apps)" ]] && problems+=("apps missing: $(missing_apps | xargs)")
    venv_ok || problems+=("python virtualenv (env/) missing or broken")
    [[ -f sites/assets/assets.json ]] || problems+=("frontend assets not built (sites/assets)")
    if ((${#problems[@]})); then
        printf '\033[1;31m[check] Bench is not set up:\033[0m\n' >&2
        printf '  - %s\n' "${problems[@]}" >&2
        printf '\033[1;33m[check] Run: ./bench.sh setup   (Windows: .\\bench.ps1 setup)\033[0m\n' >&2
        exit 1
    fi
}

# clone_app <name> <url> <branch>
# Upstream Frappe repos: shallow clone, remote "upstream" (bench convention).
# Your own repos: full history, remote "origin" (so you can push).
clone_app() {
    local name="$1" url="$2" branch="$3" target="apps/$1"
    if [[ -d "${target}/.git" ]]; then
        log "app '${name}': present, skipping clone"
        return
    fi
    if [[ -e "${target}" ]]; then
        [[ -z "$(ls -A "${target}")" ]] || die "apps/${name} exists but is not a git repo; move it away and re-run."
        rmdir "${target}"
    fi
    if [[ -z "${url}" ]]; then
        die "app '${name}' has no \"url\" in apps.json and is not present in frappe-bench/apps/.
       Push it to a git remote, then set \"url\" for '${name}' in apps.json and re-run setup."
    fi

    local args=(--branch "${branch}")
    if [[ "${url}" == *github.com/frappe/* ]]; then
        args+=(--depth 1 --origin upstream)
    else
        args+=(--origin origin)
    fi
    log "app '${name}': cloning ${url} (${branch})"
    git clone "${args[@]}" "${url}" "${target}"
}

# Returns 0 if the site's DB exists, 1 if not, 2 on connection/config error.
site_db_exists() {
    env/bin/python - "${SITE_NAME}" "${DB_HOST}" "${DB_ROOT_PASSWORD}" <<'PY'
import json, sys
site, default_host, root_password = sys.argv[1:4]
try:
    import pymysql
    cfg = json.load(open("sites/common_site_config.json"))
    cfg.update(json.load(open(f"sites/{site}/site_config.json")))
    conn = pymysql.connect(
        host=cfg.get("db_host", default_host),
        port=int(cfg.get("db_port", 3306)),
        user="root",
        password=root_password,
        connect_timeout=10,
    )
    with conn.cursor() as cur:
        cur.execute("SHOW DATABASES LIKE %s", (cfg["db_name"],))
        found = cur.fetchone() is not None
    conn.close()
except Exception as exc:  # surfaced to the shell as exit code 2
    print(f"DB probe failed: {exc}", file=sys.stderr)
    sys.exit(2)
sys.exit(0 if found else 1)
PY
}

# --- steps -------------------------------------------------------------------
step_dirs() {
    log "1/6 bench directories"
    if [[ ! -w . ]]; then
        die "${BENCH_DIR} is not writable by $(id -un) (uid $(id -u)).
       On a Linux host, run from the repo root:  sudo chown -R $(id -u):$(id -g) frappe-bench"
    fi
    mkdir -p logs config/pids apps sites
}

step_apps() {
    log "2/6 apps"
    clone_app frappe "${FRAPPE_REPO}" "${FRAPPE_BRANCH}"

    [[ -f "${APPS_MANIFEST}" ]] || die "apps manifest not found at ${APPS_MANIFEST}"
    local name url branch
    while IFS='|' read -r name url branch; do
        clone_app "${name}" "${url}" "${branch:-${FRAPPE_BRANCH}}"
    done < <(python3 - "${APPS_MANIFEST}" <<'PY'
import json, sys
for app in json.load(open(sys.argv[1])):
    print("|".join([app["name"], app.get("url") or "", app.get("branch") or ""]))
PY
)

    local missing
    missing="$(missing_apps | xargs)"
    [[ -z "${missing}" ]] || die "sites/apps.txt requires apps that are still missing: ${missing}. Add them to apps.json."
}

step_env() {
    log "3/6 python virtualenv"
    if venv_ok; then
        log "env/ healthy, skipping"
        return
    fi
    # A venv copied from another machine/pyenv version has dangling symlinks; rebuild it.
    if [[ -e env ]] && ! env/bin/python -V >/dev/null 2>&1; then
        warn "env/ is broken (interpreter not runnable); recreating"
        rm -rf env
    fi
    if [[ -n "${PYTHON:-}" ]]; then
        bench setup env --python "${PYTHON}"
    else
        bench setup env
    fi
}

step_requirements() {
    log "4/6 python + node requirements"
    local app needs=0
    while read -r app; do
        if ! env/bin/python -c "import ${app}" >/dev/null 2>&1; then needs=1; fi
        if [[ -f "apps/${app}/package.json" && ! -d "apps/${app}/node_modules" ]]; then needs=1; fi
    done < <(required_apps)
    if ((needs)); then
        bench setup requirements
    else
        log "all apps importable and node_modules present, skipping"
    fi
}

step_build() {
    log "5/6 frontend assets"
    if [[ "${SKIP_BUILD:-0}" == "1" ]]; then
        warn "SKIP_BUILD=1, skipping bench build"
    elif [[ -f sites/assets/assets.json ]]; then
        log "sites/assets already built, skipping (run 'bench build' to force)"
    else
        bench build
    fi
}

step_seed() {
    log "6/6 site database (${SITE_NAME})"
    if [[ "${SKIP_SEED:-0}" == "1" ]]; then
        warn "SKIP_SEED=1, skipping seed restore"; return
    fi
    if [[ ! -f "sites/${SITE_NAME}/site_config.json" ]]; then
        warn "sites/${SITE_NAME}/site_config.json not found; create the site with 'bench new-site'"; return
    fi
    if [[ ! -f "${SEED_FILE}" ]]; then
        warn "no seed at ${SEED_FILE}; skipping restore"; return
    fi

    local rc=0
    site_db_exists || rc=$?
    case "${rc}" in
        0) log "database already exists, skipping restore (use ./bench.sh restore-seed to overwrite)" ;;
        1)
            log "database missing; restoring ${SEED_FILE}"
            bench --site "${SITE_NAME}" restore "${SEED_FILE}" \
                --db-root-username root --db-root-password "${DB_ROOT_PASSWORD}" --force
            bench --site "${SITE_NAME}" migrate
            ;;
        *) die "cannot reach MariaDB at '${DB_HOST}' as root; check DB_ROOT_PASSWORD in .env and 'docker compose ps'." ;;
    esac
}

# --- main --------------------------------------------------------------------
case "${1:-}" in
    --check) check_ready ;;
    "")
        step_dirs
        step_apps
        step_env
        step_requirements
        step_build
        step_seed
        ok "Bench is ready. Start it with: ./bench.sh start   (Windows: .\\bench.ps1 start)"
        ;;
    *) die "unknown argument '$1' (expected: --check)" ;;
esac
