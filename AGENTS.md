# Agent Entry Point — Frappe / ERPNext v16 (`enterprise_hub`)

This repo is a Docker-first Frappe + ERPNext v16 dev stack. All custom logic lives in
`frappe-bench/apps/enterprise_hub/`; `frappe` and `erpnext` are read-only upstream.

## Before anything else
Read, in order: `context/ai-rules.md` → `context/project-overview.md` → `context/technical-rules.md`
(then `context/features/README.md` and the relevant `spec.md`). Those files are the governing standard
(rule IDs `AI-xx`, `TR-xx`). Never edit `ai-rules.md` / `technical-rules.md` unless explicitly asked.

## How work gets done
Every request (feature, bug, requirement, idea, chore) goes through the delivery lifecycle:
**use the `frappe-delivery` skill** as the entry point. It routes to phase skills
(`frappe-triage` → `frappe-spec` → `frappe-design` → `frappe-implement`/`frappe-bugfix` →
`frappe-verify` → `frappe-review` → `frappe-ship`). Role prompts for sub-agents are in `.agents/agents/`.

Workflow rules: `.agents/rules/`. If anything there conflicts with `context/*-rules.md`, the `context/` rules win.

