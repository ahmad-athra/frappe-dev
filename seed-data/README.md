# Seed Data & Site Snapshots

This directory holds database backups (`.sql.gz`) and bench state seeds to easily reproduce your environment across machines (e.g. Work PC, Home PC, CI/CD).

## Sync Workflow
- To export your current active database state:
  ```powershell
  .\bench.ps1 export-seed
  ```
- To commit and push state to your repo:
  ```powershell
  git add seed-data/
  git commit -m "chore(db): update site seed snapshot"
  git push
  ```
- On your other machine (Home PC):
  ```powershell
  git pull
  .\bench.ps1 restore-seed
  ```
