---
name: frappe-ship
description: >-
  Closes out a Frappe/ERPNext change: updates spec status, changelog and feature registry, prepares
  Conventional Commit messages for the correct repo, and gives deploy/rollback notes. Use after review passes,
  when the user asks to commit, finish, or release work.
---

# Ship

## 1. Documentation sync (AI-62)
- Spec: status → `🟢 Implemented` only if code + tests + spec agree (otherwise `⚠️ Implemented (debt)` and list debt in §16).
- Spec §17 changelog row (date, version, change). Fix any §6–§8 drift.
- `context/features/README.md` registry row + dependency graph if relations changed.
- `context/project-overview.md` §4/§5 if a feature/endpoint was added (it is not a protected file).
- Never edit `ai-rules.md` / `technical-rules.md` unless explicitly asked; propose rule changes in the report instead.

## 2. Repo split (AI-61)
| Changed | Repo | Path |
| :-- | :-- | :-- |
| App code, hooks, patches, DocTypes | `enterprise_hub` | `frappe-bench/apps/enterprise_hub` |
| Docs (`context/`), `.agents/`, bench/CLI/Docker | stack repo | repo root |
Inspect each with `git -C <path> status --short` and stage **explicit paths** (no `git add -A`). Check no secrets,
`.env`, `site_config.json` or seed dumps are staged (AI protected paths).

## 3. Branch, commit, push, MR (follow `.agents/rules/05-git-workflow.md` — standing user authorization)
Branch from freshly pulled `main`, commit only this change's files, push the branch, give the user the MR link/text.
Never merge or push `main`; after the user accepts the MR, sync local `main` and delete the branch.
Conventional Commits, one logical change per commit:
```
<type>(<scope>): <imperative summary ≤72 chars>

<why; what changed; spec F-0xx; AC ids>
Refs: F-0xx
```
Types: feat, fix, refactor, perf, test, docs, chore, ci. Breaking: `!` + `BREAKING CHANGE:` footer.
Never force-push. Anything beyond the git-workflow rule (merge, `main`, history rewrite) needs an explicit "yes".

## 4. Release notes for the user
- **Run:** `migrate`, build assets, restart (if `hooks.py` changed), `export-seed` (optional, only on request).
- **Deploy/rollback:** backup first (`.\bench.ps1 backup`); rollback = revert commit + restore backup if a patch ran (restore needs explicit user "yes").
- **Follow-ups:** debt, deferred items, new ideas → draft specs or spec §16 rows.

## 5. Final report
Use the template in `frappe-delivery`.

