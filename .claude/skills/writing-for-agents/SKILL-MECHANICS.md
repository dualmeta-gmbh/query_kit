# Skill mechanics

The skill-specific branch of [SKILL.md](SKILL.md): frontmatter, the invocation choice, where skills live here, and the set this repository runs.

## Where a skill lives

Project skills: `.claude/skills/<name>/SKILL.md`, with sibling reference files beside it, reached by relative links from `SKILL.md`. The upstream `mattpocock-skills` plugin, which this set was adapted from, ships skills with some of the same names (`grilling`, `codebase-design`, `domain-modeling`, `writing-for-agents`, `improve-codebase-architecture`); it is not required, and when installed at user scope it is reached as `mattpocock-skills:<name>`, a project skill as the bare name. Project skills call each other by the bare name so the repository-adapted version is the one that runs.

## Frontmatter

```yaml
---
name: blast-radius
description: <the context pointer: what it is, then the branches that trigger it>
disable-model-invocation: true   # only for a user-invoked skill
---
```

`name` matches the directory. The description is the always-loaded pointer; the pointer rules in SKILL.md apply in full. This frontmatter is Claude Code's; the set is packaged for `.claude/skills/` only, and another host's invocation policy (a per-skill `agents/openai.yaml`, for one) is not shipped.

## Invocation

Two choices, trading the two loads:

- **Model-invoked** (omit `disable-model-invocation`): the agent fires it on its own and other skills can call it with the Skill tool. Permanent context load for its description, in exchange for reach. Required when nobody is in the loop to type the name: this repository's AFK rule (`CLAUDE.md`) means an agent that must reach a skill before a fix has to find it unprompted.
- **User-invoked** (`disable-model-invocation: true`): only a human typing its name fires it as a skill; no other skill can. No description is loaded, so the human is the index. This governs the host's automatic invocation only: an agent can still read the file by path, and invoking it by name does not switch the AFK default off (REPOSITORY.md, "Who decides"). For a heavy, deliberate session someone starts on purpose.

Pick model-invocation only when the agent or another skill must reach the skill on its own. Shared reference two user-invoked skills both need lives in neither; put it in a plain file both point at. Here that file is `codebase-design/REPOSITORY.md`: the repository's standing constraints, stated once, reached by a relative link from every other skill, so a change to a constraint is a one-file edit.

## The set here, and why each is what it is

| Skill | Invocation | Why |
|---|---|---|
| `codebase-design` | model | Shared vocabulary four skills call; all reference. |
| `grilling` | model | Called by `improve-codebase-architecture`; also fires on `wayfinder:grilling` tickets with no human present. |
| `domain-modeling` | model | Fires when `CONTEXT.md` or an ADR is being changed, which happens inside other work. |
| `blast-radius` | model | Must be reached before every `lib/` change without being asked; the fix-introduces-defect cycle is the reason. |
| `unslop` | model | The jargon guard is a CI gate and the AI-coded disclosure makes tells in docs a credibility cost; writeups from other skills route through it. |
| `writing-for-agents` | model | Fires when a skill or `CLAUDE.md` is edited. |
| `improve-codebase-architecture` | user | A session someone starts deliberately; nothing needs to reach it unprompted. |
| `thermonuclear-review` | user | A whole-codebase sweep is expensive and chosen, never incidental. |

## Splitting by invocation

Split off a model-invoked skill when a distinct leading word should trigger it on its own, or another skill must reach it. The new description is permanent context load; the independent reach has to be worth it. `blast-radius` is split from `thermonuclear-review` for exactly this: the review is chosen, the proof step must fire by itself.

## Router skills

When user-invoked skills multiply past what a human remembers, one user-invoked router names them and when to reach for each. Two user-invoked skills do not need one yet; a line each in `CLAUDE.md` is the router.
