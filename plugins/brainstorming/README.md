# Brainstorming Plugin

Collaborative design agent for Claude Code that explores ideas through structured dialogue and produces design documents before implementation.

## Usage

```
/brainstorm
```

Starts an interactive brainstorming session for a feature, architecture decision, or any creative task.

## What It Does

The agent follows a structured workflow:
- Explores existing project context (files, docs, commits, tech stack)
- Asks clarifying questions one at a time (prefers multiple choice)
- Proposes 2-3 approaches with trade-offs and a recommendation
- Presents the design section by section, getting approval after each
- Writes a design document to `docs/plans/YYYY-MM-DD-<topic>-design.md`

## When to Use

- Before starting a new feature or significant change
- When choosing between multiple valid approaches
- When a vague idea needs structure before implementation
- For architecture decisions that affect multiple components

## Example

```
User: /brainstorm

Agent: [Scans project context silently]

Agent: What would you like to design? Are you thinking about:
  A) A new feature for the app
  B) A refactor of an existing system
  C) Something else?

User: A — I want to add WebSocket support for real-time updates

Agent: [Asks 3-5 targeted questions, one at a time]
Agent: [Proposes 2-3 approaches with trade-offs]
Agent: [Presents design sections, getting approval on each]
Agent: [Writes docs/plans/2026-02-20-websocket-realtime-design.md]

Design document saved. Ready for implementation.
```

## Version

**v1.0.0** - Initial release. Adapted from [obra/superpowers](https://github.com/obra/superpowers) brainstorming skill as a self-contained plugin.

## License

MIT
