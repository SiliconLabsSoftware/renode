# AGENTS.md

## Scope

Applies to this repository unless a nested `AGENTS.md` overrides it.

## Keep this file lean

- Keep only non-obvious, high-impact guidance that is hard to infer from code.
- Do not include generated repo tours or directory catalogs.
- Prefer fixing code/tests/tooling over adding prompt instructions.

## Skills

Agent workflows live under `.agents/skills/`. Read the skill when the task matches; do not copy skill contents into this file.

| Skill | Use when |
|-------|----------|
| [renode-build](.agents/skills/renode-build/SKILL.md) | Rebuild Renode after model or log changes |
| [renode-test_lib](.agents/skills/renode-test_lib/SKILL.md) | Run a `test_lib` / pyrenode3 test locally |

## Rules easy to miss

- Host architecture is auto-detected by `build.sh`. Do not pass `--host-arch` unless overriding detection.
- `test_lib` tests run from the repo root with `RENODE_BASE_PATH` set to that root.
- Authoritative build entry point is `./build.sh`. Authoritative `test_lib` CLI is `tests/test_lib`.

## Maintenance

Before adding content here, ask:

- Is this hard to infer quickly from repository files?
- Does this prevent a repeated, expensive mistake?

If both answers are no, do not add it. Put task procedures in a skill instead.
