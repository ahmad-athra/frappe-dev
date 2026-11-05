---
name: frappe-bugfix
description: >-
  Disciplined bug workflow for Frappe/ERPNext: reproduce, write a failing regression test, find root cause
  with evidence, apply the minimal fix, and record it. Use when the user reports an error, wrong behaviour,
  traceback, or regression, including failing tests.
---

# Bug Fix Workflow

Principle: **no fix without a reproduction; no merge without a regression test.**

## 1. Capture
Collect: expected vs actual, steps, site/user/role, doc names, version/commit, traceback or Error Log entry.
Missing repro details that block you → ask once (`ask_question`). Never print secrets.

## 2. Reproduce (read-only first)
- Logs: `.\bench.ps1 logs` (or read `frappe-bench/logs/*`), Error Log DocType, browser console.
- Read-only data inspection through `frappe.db.get_value`/`get_all` in `bench execute` — **no raw SQL writes** (ai-rules §4).
- Reproduce on the dev site only through safe reads; otherwise reproduce in a test.
- Cannot reproduce after reasonable effort → report findings and ask; don't guess-fix.

## 3. Failing test (Red)
Write the smallest test that fails for the *reported reason* (`IntegrationTestCase`, own fixtures, on a test site with
`allow_tests`). Run it and **show it failing**. Name it for the bug: `test_<behaviour>_regression`.

## 4. Root cause
Use five-whys / bisect (`git log -S`, `git bisect` on app repo). Distinguish **cause** from **symptom**; confirm with
evidence (trace, query, test). Check whether upstream Frappe/ERPNext behaviour is the cause — if so, work around
via hooks, never patch core (TR-01), and note the upstream issue.
Also check: are other call sites affected by the same defect? (`rg` the pattern.)

## 5. Fix (Green)
Minimal change at the root (AI-10). No unrelated refactors. Data already corrupted by the bug ⇒ propose an idempotent
patch (TR-100..103) and **ask** before running it (backup first).
Fix is a security issue? Treat privately: no details in commit/spec text beyond what's necessary, flag to user.

## 6. Verify
Regression test green; run the module's full tests + lint (`frappe-verify`). Confirm original repro no longer occurs.

## 7. Record
Add to the owning spec: §16 (resolved known-issue) and §17 changelog (`fix:` entry with root cause in one line).
Commit message (when asked): `fix(<scope>): <what>` + body: cause, fix, test.

## Hand-off
Severity S/M/L? → `frappe-review` → `frappe-ship`. If two fix attempts fail: stop (AI-53) with a hypothesis table.

