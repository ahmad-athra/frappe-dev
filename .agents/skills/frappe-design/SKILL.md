---
name: frappe-design
description: >-
  Produces the technical design for an approved Frappe/ERPNext spec or a bug fix — chooses extension points,
  data model, permissions, jobs, caching, migration plan and test strategy, verified against local source.
  Use after the spec is approved and before writing code; includes a light mode for bugs.
---

# Technical Design

Design goes **into the spec** (§5–§13), not a separate doc. Light mode (bugs, size S): write a 5-line design note in
the spec's §16/§17 or in the final report.

## Steps

1. **Extension point** — walk the decision tree in `technical-rules.md §2`. State the chosen point and why
   each earlier option was rejected. Core change needed? Stop; propose hook-based alternative (see ai-rules §3).
2. **Verify every API** you plan to use exists in local v16 source (AI-03/04). Record file paths in the spec.
   Find an upstream precedent to mirror.
3. **Data model** — DocTypes (naming, submittable?, child vs link, TR-30..37), indexes, Custom Fields via
   `enterprise_hub/<module>/custom/` or fixtures, settings toggles in `Enterprise Hub Settings` (TR-96).
4. **Layering** — thin api/events/controllers → `services/` → repositories (queries) (TR-20). List new files.
5. **Security** (STRIDE-lite, each answered in §9):
   Spoofing/auth (who may call) · Tampering (validate typed args, submit/cancel integrity) · Info disclosure
   (permission-aware reads, no metadata leakage) · DoS (rate limit, pagination, job queue choice) ·
   Elevation (no unjustified `ignore_permissions`, role matrix) · Multi-tenant/multi-company isolation (TR-80, TR-85).
6. **Performance & concurrency** — data volume estimate, indexes + `EXPLAIN` plan for heavy queries (TR-47),
   job queue/timeouts/idempotency (TR-60..62), cache key+TTL+invalidation (TR-65..67), locks (TR-69..71).
7. **ERPNext integrity** — ledgers only via vouchers (TR-90), symmetric `on_cancel` (TR-95), Repost Item Valuation (TR-93).
8. **Migration & rollback** — patches (idempotent, batched, pre/post model sync); how to undo; backup need.
9. **Test strategy** — map each AC to unit/integration/permission/manual test and file path (TR-130..133).
10. **Observability** — logger fields, Error Log titles, health impact (§13).
11. **Alternatives considered** — at least one rejected alternative with trade-off. For decisions with long-term
    consequences add an ADR-style paragraph in §16.

## Gate 2 (if risk flags from triage)
Summarize design in ≤15 lines (extension point, schema, permissions, migration, rollback) and ask for approval before coding.
Otherwise proceed and mention the design in the next update.

## Output checklist
- [ ] Spec §5–§13 filled, APIs verified with paths
- [ ] AC → test mapping complete
- [ ] Rollback stated
