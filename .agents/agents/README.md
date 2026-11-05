# Agent Roles

Role prompts for sub-agents, used through `invoke_subagent` (type `self` or `research`; models: `pro` for
architect/security, `inherit` otherwise). Pass the role file path plus the task; the sub-agent must first read
`AGENTS.md` and `context/`.

| Role file | Writes code? | Use in phase | Typical model |
| :-- | :-- | :-- | :-- |
| [product-analyst.md](./product-analyst.md) | No (docs only) | triage, spec | inherit |
| [frappe-architect.md](./frappe-architect.md) | No (spec only) | design | pro |
| [frappe-engineer.md](./frappe-engineer.md) | Yes | implement, bugfix | inherit |
| [qa-engineer.md](./qa-engineer.md) | Tests only | implement, verify | inherit |
| [code-reviewer.md](./code-reviewer.md) | No | review | inherit |
| [security-reviewer.md](./security-reviewer.md) | No | review (risk-flagged work) | pro |

## Invocation pattern
```
invoke_subagent(TypeName="self", Role="Code reviewer",
  Prompt="Read .agents/agents/code-reviewer.md and follow it. Review: <diff/paths>. Spec: <path>. Return findings table only.")
```

## Orchestration rules
- **One writer at a time** per repo; reviewers/researchers run in parallel (read-only).
- Sub-agents inherit the gates: they never commit, push, run destructive commands, or skip approval gates.
- Give each a *self-contained* brief: goal, spec path, files in scope, expected output format.
- The orchestrator (`frappe-delivery`) owns user communication and verifies sub-agent claims by running checks itself.

