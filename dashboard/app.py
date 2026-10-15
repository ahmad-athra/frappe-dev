#!/usr/bin/env python3
"""
Frappe & ERPNext v16 Enterprise Web Control Center
Zero-dependency HTTP server running directly inside bench container on port 8080.
Provides GUI controls for:
- Database Backups & Restores
- Background Workers & Schedulers
- Apps Management (Install/Uninstall/List)
- Redis Cache & Queue
- Live System Telemetry
"""

import http.server
import json
import os
import subprocess
import urllib.parse
from http import HTTPStatus

PORT = int(os.environ.get("DASHBOARD_PORT", 8080))
BENCH_DIR = "/workspace/frappe-bench"
DEFAULT_SITE = "development.localhost"


def get_env_ports():
    web_port = os.environ.get("WEB_PORT")
    socketio_port = os.environ.get("SOCKETIO_PORT")
    dashboard_port = os.environ.get("DASHBOARD_PORT")

    # If missing from environment, attempt to parse .env file
    if not (web_port and socketio_port and dashboard_port):
        env_paths = [
            "/workspace/.env",
            os.path.join(os.path.dirname(__file__), "..", ".env"),
            os.path.join(BENCH_DIR, "..", ".env"),
            ".env",
        ]
        for ep in env_paths:
            if os.path.exists(ep):
                try:
                    with open(ep, "r", encoding="utf-8") as f:
                        for line in f:
                            line = line.strip()
                            if line and not line.startswith("#") and "=" in line:
                                k, v = line.split("=", 1)
                                k = k.strip()
                                v = v.strip().strip("'\"")
                                if k == "WEB_PORT" and not web_port:
                                    web_port = v
                                elif k == "SOCKETIO_PORT" and not socketio_port:
                                    socketio_port = v
                                elif k == "DASHBOARD_PORT" and not dashboard_port:
                                    dashboard_port = v
                except Exception:
                    pass

    return {
        "web_port": web_port or "8000",
        "socketio_port": socketio_port or "9000",
        "dashboard_port": dashboard_port or "8080",
    }


def run_cmd(cmd, cwd=BENCH_DIR):
    try:
        res = subprocess.run(
            cmd,
            shell=True,
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=120,
        )
        return {
            "success": res.returncode == 0,
            "stdout": res.stdout.strip(),
            "stderr": res.stderr.strip(),
        }
    except Exception as e:
        return {"success": False, "stdout": "", "stderr": str(e)}


def get_status():
    ports = get_env_ports()

    # Check processes
    ps_res = run_cmd("ps aux")
    ps_out = ps_res.get("stdout", "")

    honcho_running = "honcho" in ps_out or "bench_helper" in ps_out
    web_running = "serve" in ps_out or f":{ports['web_port']}" in ps_out or honcho_running
    socketio_running = "socketio" in ps_out
    workers_running = "worker" in ps_out
    schedule_running = "schedule" in ps_out

    # Check installed apps
    apps = []
    apps_txt_path = os.path.join(BENCH_DIR, "sites", "apps.txt")
    if os.path.exists(apps_txt_path):
        with open(apps_txt_path, "r") as f:
            apps = [line.strip() for line in f if line.strip()]
    elif os.path.exists(os.path.join(BENCH_DIR, "apps")):
        apps = os.listdir(os.path.join(BENCH_DIR, "apps"))

    # Check backups
    backups = []
    backup_dir = os.path.join(BENCH_DIR, "sites", DEFAULT_SITE, "private", "backups")
    if os.path.exists(backup_dir):
        for fname in sorted(os.listdir(backup_dir), reverse=True):
            if fname.endswith(".sql.gz"):
                fpath = os.path.join(backup_dir, fname)
                size_mb = round(os.path.getsize(fpath) / (1024 * 1024), 2)
                backups.append({"filename": fname, "size_mb": size_mb, "path": fpath})

    # Scheduler info
    sched_info = run_cmd(f"bench --site {DEFAULT_SITE} doctor")

    return {
        "site": DEFAULT_SITE,
        "web_running": web_running,
        "socketio_running": socketio_running,
        "workers_running": workers_running,
        "schedule_running": schedule_running,
        "honcho_running": honcho_running,
        "apps": apps,
        "backups": backups,
        "scheduler_details": sched_info.get("stdout", "") or sched_info.get("stderr", ""),
        "web_port": ports["web_port"],
        "socketio_port": ports["socketio_port"],
        "dashboard_port": ports["dashboard_port"],
    }


