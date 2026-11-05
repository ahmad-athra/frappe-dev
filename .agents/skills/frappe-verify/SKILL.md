---
name: frappe-verify
description: >-
  Runs and reports lint, tests, migration and smoke checks for changes in the enterprise_hub Frappe app
  using the dockerised bench and a safe test site. Use after implementing or fixing anything and before
  review or claiming work is done.
---

# Verification

Never say "tested/working" for something not executed (AI-52). Report exact commands and outcomes.

## 1. Pick a safe site (AI-51)
```powershell
docker compose exec -T frappe bash -c "ls /workspace/frappe-bench/sites"
```
Use a site with `allow_tests: true` that is **not** `development.localhost`. If none exists, ask the user before
creating one (`bench new-site` is a new-state operation) or before running tests on the dev site.

## 2. Schema sync (if DocType/Custom Field/patch touched)
`.\bench.ps1 migrate` for dev, and `bench --site <test-site> migrate` for the test site. Confirm no patch errors.

## 3. Lint & format (AI-50)
Run in the app dir inside the container (or via pre-commit if installed):
```powershell
docker compose exec -T frappe bash -c "cd /workspace/frappe-bench/apps/enterprise_hub && ruff check . && ruff format --check ."
```
JS/Vue: `eslint` / `prettier --check` through the repo's pre-commit config. Missing tool ⇒ report, don't skip silently.

## 4. Tests (TR-132)
```powershell
docker compose exec -T frappe bash -c "cd /workspace/frappe-bench && bench --site <test-site> run-tests --app enterprise_hub --module <dotted.module>"
```
Run touched modules first, then the whole app. Flaky = failure until understood.

## 5. Smoke checks (as applicable)
- API: `GET /api/method/ping`; hit new endpoints with an allowed and a denied role.
- UI: open the Desk form/list; check browser console for errors (use `/browser` skill capabilities if available).
- Background jobs: `.\bench.ps1 worker status`; check Error Log for new entries.
- Query-heavy changes: `EXPLAIN` the query (TR-47).

## 6. Acceptance traceability
Fill a table in the report:

| AC | Test / check | Result |
| :-- | :-- | :-- |

## 7. Result
Pass → `frappe-review`. Fail → fix and re-run; **second identical failure → stop and ask** (AI-53).
Report unrun items explicitly (e.g. "UI not exercised").

