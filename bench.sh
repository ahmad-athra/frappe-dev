#!/usr/bin/env bash
set -e

COMPOSE_FILE="docker-compose.yml"
FRAPPE_SERVICE="frappe"
DEFAULT_SITE="development.localhost"

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
    start)
        if [[ "$1" == "-d" ]]; then
            echo "Starting Frappe Bench Dev Server in background..."
            docker compose -f "$COMPOSE_FILE" exec -d "$FRAPPE_SERVICE" bash -c "cd /workspace/frappe-bench && honcho start socketio watch schedule worker_short worker_long worker_default web > /workspace/frappe-bench/logs/honcho.log 2>&1"
            echo "Bench server started in background! Check logs with: ./bench.sh logs"
        else
            echo "Starting Frappe Bench Dev Server (port 8000, socketio 9000)..."
            docker compose -f "$COMPOSE_FILE" exec -it "$FRAPPE_SERVICE" bash -c "cd /workspace/frappe-bench && honcho start socketio watch schedule worker_short worker_long worker_default web"
        fi
        ;;
    stop)
        echo "Stopping bench dev server..."
        docker compose -f "$COMPOSE_FILE" exec "$FRAPPE_SERVICE" bash -c "pkill -f honcho 2>/dev/null; pkill -f 'frappe.utils.bench_helper' 2>/dev/null; pkill -f 'node.*socketio' 2>/dev/null; true"
        echo "Stopped."
        ;;
    restart)
        $0 stop
        sleep 2
        $0 start -d
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
        docker compose -f "$COMPOSE_FILE" exec "$FRAPPE_SERVICE" bash -c "cd /workspace/frappe-bench && bench --site $SITE restore /workspace/seed-data/latest-seed.sql.gz --db-root-password 123"
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
        echo "Starting Web Control Center on http://localhost:8080 ..."
        docker compose -f "$COMPOSE_FILE" exec -d "$FRAPPE_SERVICE" bash -c "python3 /workspace/dashboard/app.py > /workspace/dashboard/dashboard.log 2>&1"
        ;;
    exec)
        docker compose -f "$COMPOSE_FILE" exec -it "$FRAPPE_SERVICE" bash -c "cd /workspace/frappe-bench && bench $*"
        ;;
    *)
        echo "Usage: ./bench.sh [up|down|ps|bash|start|stop|restart|worker|scheduler|backup|export-seed|restore-seed|install-app|uninstall-app|new-app|get-app|migrate|console|redis|logs|dashboard|exec]"
        ;;
esac