class ControlHandler(http.server.BaseHTTPRequestHandler):
    def _send_json(self, data, status=HTTPStatus.OK):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()
        self.wfile.write(json.dumps(data).encode("utf-8"))

    def do_OPTIONS(self):
        self._send_json({"ok": True})

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        if url.path == "/api/status":
            self._send_json(get_status())
        elif url.path in ["/", "/index.html"]:
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            html_path = os.path.join(os.path.dirname(__file__), "templates", "index.html")
            if os.path.exists(html_path):
                with open(html_path, "r", encoding="utf-8") as f:
                    content = f.read()
                ports = get_env_ports()
                content = content.replace("{{WEB_PORT}}", str(ports["web_port"]))
                content = content.replace("{{SOCKETIO_PORT}}", str(ports["socketio_port"]))
                content = content.replace("{{DASHBOARD_PORT}}", str(ports["dashboard_port"]))
                self.wfile.write(content.encode("utf-8"))
            else:
                self.wfile.write(b"<h1>Frappe Bench Control Center</h1>")
        else:
            self.send_response(HTTPStatus.NOT_FOUND)
            self.end_headers()

    def do_POST(self):
        url = urllib.parse.urlparse(self.path)
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length).decode("utf-8") if content_length > 0 else "{}"
        try:
            payload = json.loads(body)
        except Exception:
            payload = {}

        action = url.path.replace("/api/", "")

        if action == "backup":
            site = payload.get("site", DEFAULT_SITE)
            res = run_cmd(f"bench --site {site} backup --with-files")
            self._send_json(res)

        elif action == "restore":
            filename = payload.get("filename")
            site = payload.get("site", DEFAULT_SITE)
            if not filename:
                self._send_json({"success": False, "stderr": "Backup filename required"}, status=HTTPStatus.BAD_REQUEST)
                return
            backup_path = os.path.join(BENCH_DIR, "sites", site, "private", "backups", filename)
            res = run_cmd(f"bench --site {site} restore {backup_path} --db-root-password 123")
            self._send_json(res)

        elif action == "server/start":
            res = run_cmd("nohup honcho start socketio watch schedule worker web > /workspace/frappe-bench/logs/honcho.log 2>&1 &")
            self._send_json({"success": True, "message": "Dev server started"})

        elif action == "server/stop":
            run_cmd("pkill -f honcho; pkill -f 'frappe.utils.bench_helper'; pkill -f 'node.*socketio'")
            self._send_json({"success": True, "message": "Dev server stopped"})

        elif action == "workers/restart":
            run_cmd("pkill -f 'worker'")
            self._send_json({"success": True, "message": "Workers signaled to restart"})

        elif action == "scheduler/toggle":
            site = payload.get("site", DEFAULT_SITE)
            enable = payload.get("enable", True)
            cmd = f"bench --site {site} enable-scheduler" if enable else f"bench --site {site} disable-scheduler"
            res = run_cmd(cmd)
            self._send_json(res)

        elif action == "redis/flush":
            res_cache = run_cmd("redis-cli -h redis-cache flushall")
            res_queue = run_cmd("redis-cli -h redis-queue flushall")
            self._send_json({"success": True, "cache": res_cache, "queue": res_queue})

        elif action == "apps/install":
            app = payload.get("app")
            site = payload.get("site", DEFAULT_SITE)
            if not app:
                self._send_json({"success": False, "stderr": "App name required"}, status=HTTPStatus.BAD_REQUEST)
                return
            res = run_cmd(f"bench --site {site} install-app {app}")
            self._send_json(res)

        elif action == "apps/uninstall":
            app = payload.get("app")
            site = payload.get("site", DEFAULT_SITE)
            if not app:
                self._send_json({"success": False, "stderr": "App name required"}, status=HTTPStatus.BAD_REQUEST)
                return
            res = run_cmd(f"bench --site {site} uninstall-app {app}")
            self._send_json(res)

        elif action == "migrate":
            site = payload.get("site", DEFAULT_SITE)
            res = run_cmd(f"bench --site {site} migrate")
            self._send_json(res)

        else:
            self._send_json({"error": "Unknown action"}, status=HTTPStatus.NOT_FOUND)


def main():
    print(f"🚀 Frappe Bench Control Server listening on http://0.0.0.0:{PORT}")
    server = http.server.HTTPServer(("0.0.0.0", PORT), ControlHandler)
    server.serve_forever()


if __name__ == "__main__":
    main()
