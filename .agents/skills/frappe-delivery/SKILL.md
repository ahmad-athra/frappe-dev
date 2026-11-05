---
name: frappe-delivery
description: >-
  Entry point and orchestrator for ANY development request on this Frappe/ERPNext repo — a new feature,
  bug report, requirement, idea, change request, refactor or chore. Use first, whenever the user describes
  something to build, fix, or change. Routes through triage, spec, design, implementation, verification,
  review and ship using the phase skills.
---

# Frappe Delivery Orchestrator

Takes a raw request from zero to done. Governance lives in `context/` (read it first — AI-01); this skill
sequences the phase skills and enforces gates from `.agents/rules/00-delivery-gates.md`.

## Flow

```mermaid
flowchart TD
    R["Request"] --> T["frappe-triage"]
    T -->|"idea / requirement / feature"| S["frappe-spec"]
    T -->|bug| B["frappe-bugfix"]
    T -->|"chore / trivial"| I
    S --> G1{"Gate 1: spec approved?"}
    G1 -->|no| S
    G1 -->|yes| D["frappe-design"]
    B --> D2["frappe-design (light)"]
    D --> I["frappe-implement"]
    D2 --> I
    I --> V["frappe-verify"]
    V -->|fail twice| STOP["Stop and ask (AI-53)"]
    V -->|pass| RV["frappe-review"]
    RV -->|findings| I
    RV -->|clean| SH["frappe-ship"]
```

## Procedure

1. **Create a task checklist** (one item per phase) and keep it updated.
2. Read `context/` per its README reading order (skip files already read this session).
3. Invoke `frappe-triage`; follow its routing. Read each phase skill's `SKILL.md` when you reach it.
4. At each gate, **stop and present** the artifact (spec / design summary / diff summary) and wait.
5. Delegate where it helps (see `.agents/agents/README.md`): independent review and QA roles give fresher
   eyes than self-review. Parallelize only read-only work (research, review); one engineer writes code.
6. Finish only when the Definition of Done in `00-delivery-gates.md` is satisfied.

## Autonomy levels

| Request signal | Mode |
| :-- | :-- |
| "just fix X" + trivial, clear cause | Skip spec; still reproduce → test → fix → verify |
| Normal feature/bug | Full flow, gates 1 and 3 |
| Touches schema, money/stock ledgers, permissions, guest access | Full flow + gate 2 + security reviewer |
| Vague idea ("we should maybe…") | Triage + spec only; stop at Gate 1 |

## Final report template
```
Outcome: <one line>
Changed: <files/links>   Spec: <link + status>
Verified: <exact commands + results>   Not verified: <list>
You must: <migrate / restart / approve / push>
Risks & follow-ups: <list>
```

