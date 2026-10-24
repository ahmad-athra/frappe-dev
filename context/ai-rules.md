# 🛡️ AI Rules — Behavioural Guardrails

> These rules are **mandatory** for any AI agent operating in this repository.
> If a rule conflicts with a user instruction, **stop and ask** — do not silently pick one.
> Rule IDs (e.g. `AI-03`) can be cited in reviews and commit messages.

---

## 1. Context First

| ID | Rule |
| :-- | :--- |
| AI-01 | Before any task, read `context/ai-rules.md`, `context/project-overview.md`, and `context/technical-rules.md`. |
| AI-02 | Before touching an existing feature, read its `context/features/F-XXX-*/spec.md`. |
| AI-03 | Before using any Frappe/ERPNext API, **verify it exists in the local source** (`frappe-bench/apps/frappe`, `frappe-bench/apps/erpnext`) or official v16 docs. Never invent methods, hooks, fields, or DocType names. |
| AI-04 | Before referencing a field on an ERPNext DocType, open its `*.json` definition and confirm the `fieldname`. |
| AI-05 | Treat the `context/` docs as guidance, not ground truth: if code and docs disagree, trust the code, then report the drift. |

## 2. Scope Discipline

| ID | Rule |
| :-- | :--- |
| AI-10 | Do **only** what was asked. No drive-by refactors, renames, reformatting, or "improvements" outside scope. |
| AI-11 | Do not add new dependencies (pip, npm, apt, Docker images) without explicit approval. |
| AI-12 | Do not create new apps, modules, or top-level directories without approval. |
| AI-13 | Preserve existing comments and docstrings unrelated to the change. |
| AI-14 | If a request is ambiguous, has multiple valid designs, or affects data/schema — **ask before implementing**. |
| AI-15 | New feature ⇒ create a spec from `context/features/_template/spec.md` with status `Draft` and get approval before writing code (skip only for trivial fixes the user explicitly waives). |

## 3. Protected Paths (Never Modify)

| Path | Reason |
| :--- | :--- |
| `frappe-bench/apps/frappe/**` | Core framework — upgrade safety |
| `frappe-bench/apps/erpnext/**` | Upstream ERP — upgrade safety |
| `frappe-bench/env/**`, `frappe-bench/config/**` | Generated virtualenv / bench config |
| `frappe-bench/sites/assets/**` | Build output |
| `frappe-bench/sites/*/private/**`, `frappe-bench/sites/*/public/files/**` | Tenant data & backups |
| `frappe-bench/logs/**`, `dashboard/*.log` | Runtime logs |
| `**/node_modules/**`, `**/__pycache__/**` | Generated |
| `seed-data/latest-seed.sql.gz` | Only changed via `export-seed` on user request |
| `.env`, `**/site_config.json`, `common_site_config.json` | Secrets & runtime config — change only on explicit request |
| `context/ai-rules.md`, `context/technical-rules.md` | Governance docs — change only on explicit request |

> [!IMPORTANT]
> All custom logic lives in `frappe-bench/apps/enterprise_hub/`. If a requirement seems to need a core
> change, stop and propose a hook-based alternative (see `technical-rules.md §2`).

## 4. Dangerous Operations (Require Explicit Confirmation)

Never run these without the user typing an explicit "yes" for **that specific command**:

| Category | Commands |
| :--- | :--- |
| Data loss | `bench restore`, `.\bench.ps1 restore`, `.\bench.ps1 restore-seed`, `bench drop-site`, `bench reinstall`, `bench --site X uninstall-app` (drops tables) |
| Cache/queue wipe | `.\bench.ps1 redis flush`, `redis-cli flushall` (also drops queued jobs) |
| Infra | `docker compose down -v`, `docker volume rm`, `docker system prune` |
| Git history | `git push --force`, `git reset --hard`, `git clean -fd`, rebasing shared branches |
| Process control | Killing the running dev server (`.\bench.ps1 stop`, `pkill`) when the user has it running |
| Raw SQL writes | Any `DELETE`/`UPDATE`/`DROP`/`ALTER` executed directly against MariaDB |

## 5. Execution Environment

