---
trigger: always_on
---

# Git Workflow — one feature, one branch, one commit set, one MR

> **Authorization:** the user has explicitly and permanently asked for this workflow. For the steps below, that
> counts as "asked" under AI-60 and replaces the per-commit Gate 3 prompt. Everything **outside** this list still
> needs an explicit request (`ai-rules.md §4`).

## Rules
1. **Own branch per unit of work** (feature, bug, chore, or agent/rules config). Never commit directly to `main`.
   Name: `<type>/<F-XXX>-<kebab-slug>` (e.g. `feat/F-007-delivery-agents`, `fix/F-005-activity-title`, `chore/agents-config`).
2. **Sync before branching:** `git fetch origin` → `git switch main` → `git pull --ff-only origin main` → `git switch -c <branch>`.
   If main is not fast-forwardable or the tree has unrelated changes you'd carry over, stop and ask.
3. **Sync again before pushing:** `git fetch origin`; if `origin/main` moved, `git rebase origin/main` (own unpushed branch only)
   or merge it if the branch is already shared; resolve conflicts, re-run `frappe-verify`.
4. **Commit only that unit's files** by explicit path (never `git add -A` / `.`), Conventional Commits (AI-60, TR-143).
   Unrelated dirty files (site configs, `touched_tables.json`, seed data, `.env`) stay out — mention them in the report.
   Secrets / protected paths (`ai-rules.md §3`) are never staged.
5. **Push the branch** (`git push -u origin <branch>`) after verification + review pass. Never `--force` (use
   `--force-with-lease` only after an explicit "yes").
6. **Open the MR (GitHub Pull Request) into `main`.** `gh` is not installed here, so give the user the compare URL
   `https://github.com/ahmad-athra/frappe-dev/compare/main...<branch>?expand=1` plus a ready title/body
   (summary, spec link, AC → test table, verification evidence, migrate/restart notes, rollback). If `gh` becomes
   available, use `gh pr create --base main`.
7. **Never merge your own MR** or push to `main`. The user reviews and accepts.
8. **After the user accepts the MR** (they say so): `git fetch origin --prune` → `git switch main` →
   `git pull --ff-only origin main` → delete the merged local branch (`git branch -d <branch>`, safe delete only).
9. **Two repos (AI-61):** apply this per repo. Stack repo = `ahmad-athra/frappe-dev` (root: `context/`, `.agents/`,
   `bench*`, docker). App repo = `frappe-bench/apps/enterprise_hub` (`git@github.com:ahmad-athra/enterprise_hub.git`,
   base branch `version-16`, not `main`). A feature touching both gets one branch + one MR in each, cross-linked.
10. **Atomic history:** separate commits for separate concerns (e.g. tests, feature, docs); each one builds and passes.

## Quick sequence
```powershell
git fetch origin; git switch main; git pull --ff-only origin main
git switch -c feat/F-XXX-slug
# ...work, verify, review...
git add <explicit paths>; git commit -m "feat(scope): summary"
git fetch origin; git rebase origin/main
git push -u origin feat/F-XXX-slug      # then hand the user the compare URL / MR text
```
