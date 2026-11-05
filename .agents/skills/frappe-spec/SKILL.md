---
name: frappe-spec
description: >-
  Turns an idea, requirement or feature request into a reviewable spec using the repo template
  (context/features/_template/spec.md) with user stories, testable acceptance criteria, and ERPNext
  fit-gap analysis. Use after triage for any new feature or requirement, or when amending an existing spec.
---

# Spec Authoring (Spec-Driven Development)

Output: `context/features/F-XXX-<slug>/spec.md`, status **Draft**, plus a registry row (📝 Draft).

## Steps

1. **Discovery** (ideas/vague requirements): restate the problem, actors, and success measure in your own words.
   Identify the *job to be done*, not the solution. Ask only blocking questions.
2. **ERPNext fit-gap first** — before designing anything new, check whether standard ERPNext/Frappe already covers it:
   - search `frappe-bench/apps/erpnext` for existing DocTypes/reports/settings; check Settings DocTypes (TR-96)
   - classify each requirement: **Standard** (config only) · **Configure** (Custom Field/Property Setter, workflow) ·
     **Extend** (hooks/controller extension) · **Build** (new DocType/app code). Prefer left-most.
   - Record result in spec §5 "Architecture". Rule of thumb: customization cost compounds across every upgrade.
3. **Copy the template**, fill every section; write `N/A` instead of deleting sections.
4. **Write requirements well:**
   - User stories: `As a <role>, I want <capability>, so that <outcome>` (INVEST: independent, small, testable).
   - Functional requirements with MoSCoW priority; non-goals explicit.
   - **Acceptance criteria in Given/When/Then**, one per behaviour, each uniquely ID'd (`AC-n`) and including
     at least one negative/permission case and one edge case (empty, duplicate, back-dated, multi-company, cancelled doc).
   - Non-functional: expected data volume, performance budget, audit trail, i18n, permissions matrix.
5. **Data & contract sketch** (§6–§8): DocTypes/fields (links, indexes), customizations, API signatures, hooks.
   Detail belongs to `frappe-design`; keep here at the level reviewers need to approve scope.
6. **Open questions & risks** in §16 with owner and severity.
7. **Self-check** before presenting: every FR maps to ≥1 AC; no solution leakage in goals; no TBDs in "Must" items.
8. Update `context/features/README.md` registry (new row, status Draft).

## Gate 1
Present a ≤20-line summary + link to spec (use `ask_question`: Approve / Revise / Split). Only on approval set
status `✅ Approved`. For amendments, mark changes in the changelog (§17) with version bump.

## Anti-patterns
Specs describing implementation instead of behaviour · untestable criteria ("fast", "user-friendly") · skipping
fit-gap · scope bundles that should be separate features.