| ID | Rule |
| :-- | :--- |
| AI-30 | Host is **Windows / PowerShell**. Bench and Python commands run **inside the container**. Never run `bench` or the app's Python on the host. Agents have no TTY, so prefer `docker compose exec -T frappe bash -c "cd /workspace/frappe-bench && bench --site <site> <cmd>"` over `.\bench.ps1 exec/console/bash` (which use `-it`). Non-interactive `bench.ps1` commands (`migrate`, `backup`, `ps`) are fine. |
| AI-31 | Assume the dev server is **already running** (`bench start`). Do not start a second instance; code changes hot-reload. Restart only when required (e.g. `hooks.py` changes, new whitelisted module) and tell the user. |
| AI-32 | After DocType / Custom Field / patch changes, run `.\bench.ps1 migrate` (or instruct the user to). |
| AI-33 | Always pass `--site` explicitly; never rely on implicit default site in scripts or code. |
| AI-34 | Use non-interactive flags; never launch interactive prompts (`console`, `bash -it`) from automation. |

## 6. Code Generation Rules

| ID | Rule |
| :-- | :--- |
| AI-40 | Follow every rule in `technical-rules.md`. Cite the rule ID when you deviate and explain why. |
| AI-41 | No placeholder logic (`pass`, `TODO`, fake data) in delivered code unless explicitly agreed. |
| AI-42 | No hardcoded secrets, passwords, hostnames, site names, ports, colours, or pixel values. |
| AI-43 | Every new whitelisted method must declare permissions, HTTP methods, and typed arguments. Never use `allow_guest=True` without approval. |
| AI-44 | Never swallow exceptions (`except: pass`). Log with `frappe.log_error` and re-raise or `frappe.throw` a sanitised message. |
| AI-45 | Never call `frappe.db.commit()` inside request handlers or document hooks. |
| AI-46 | Never use `ignore_permissions=True` / `ignore_validate=True` / `ignore_mandatory=True` without a code comment justifying it. |
| AI-47 | When hand-editing a DocType `.json`, bump its `"modified"` timestamp or `migrate` will not sync it. Prefer editing via Desk (developer mode) and exporting. |
| AI-48 | All user-facing strings wrapped for translation: `_()` (Python), `__()` (JS). |
| AI-49 | Add or update tests for every behavioural change. |

## 7. Testing & Verification

| ID | Rule |
| :-- | :--- |
| AI-50 | Run lint (`ruff`, `eslint`/`prettier` via pre-commit) and tests for the touched module before declaring done. |
| AI-51 | Tests must **not** run against `development.localhost` without confirmation — they create/delete records. Prefer a dedicated test site (`allow_tests: true`). |
| AI-52 | Never claim something is "tested", "verified", or "working" unless you actually executed it. State clearly what was and wasn't run. |
| AI-53 | If the same fix fails twice, **stop**, summarise findings, and ask — don't loop. |

## 8. Git & Documentation

| ID | Rule |
| :-- | :--- |
| AI-60 | Do not commit or push unless asked. When asked, use Conventional Commits (`feat:`, `fix:`, `chore:`, `refactor:`, `docs:`, `test:`). |
| AI-61 | Remember the two-repo layout: stack repo (root) vs. `frappe-bench/apps/enterprise_hub` (own repo). Commit in the correct one. |
| AI-62 | After implementing a feature: update its `spec.md` (status, changelog) and the registry in `context/features/README.md`. |
| AI-63 | Documentation uses Markdown + Mermaid, Notion-exportable, no HTML in diagram labels. |

## 9. Design & UI

| ID | Rule |
| :-- | :--- |
| AI-70 | Desk UI: use native Frappe form/list APIs (`frappe.ui.form.on`, `frappe.ui.Dialog`). Standalone Vue SPAs: use **PrimeVue** components. Never hand-roll a component that the SDK provides. |
| AI-71 | No inline styles or hardcoded hex/px values — use CSS variables / theme tokens so tenants can be white-labelled. |
| AI-72 | If a design (e.g. Figma) uses non-standard tokens or components missing from the SDK, **stop and notify** with a standardised proposal before coding. |
| AI-73 | Every interactive element must have ARIA attributes and meet WCAG AA contrast. |

## 10. Communication

- Be concise. Lead with what changed and what the user must do next (e.g. "run migrate").
- Surface risks (security, data loss, upgrade breakage) proactively, even if not asked.
- Link files with clickable paths. Don't paste secrets from config files into chat or docs.
