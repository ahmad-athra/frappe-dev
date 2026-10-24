#!/usr/bin/env bash
set -eo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

# Git Bash / MSYS on Windows rewrites any argument starting with "/" into a Windows path
# ("/workspace/x" -> "C:/Program Files/Git/workspace/x") before docker sees it.
# All paths we pass to `docker compose exec` are container paths, so disable that.
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL="*"

COMPOSE_FILE="docker-compose.yml"
FRAPPE_SERVICE="frappe"

if [ -f .env ]; then
    export $(grep -E '^(WEB_PORT|SOCKETIO_PORT|DASHBOARD_PORT|SITE_NAME|DB_ROOT_PASSWORD)=' .env | tr -d '\r' | xargs)
fi
WEB_PORT="${WEB_PORT:-8000}"
SOCKETIO_PORT="${SOCKETIO_PORT:-9000}"
DASHBOARD_PORT="${DASHBOARD_PORT:-8080}"
DEFAULT_SITE="${SITE_NAME:-development.localhost}"
DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-123}"

# Fails fast with an actionable message when git-ignored bench state is missing.
PREFLIGHT="bash /workspace/scripts/setup-bench.sh --check"

COMMAND="${1:-help}"
shift || true

case "$COMMAND" in
    up)
        echo "Starting Docker stack..."
        docker compose -f "$COMPOSE_FILE" up -d
        ;;
    down)
        echo "Stopping Docker stack..."
        docker compose -f "$COMPOSE_FILE" down
        ;;
    ps|status)
        docker compose -f "$COMPOSE_FILE" ps
        ;;
    bash)
        docker compose -f "$COMPOSE_FILE" exec -e "TERM=xterm-256color" -it "$FRAPPE_SERVICE" bash
        ;;
    setup)
        # Fresh clone / new machine: rebuild apps, env, logs, assets and restore the seed DB.
        # Private apps (git@/ssh:// URLs) are cloned HERE on the host, where your SSH keys live;
        # the container has no git credentials. Everything else happens inside the container.
        echo "Ensuring Docker stack is up (recreates frappe if compose config changed)..."
        docker compose -f "$COMPOSE_FILE" up -d
        # Parse apps.json with the container's python: host python3 on Windows is often the Store stub.
        docker compose -f "$COMPOSE_FILE" exec -T "$FRAPPE_SERVICE" python3 -c 'import json; [print("|".join([a["name"], a.get("url") or "", a.get("branch") or "version-16"])) for a in json.load(open("/workspace/apps.json"))]' |
        tr -d '\r' |
        while IFS='|' read -r APP URL BRANCH; do
            if [[ "$URL" =~ ^(git@|ssh://) && ! -d "frappe-bench/apps/$APP/.git" ]]; then
                echo "Cloning private app '$APP' on host ($URL, $BRANCH)..."
                mkdir -p frappe-bench/apps
                git clone --branch "$BRANCH" "$URL" "frappe-bench/apps/$APP"
            fi
        done
        docker compose -f "$COMPOSE_FILE" exec "$FRAPPE_SERVICE" bash /workspace/scripts/setup-bench.sh
        ;;
    start)
        docker compose -f "$COMPOSE_FILE" exec "$FRAPPE_SERVICE" $PREFLIGHT
        if [[ "$1" == "-d" ]]; then
            echo "Starting Frappe Bench Dev Server in background..."
            docker compose -f "$COMPOSE_FILE" exec -d "$FRAPPE_SERVICE" bash -c "cd /workspace/frappe-bench && honcho start socketio watch schedule worker web > /workspace/frappe-bench/logs/honcho.log 2>&1"
            echo "Bench server started in background! Check logs with: ./bench.sh logs"
        else
            echo "Starting Frappe Bench Dev Server (port $WEB_PORT, socketio $SOCKETIO_PORT)..."
            docker compose -f "$COMPOSE_FILE" exec -it "$FRAPPE_SERVICE" bash -c "cd /workspace/frappe-bench && honcho start socketio watch schedule worker web"
        fi
        ;;
    stop)
        echo "Stopping bench dev server..."
        docker compose -f "$COMPOSE_FILE" exec "$FRAPPE_SERVICE" bash -c "pkill -f honcho 2>/dev/null; pkill -f 'frappe.utils.bench_helper' 2>/dev/null; pkill -f 'node.*socketio' 2>/dev/null; true"
        echo "Stopped."
        ;;
    restart)
        ./bench.sh stop
        sleep 2
        ./bench.sh start -d
        ;;
    worker)
        SUB="${1:-status}"
        if [[ "$SUB" == "restart" ]]; then
            echo "Restarting RQ workers..."
            docker compose -f "$COMPOSE_FILE" exec "$FRAPPE_SERVICE" bash -c "pkill -f 'worker' 2>/dev/null; true"
            echo "Workers restarted."
        else
            docker compose -f "$COMPOSE_FILE" exec "$FRAPPE_SERVICE" bash -c "cd /workspace/frappe-bench && bench --site $DEFAULT_SITE doctor || true"
        fi
        ;;
    scheduler)
        SUB="${1:-status}"
        SITE="${2:-$DEFAULT_SITE}"
        if [[ "$SUB" == "enable" ]]; then
            docker compose -f "$COMPOSE_FILE" exec "$FRAPPE_SERVICE" bash -c "cd /workspace/frappe-bench && bench --site $SITE enable-scheduler"
        elif [[ "$SUB" == "disable" ]]; then
            docker compose -f "$COMPOSE_FILE" exec "$FRAPPE_SERVICE" bash -c "cd /workspace/frappe-bench && bench --site $SITE disable-scheduler"
        else
            docker compose -f "$COMPOSE_FILE" exec "$FRAPPE_SERVICE" bash -c "cd /workspace/frappe-bench && bench --site $SITE doctor"
        fi
        ;;
    backup)
        SITE="${1:-$DEFAULT_SITE}"
        echo "Backing up site '$SITE'..."
        docker compose -f "$COMPOSE_FILE" exec "$FRAPPE_SERVICE" bash -c "cd /workspace/frappe-bench && bench --site $SITE backup --with-files"
        ;;
    export-seed)
        SITE="${1:-$DEFAULT_SITE}"
        echo "Exporting site snapshot to seed-data/..."
        docker compose -f "$COMPOSE_FILE" exec "$FRAPPE_SERVICE" bash -c "cd /workspace/frappe-bench && bench --site $SITE backup && cp \$(ls -t /workspace/frappe-bench/sites/$SITE/private/backups/*-database.sql.gz | head -n 1) /workspace/seed-data/latest-seed.sql.gz && cp /workspace/frappe-bench/sites/$SITE/site_config.json /workspace/seed-data/site_config.json"
        echo "Seed snapshot saved!"
        ;;
    restore-seed)
        SITE="${1:-$DEFAULT_SITE}"
        echo "Restoring seed snapshot into '$SITE'..."
        docker compose -f "$COMPOSE_FILE" exec "$FRAPPE_SERVICE" bash -c "cd /workspace/frappe-bench && bench --site $SITE restore /workspace/seed-data/latest-seed.sql.gz --db-root-password '$DB_ROOT_PASSWORD'"
        ;;
    install-app)
        APP="$1"
        SITE="${2:-$DEFAULT_SITE}"
        docker compose -f "$COMPOSE_FILE" exec "$FRAPPE_SERVICE" bash -c "cd /workspace/frappe-bench && bench --site $SITE install-app $APP"
        ;;
    uninstall-app)
        APP="$1"
        SITE="${2:-$DEFAULT_SITE}"
        docker compose -f "$COMPOSE_FILE" exec "$FRAPPE_SERVICE" bash -c "cd /workspace/frappe-bench && bench --site $SITE uninstall-app $APP"
        ;;
    new-app)
        APP="$1"
        docker compose -f "$COMPOSE_FILE" exec -it "$FRAPPE_SERVICE" bash -c "cd /workspace/frappe-bench && bench new-app $APP"
        ;;
    get-app)
        TARGET="$1"
        docker compose -f "$COMPOSE_FILE" exec "$FRAPPE_SERVICE" bash -c "cd /workspace/frappe-bench && bench get-app $TARGET"
        ;;
    migrate)
        SITE="${1:-$DEFAULT_SITE}"
        docker compose -f "$COMPOSE_FILE" exec "$FRAPPE_SERVICE" bash -c "cd /workspace/frappe-bench && bench --site $SITE migrate"
        ;;
    console)
        SITE="${1:-$DEFAULT_SITE}"
        docker compose -f "$COMPOSE_FILE" exec -it "$FRAPPE_SERVICE" bash -c "cd /workspace/frappe-bench && bench --site $SITE console"
        ;;
    redis)
        SUB="${1:-info}"
        if [[ "$SUB" == "flush" ]]; then
            docker compose -f "$COMPOSE_FILE" exec redis-cache redis-cli flushall
            docker compose -f "$COMPOSE_FILE" exec redis-queue redis-cli flushall
            echo "Redis flushed."
        else
            docker compose -f "$COMPOSE_FILE" exec redis-cache redis-cli info memory
            docker compose -f "$COMPOSE_FILE" exec redis-queue redis-cli info memory
        fi
        ;;
    logs)
        docker compose -f "$COMPOSE_FILE" exec "$FRAPPE_SERVICE" tail -n 50 -f /workspace/frappe-bench/logs/honcho.log
        ;;
    dashboard)
        echo "Starting Web Control Center on http://localhost:$DASHBOARD_PORT ..."
        docker compose -f "$COMPOSE_FILE" exec -d "$FRAPPE_SERVICE" bash -c "python3 /workspace/dashboard/app.py > /workspace/dashboard/dashboard.log 2>&1"
        ;;
    exec)
        docker compose -f "$COMPOSE_FILE" exec -it "$FRAPPE_SERVICE" bash -c "cd /workspace/frappe-bench && bench $*"
        ;;
    *)
        echo "Usage: ./bench.sh [up|down|ps|bash|setup|start|stop|restart|worker|scheduler|backup|export-seed|restore-seed|install-app|uninstall-app|new-app|get-app|migrate|console|redis|logs|dashboard|exec]"
        ;;
esac
