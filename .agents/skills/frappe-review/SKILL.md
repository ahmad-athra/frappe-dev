---
name: frappe-review
description: >-
  Structured pre-merge code review of changes in the Frappe/ERPNext enterprise_hub app covering spec
  conformance, security, permissions, multi-tenancy, performance, ERPNext integrity, tests and style,
  with severity-ranked findings. Use after verification and before shipping, or when asked to review a diff or PR.
---

# Review

Review the diff (`git diff` in the app repo, plus root repo) against the spec and `context/technical-rules.md`.
Prefer an **independent reviewer** sub-agent (`.agents/agents/code-reviewer.md`, and `security-reviewer.md` for risk-flagged work).

## Pass order
1. **Spec conformance** — every FR/AC implemented; nothing extra (scope creep AI-10); spec matches code.
2. **Correctness** — edge cases (empty, duplicate, back-dated, cancelled/amended docs, multi-company, timezone), error paths, idempotency.
3. **Security** — permission checks on every entry point, typed args, `methods=[...]`, no `allow_guest` without approval,
   no SQL injection (parameterized), output escaping, no secrets, `ignore_*` flags justified (AI-46, TR-50..53, TR-81..84).
4. **Tenancy & company scoping** — no hardcoded site/company/user; filters by company (TR-03, TR-80, TR-85).
5. **Performance** — N+1, `SELECT *`, missing indexes, unbounded lists, work in request that should be enqueued, cache keys/TTL/invalidation (TR-40..47, 60..69).
6. **ERPNext integrity** — ledgers via vouchers, submit/cancel symmetry, controller extension not copy (TR-90..97).
7. **Data safety** — patches idempotent/batched/append-only; destructive operations absent; rollback viable (TR-100..104).
8. **Tests** — meaningful assertions, negative/permission cases, no dependency on seed data, deterministic (TR-130..133).
9. **Maintainability & style** — thin controllers, constants, naming, docstrings, i18n, no dead code, ruff/prettier clean.
10. **Docs** — spec status/changelog/registry updated (AI-62).

## Findings format
| # | Severity | File:line | Finding | Suggested fix |
| :-- | :-- | :-- | :-- | :-- |
Severities: **Blocker** (security, data loss, spec violation, broken tests) · **Major** (perf, missing tests, rule violation) ·
**Minor** (style, naming) · **Nit**. Cite rule IDs. Praise nothing generic; note risky-but-OK decisions.

## Outcome
Blockers/Majors ⇒ back to `frappe-implement`, then re-verify. Clean or Minor-only ⇒ proceed to `frappe-ship`.
Review is advisory evidence, never a substitute for running tests.

