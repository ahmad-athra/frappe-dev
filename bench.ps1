<#
.SYNOPSIS
    Frappe & ERPNext v16 Bench CLI Controller for Docker.
.DESCRIPTION
    Full-featured development control utility for Frappe, ERPNext, Background Workers,
    Schedulers, Redis, Backups, and Custom Apps.
#>

param(
    [Parameter(Position=0)]
    [string]$Command = "help",

    [Parameter(Position=1, ValueFromRemainingArguments=$true)]
    [string[]]$ArgsList
)

$DefaultSite = "development.localhost"
$ComposeFile = "docker-compose.yml"
$FrappeService = "frappe"

function Print-Header {
    Write-Host "`n🚀 Frappe & ERPNext v16 Enterprise Dev CLI" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor DarkGray
}

function Show-Help {
    Print-Header
    Write-Host "Usage: .\bench.ps1 <command> [options]`n" -ForegroundColor Yellow
    Write-Host "Stack Lifecycle:" -ForegroundColor Green
    Write-Host "  up                 Start all Docker containers (MariaDB, Redis, Frappe)"
    Write-Host "  down               Stop all Docker containers"
    Write-Host "  ps / status        Show running container status and health"
    Write-Host "  bash               Open interactive Bash shell inside frappe container`n"

    Write-Host "Dev Server & Honcho:" -ForegroundColor Green
    Write-Host "  start [-d]         Start bench dev server (foreground or -d for background)"
    Write-Host "  stop               Stop running bench dev server and workers"
    Write-Host "  restart            Restart bench dev server`n"

    Write-Host "Workers & Scheduler:" -ForegroundColor Green
    Write-Host "  worker status      Check RQ background worker status"
    Write-Host "  worker restart     Restart background workers (short, long, default)"
    Write-Host "  scheduler status   Check scheduler status"
    Write-Host "  scheduler enable   Enable scheduler on default site"
    Write-Host "  scheduler disable  Disable scheduler on default site`n"

    Write-Host "Database & Backups:" -ForegroundColor Green
    Write-Host "  backup [site]      Take site backup (with files)"
    Write-Host "  restore [site] <file> Restore database backup into site"
    Write-Host "  export-seed [site] Export current site DB dump to seed-data/ for GitHub sync"
    Write-Host "  restore-seed [site] Restore seed-data/ snapshot into MariaDB`n"

    Write-Host "Apps & Sites:" -ForegroundColor Green
    Write-Host "  new-app <name>     Create a new custom Frappe app"
    Write-Host "  get-app <url|name> Clone and install app into bench"
    Write-Host "  install-app <app> [site] Install app on site"
    Write-Host "  uninstall-app <app> [site] Uninstall app from site"
    Write-Host "  migrate [site]     Run bench migrate on site"
    Write-Host "  new-site <name>    Create a new multi-tenant site"
    Write-Host "  console [site]     Open interactive Frappe Python console`n"

    Write-Host "Redis:" -ForegroundColor Green
    Write-Host "  redis flush        Flush Redis cache & queue"
    Write-Host "  redis info         Display Redis memory and queue stats`n"

    Write-Host "Web Management Tool:" -ForegroundColor Green
    Write-Host "  dashboard          Start/Access Web Control Center at http://localhost:8080`n"

    Write-Host "Passthrough:" -ForegroundColor Green
    Write-Host "  exec <bench cmd>   Execute any arbitrary bench command directly`n"
}

