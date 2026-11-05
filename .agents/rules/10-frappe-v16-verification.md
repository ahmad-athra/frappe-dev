---
trigger: model_decision
description: Apply when writing, modifying or reviewing any Frappe/ERPNext Python, JS, DocType JSON, hooks, patches or tests in enterprise_hub.
---

# Frappe v16 — Verify, Don't Recall

Models frequently hallucinate Frappe APIs. Extends AI-03/AI-04.

1. **Grep before use.** Before calling any `frappe.*`/`erpnext.*` function, hook key, or DocType field:
   `rg -n "def <name>" frappe-bench/apps/frappe/frappe frappe-bench/apps/erpnext/erpnext` and open the
   DocType `*.json` for fieldnames. Cite the file in the spec/PR if non-obvious.
2. **Prefer copying a pattern from upstream** (find a similar ERPNext feature) over inventing structure.
3. **Where things go** (TR-20): thin `api/`, `events/`, controllers → `services/` for logic → `tasks/` for jobs.
4. **Schema change checklist:** DocType JSON `modified` bumped (AI-47) → `migrate` → test site migrate → patch if existing data is affected (TR-100..104).
5. **Hook changes** (`hooks.py`) require a dev-server restart; say so.
6. **Windows host quirks:** paths in docker commands are Linux paths (`/workspace/...`); use `docker compose exec -T` (AI-30); the PowerShell shell has no `&&` in older versions — chain with `;` or separate calls.
7. **Search large trees with `rg`** and exclude `node_modules`; recursive `Get-ChildItem` over `frappe-bench` is extremely slow.
8. **Never print secrets** from `.env` / `site_config.json`.

