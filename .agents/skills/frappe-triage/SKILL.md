---
name: frappe-triage
description: >-
  Classifies an incoming request (idea, requirement, feature, bug, chore, question), finds the affected
  existing feature/spec, assesses size and risk, and decides the route and which gates apply. Use at the
  start of any development request before writing a spec or code.
---

# Triage

## 1. Classify

| Type | Signals | Route |
| :-- | :-- | :-- |
| Idea | "what if", no acceptance criteria | `frappe-spec` (discovery mode), stop at Gate 1 |
| Requirement | business rule / compliance / stakeholder need | `frappe-spec` |
| Feature | new capability | `frappe-spec` → design → implement |
| Bug | wrong/unexpected behaviour, error, regression | `frappe-bugfix` |
| Chore | deps, CI, docs, refactor (needs approval AI-10/11) | implement directly with approval |
| Question | no change wanted | answer from code + `context/`; no workflow |

## 2. Locate
- Search `context/features/README.md` + specs for the owning feature (AI-02). Read its spec.
- `rg` the codebase for the touched DocTypes/modules. Note drift between spec and code (AI-05).
- Decide: **new feature ID** (next sequential, never reused) or **amend existing spec**.

## 3. Size & risk (T-shirt + flags)
Size: **S** (≤1 file, no schema) · **M** (one module, maybe a DocType) · **L** (multi-module / integration).
Risk flags — each forces Gate 2 and security review: schema change on existing data · ledger/stock/payment
impact (TR-90..95) · permission or `allow_guest` change · new scheduler/background job · core-change temptation ·
destructive command (ai-rules §4) · new dependency.
Large (L) requests: propose slicing into vertical increments, each independently shippable.

## 4. Clarify
List unknowns. If any blocks the spec, ask in **one** `ask_question` call (≤4 questions, recommended option first).
Do not ask what the code or `context/` already answers.

## 5. Output (post to user, ≤15 lines)
```
Type: … | Size: … | Risk flags: … | Owning feature: F-0xx / NEW
Route: <skills in order> | Gates: <1/2/3>
Assumptions: …  Open questions: …
```
Then continue to the routed skill unless questions are blocking.

