# agent-skills

Personal [Agent Skills](https://agentskills.io/specification) shared across Claude Code,
Codex, pi, and opencode.

## Install

```bash
git clone git@github.com:dschaaff/agent-skills.git ~/development/github/agent-skills
~/development/github/agent-skills/install.sh
```

`install.sh` creates two symlinks, both pointing at this repo's `skills/`:

| Link | Read by |
| --- | --- |
| `~/.agents/skills` | Codex, pi, opencode |
| `~/.claude/skills` | Claude Code (and opencode) |

Two links rather than one because Claude Code only looks in `~/.claude/skills`, while Codex
and pi only look in `~/.agents/skills`. Both are symlinks to the checkout, so editing a
skill mid-session edits the git-tracked file.

The script is idempotent. It replaces only the symlinks the previous stow-based dotfiles
setup created; anything else already occupying either path is reported and left in place.

Skills can also be installed with the [`skills`](https://github.com/vercel-labs/skills) CLI:

```bash
npx skills add dschaaff/agent-skills
```

## Skills

| Skill | Purpose |
| --- | --- |
| `brainstorm` | Interview an idea into shared understanding before any code |
| `to-spec` | Turn a finished design conversation into a spec file |
| `implement-spec` | Work a spec slice by slice with fresh subagents |
| `verify` | Review a diff against a spec on two axes |
| `tdd` | Red-green test-driven development |
| `grilling` | Stress-test a plan or decision through relentless questioning |
| `codebase-design` | Shared vocabulary for designing deep modules |
| `domain-modeling` | Build the project's glossary and record decisions as ADRs |
| `improve-codebase-architecture` | Scan for deepening opportunities, report them, grill one |
| `playwright-cli` | Drive a browser for testing and extraction |

## Development

```bash
prek run --all-files      # everything CI runs
./scripts/validate-skills.sh    # spec compliance
./scripts/check-skill-refs.sh   # inter-skill references resolve
./tests/install_test.sh         # install.sh, against throwaway HOMEs
```

Adding a skill: create `skills/<name>/SKILL.md` with `name` and `description` frontmatter.
`name` must match the directory. Keep to the spec's fields — these files are read by four
different harnesses, so vendor-specific frontmatter either gets ignored or turns the skill
into a decoy elsewhere. The one exception is `disable-model-invocation`, allowlisted in
`ALLOWED_EXTRA_FIELDS` in `scripts/validate-skills.sh`: Claude Code reads it to keep a skill
out of the model-facing list, and the rest ignore it. A skill carrying an allowlisted field
is still validated in full, as a copy with the field stripped. Adding to that list is a
deliberate decision, not a way around a validation failure. When one skill points at another, write it as "invoke the `name`
skill"; `check-skill-refs.sh` scans every markdown file under `skills/`, but only catches rot
in that form — a bare `/name` slips past it.
