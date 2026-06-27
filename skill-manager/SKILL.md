---
name: skill-manager
description: Manage AI agent skills across pi, Claude Code, OpenAI Codex, and OpenCode. Install skills from a shared git repo, commit and push new versions, and pull latest changes to update local skill directories. Use when the user asks to install, update, sync, commit, or push skills for any supported agent.
---

# Skill Manager

Manage skills across multiple AI coding agents from a single shared git repository.

## Supported Agents

| Agent | Skill Directories |
|-------|------------------|
| **pi** | `~/.pi/agent/skills/`, `~/.agents/skills/` |
| **claude** | `~/.claude/skills/` |
| **codex** | `~/.codex/skills/` |
| **opencode** | `~/.opencode/skills/` |

## Setup

The **current directory is your skills repo**. Run these commands from inside the repo (e.g. `~/Documents/skills`).

If you want to manage a repo elsewhere, use `--repo /path/to/repo`.

## Commands

### Install Skills

Install skills from the repo into one or more agents:

```bash
./scripts/install-skills.py --agents all
```

Install to specific agents only:

```bash
./scripts/install-skills.py --agents pi claude
```

Install a single skill:

```bash
./scripts/install-skills.py --skill my-skill --agents all
```

### Commit & Push

Copy skills from local agent directories into the repo, commit, and push:

```bash
./scripts/commit-skills.py --agents all -m "Add new skill"
```

Commit a single skill without pushing:

```bash
./scripts/commit-skills.py --skill my-skill --no-push
```

### Update (Pull & Merge)

Pull the latest changes from the repo and update local agent directories:

```bash
./scripts/update-skills.py --agents all
```

Update a single skill:

```bash
./scripts/update-skills.py --skill my-skill --agents pi opencode
```

## Typical Workflow

1. **Create or edit a skill** in one of the agent directories (e.g. `~/.pi/agent/skills/my-skill/`).
2. **Commit it** to this repo:
   ```bash
   ./scripts/commit-skills.py --agents pi -m "Add my-skill"
   ```
3. **Install it** on other agents:
   ```bash
   ./scripts/install-skills.py --agents claude codex opencode --skill my-skill
   ```
4. **Update all agents** after pulling on another machine:
   ```bash
   ./scripts/update-skills.py --agents all
   ```

## Notes

- Skills are identified by the `name:` field in their `SKILL.md` frontmatter.
- Restart agents after installing or updating skills for changes to take effect.
- The scripts preserve directory structures and overwrite existing skills on update.
