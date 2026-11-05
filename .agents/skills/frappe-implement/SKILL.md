---
name: frappe-implement
description: >-
  Implements an approved Frappe/ERPNext spec or design in the enterprise_hub app using test-first,
  small vertical increments that follow technical-rules.md. Use after design for features, requirements
  and chores; bugs use frappe-bugfix which then hands off here.
---

# Implementation

Work only in `frappe-bench/apps/enterprise_hub/` (TR-01). Commands run in the container (AI-30).

## Command prefix
```powershell
docker compose exec -T frappe bash -c "cd /workspace/frappe-bench && bench --site <site> <cmd>"
```
Always pass `--site` (AI-33). Dev server is assumed running (AI-31).

## Loop (repeat per acceptance criterion / vertical slice)

1. **Red** — write the failing test from the AC (`IntegrationTestCase` for DB, `UnitTestCase` for pure logic; TR-130).
   Tests create their own fixtures (TR-133). Add allowed *and* denied permission tests for each API (TR-131).
2. **Green** — minimal code to pass, in this order of layers:
   DocType JSON/controller → services → events/api/tasks → `hooks.py` → client JS → patches.
3. **Refactor** — remove duplication; keep controllers thin; constants in `constants.py` (TR-22).
4. **Run** the touched test module (see `frappe-verify`). Fix before moving on.
5. **Checkpoint** — after each slice: `git diff --stat` in the correct repo; ensure only in-scope files changed (AI-10).

## Frappe-specific checklist (tick while coding)
- Whitelisted: `methods=[...]`, typed args, explicit permission check (TR-50..52)
- Queries: explicit `fields`, no N+1, parameterized SQL, v16 dict-syntax functions (TR-40..45)
- No `frappe.db.commit()` in handlers (AI-45); `enqueue` with names not docs, idempotent (TR-62)
- Errors: `frappe.throw(_(...))` for users, `frappe.log_error` + re-raise for unexpected (TR-111..113)
- Strings translatable `_()` / `__()` (AI-48); no hex/px literals (AI-71)
- `on_submit` ⇒ symmetric `on_cancel` (TR-95); ledgers only via vouchers (TR-90)
- Docstrings on public functions (TR-144); preserve unrelated comments (AI-13)
- Desk JS via `doctype_js` in hooks, not Client Scripts (TR-15); no Server Scripts (TR-16)

## Schema changes
Create DocTypes in Desk with developer mode so JSON is exported (TR-30); if JSON is hand-edited bump `modified`.
Then `.\bench.ps1 migrate`; add idempotent patch + `patches.txt` entry when existing data is affected.
Hook changes ⇒ tell the user a dev-server restart is needed.

## Stop conditions
Spec/design contradicted by reality · needs new dependency/app/dir (AI-11/12) · core change required · same fix failed twice (AI-53).
Report and ask; do not improvise.

## Done when
All AC tests green, no placeholder logic (AI-41), spec §6–§8 matches the actual code. Hand off to `frappe-verify`.