switch ($Command.ToLower()) {
    "up" {
        Write-Host "Starting Docker stack..." -ForegroundColor Cyan
        docker compose -f $ComposeFile up -d
    }
    "down" {
        Write-Host "Stopping Docker stack..." -ForegroundColor Yellow
        docker compose -f $ComposeFile down
    }
    { $_ -in "ps", "status" } {
        docker compose -f $ComposeFile ps
    }
    "bash" {
        docker compose -f $ComposeFile exec -e "TERM=xterm-256color" -it $FrappeService bash
    }
    "start" {
        $IsDaemon = $ArgsList -contains "-d"
        Write-Host "Starting Frappe Bench Dev Server (port 8000, socketio 9000)..." -ForegroundColor Cyan
        if ($IsDaemon) {
            docker compose -f $ComposeFile exec -d $FrappeService bash -c "cd /workspace/frappe-bench && honcho start socketio watch schedule worker_short worker_long worker_default web > /workspace/frappe-bench/logs/honcho.log 2>&1"
            Write-Host "Bench dev server started in background! Check logs with: .\bench.ps1 logs" -ForegroundColor Green
        } else {
            docker compose -f $ComposeFile exec -it $FrappeService bash -c "cd /workspace/frappe-bench && honcho start socketio watch schedule worker_short worker_long worker_default web"
        }
    }
    "stop" {
        Write-Host "Stopping bench dev server processes..." -ForegroundColor Yellow
        docker compose -f $ComposeFile exec $FrappeService bash -c "pkill -f honcho 2>/dev/null; pkill -f 'frappe.utils.bench_helper' 2>/dev/null; pkill -f 'node.*socketio' 2>/dev/null; true"
        Write-Host "Processes stopped." -ForegroundColor Green
    }
    "restart" {
        & $PSCommandPath stop
        Start-Sleep -Seconds 2
        & $PSCommandPath start -d
    }
    "worker" {
        $Sub = if ($ArgsList.Count -gt 0) { $ArgsList[0] } else { "status" }
        if ($Sub -eq "restart") {
            Write-Host "Restarting RQ workers..." -ForegroundColor Yellow
            docker compose -f $ComposeFile exec $FrappeService bash -c "pkill -f 'worker' 2>/dev/null; true"
            Write-Host "Workers signaled to restart." -ForegroundColor Green
        } else {
            Write-Host "Background Workers Status:" -ForegroundColor Cyan
            docker compose -f $ComposeFile exec $FrappeService bash -c "cd /workspace/frappe-bench && bench --site $DefaultSite doctor || true"
        }
    }
    "scheduler" {
        $Sub = if ($ArgsList.Count -gt 0) { $ArgsList[0] } else { "status" }
        $Site = if ($ArgsList.Count -gt 1) { $ArgsList[1] } else { $DefaultSite }
        switch ($Sub) {
            "enable" {
                docker compose -f $ComposeFile exec $FrappeService bash -c "cd /workspace/frappe-bench && bench --site $Site enable-scheduler"
            }
            "disable" {
                docker compose -f $ComposeFile exec $FrappeService bash -c "cd /workspace/frappe-bench && bench --site $Site disable-scheduler"
            }
            default {
                docker compose -f $ComposeFile exec $FrappeService bash -c "cd /workspace/frappe-bench && bench --site $Site doctor"
            }
        }
    }
    "backup" {
        $Site = if ($ArgsList.Count -gt 0) { $ArgsList[0] } else { $DefaultSite }
        Write-Host "Backing up site '$Site'..." -ForegroundColor Cyan
        docker compose -f $ComposeFile exec $FrappeService bash -c "cd /workspace/frappe-bench && bench --site $Site backup --with-files"
        Write-Host "Backup completed! Stored in frappe-bench/sites/$Site/private/backups/" -ForegroundColor Green
    }
    "export-seed" {
        $Site = if ($ArgsList.Count -gt 0) { $ArgsList[0] } else { $DefaultSite }
        Write-Host "Exporting site snapshot to seed-data/..." -ForegroundColor Cyan
        docker compose -f $ComposeFile exec $FrappeService bash -c "cd /workspace/frappe-bench && bench --site $Site backup && cp ``$(ls -t /workspace/frappe-bench/sites/$Site/private/backups/*-database.sql.gz | head -n 1) /workspace/seed-data/latest-seed.sql.gz && cp /workspace/frappe-bench/sites/$Site/site_config.json /workspace/seed-data/site_config.json"
        Write-Host "Seed snapshot saved to ./seed-data/latest-seed.sql.gz and site_config.json!" -ForegroundColor Green
    }
    "restore-seed" {
        $Site = if ($ArgsList.Count -gt 0) { $ArgsList[0] } else { $DefaultSite }
        Write-Host "Restoring seed snapshot into '$Site'..." -ForegroundColor Yellow
        docker compose -f $ComposeFile exec $FrappeService bash -c "cd /workspace/frappe-bench && bench --site $Site restore /workspace/seed-data/latest-seed.sql.gz --db-root-password 123"
        Write-Host "Restore complete!" -ForegroundColor Green
    }
    "restore" {
        if ($ArgsList.Count -lt 1) {
            Write-Host "Error: Please specify the backup file path to restore." -ForegroundColor Red
            return
        }
        $File = $ArgsList[0]
        $Site = if ($ArgsList.Count -gt 1) { $ArgsList[1] } else { $DefaultSite }
        docker compose -f $ComposeFile exec $FrappeService bash -c "cd /workspace/frappe-bench && bench --site $Site restore $File --db-root-password 123"
    }
    "new-app" {
        if ($ArgsList.Count -lt 1) {
            Write-Host "Error: App name required. Usage: .\bench.ps1 new-app <app_name>" -ForegroundColor Red
            return
        }
        $App = $ArgsList[0]
        docker compose -f $ComposeFile exec -it $FrappeService bash -c "cd /workspace/frappe-bench && bench new-app $App"
    }
    "get-app" {
        if ($ArgsList.Count -lt 1) {
            Write-Host "Error: App URL or name required." -ForegroundColor Red
            return
        }
        $Target = $ArgsList[0]
        docker compose -f $ComposeFile exec $FrappeService bash -c "cd /workspace/frappe-bench && bench get-app $Target"
    }
    "install-app" {
        if ($ArgsList.Count -lt 1) {
            Write-Host "Error: App name required." -ForegroundColor Red
            return
        }
        $App = $ArgsList[0]
        $Site = if ($ArgsList.Count -gt 1) { $ArgsList[1] } else { $DefaultSite }
        Write-Host "Installing app '$App' on site '$Site'..." -ForegroundColor Cyan
        docker compose -f $ComposeFile exec $FrappeService bash -c "cd /workspace/frappe-bench && bench --site $Site install-app $App"
    }
    "uninstall-app" {
        if ($ArgsList.Count -lt 1) {
            Write-Host "Error: App name required." -ForegroundColor Red
            return
        }
        $App = $ArgsList[0]
        $Site = if ($ArgsList.Count -gt 1) { $ArgsList[1] } else { $DefaultSite }
        Write-Host "Uninstalling app '$App' from site '$Site'..." -ForegroundColor Yellow
        docker compose -f $ComposeFile exec $FrappeService bash -c "cd /workspace/frappe-bench && bench --site $Site uninstall-app $App"
    }
    "migrate" {
        $Site = if ($ArgsList.Count -gt 0) { $ArgsList[0] } else { $DefaultSite }
        docker compose -f $ComposeFile exec $FrappeService bash -c "cd /workspace/frappe-bench && bench --site $Site migrate"
    }
    "console" {
        $Site = if ($ArgsList.Count -gt 0) { $ArgsList[0] } else { $DefaultSite }
        docker compose -f $ComposeFile exec -it $FrappeService bash -c "cd /workspace/frappe-bench && bench --site $Site console"
    }
    "redis" {
        $Sub = if ($ArgsList.Count -gt 0) { $ArgsList[0] } else { "info" }
        switch ($Sub) {
            "flush" {
                Write-Host "Flushing Redis Cache and Queue..." -ForegroundColor Yellow
                docker compose -f $ComposeFile exec redis-cache redis-cli flushall
                docker compose -f $ComposeFile exec redis-queue redis-cli flushall
                Write-Host "Redis flushed successfully." -ForegroundColor Green
            }
            default {
                Write-Host "Redis Cache Stats:" -ForegroundColor Cyan
                docker compose -f $ComposeFile exec redis-cache redis-cli info memory
                Write-Host "`nRedis Queue Stats:" -ForegroundColor Cyan
                docker compose -f $ComposeFile exec redis-queue redis-cli info memory
            }
        }
    }
    "logs" {
        docker compose -f $ComposeFile exec $FrappeService tail -n 50 -f /workspace/frappe-bench/logs/honcho.log
    }
    "dashboard" {
        Write-Host "Launching Web Control Center on http://localhost:8080 ..." -ForegroundColor Cyan
        docker compose -f $ComposeFile exec -d $FrappeService bash -c "python3 /workspace/dashboard/app.py > /workspace/dashboard/dashboard.log 2>&1"
        Start-Process "http://localhost:8080"
    }
    "exec" {
        $BenchCmd = $ArgsList -join " "
        docker compose -f $ComposeFile exec -it $FrappeService bash -c "cd /workspace/frappe-bench && bench $BenchCmd"
    }
    default {
        Show-Help
    }
}
