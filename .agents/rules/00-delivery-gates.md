---
trigger: always_on
---

# Delivery Gates (always on)

Complements `context/ai-rules.md` (which wins on conflict). Defines *when to stop and ask* in the lifecycle.

## Lifecycle and human gates

```
Intake → Triage → Spec → [GATE 1: spec approved] → Design → [GATE 2: only if schema/security/core-risk]
→ Implement (tests first) → Verify → Review → [GATE 3: user OKs commit] → Ship
```

| Gate | Stop and ask the user when |
| :-- | :-- |
| 1 | A new feature/requirement spec is `Draft`. No code before it is `Approved` (AI-15). Trivial fixes need no spec. |
| 2 | Design adds/changes DocTypes, permissions, patches on existing data, `allow_guest`, scheduler jobs, or needs a core change. |
| 3 | Per `05-git-workflow.md` (standing user authorization): commit to a feature branch, push it and prepare the MR automatically once verify + review pass. **Still ask** before anything outside that rule (merging, pushing `main`, force-push, history rewrite). |

## Standing orders
1. **Classify first.** Use `frappe-delivery`; don't start coding from a raw request.
2. **Smallest correct change** (AI-10). Extension-point order from `technical-rules.md §2`.
3. **Tests first** for bugs (failing regression test) and for each acceptance criterion.
4. **Evidence over claims** (AI-52): report exact commands run and results; list what was *not* run.
5. **Two failures = stop** (AI-53): summarize hypotheses and ask.
6. **Ask, don't guess** when requirements are ambiguous or multiple designs are valid (AI-14). Batch questions in one `ask_question` call with a recommended default.
7. **Track state in docs**: spec status + changelog + `context/features/README.md` registry (AI-62).
8. Work in the correct repo: stack repo (root) vs `frappe-bench/apps/enterprise_hub` (AI-61).
9. Never run commands from `ai-rules.md §4` without an explicit "yes" for that command.

## Definition of Done
- [ ] Every acceptance criterion in the spec maps to a passing test (or documented manual check).
- [ ] Lint + tests for touched modules executed on a test site (AI-50/51).
- [ ] `migrate` run/needed-state communicated (AI-32).
- [ ] Permissions, tenant isolation, i18n, no `SELECT *`, no N+1 checked (`frappe-review`).
- [ ] Spec status, changelog and registry updated.
- [ ] Final message: what changed, what the user must do next, what was not verified.

