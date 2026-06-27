#!/usr/bin/env python3
"""Commit skills from local agent directories to the shared git repo and push.

Supports: pi, claude, codex, opencode
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

AGENTS = {
    "pi": [
        Path.home() / ".pi" / "agent" / "skills",
        Path.home() / ".agents" / "skills",
    ],
    "claude": [
        Path.home() / ".claude" / "skills",
    ],
    "codex": [
        Path.home() / ".codex" / "skills",
    ],
    "opencode": [
        Path.home() / ".opencode" / "skills",
    ],
}


def run(cmd: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, cwd=cwd, check=True, capture_output=True, text=True)


def discover_skills(skill_dir: Path) -> list[Path]:
    """Discover skill directories in an agent skills folder."""
    skills = []
    if not skill_dir.exists():
        return skills
    for subdir in skill_dir.iterdir():
        if subdir.is_dir() and (subdir / "SKILL.md").exists():
            skills.append(subdir)
    return skills


def copy_skills_to_repo(repo_path: Path, agents: list[str], only_skill: str | None = None) -> list[str]:
    """Copy skills from agent dirs to repo. Returns list of skill names copied."""
    copied = set()
    for agent in agents:
        for skill_dir in AGENTS[agent]:
            for skill in discover_skills(skill_dir):
                name = skill.name
                if only_skill and name != only_skill:
                    continue
                # Read name from frontmatter if available
                skill_md = skill / "SKILL.md"
                with open(skill_md, "r") as f:
                    for line in f:
                        if line.startswith("name:"):
                            name = line.split(":", 1)[1].strip()
                            break
                dst = repo_path / name
                if dst.exists():
                    shutil.rmtree(dst)
                shutil.copytree(skill, dst, symlinks=True)
                copied.add(name)
                print(f"  Copied '{name}' from {agent}")
    return list(copied)


def main() -> int:
    parser = argparse.ArgumentParser(description="Commit and push skills to repo")
    parser.add_argument("--repo", default=".", help="Path to skills git repo (default: current directory)")
    parser.add_argument("--agents", nargs="+", choices=list(AGENTS.keys()) + ["all"],
                        default=["all"], help="Source agents")
    parser.add_argument("--skill", default=None, help="Commit only this skill name")
    parser.add_argument("--message", "-m", default="Update skills", help="Git commit message")
    parser.add_argument("--push", action="store_true", default=True, help="Push after commit")
    parser.add_argument("--no-push", dest="push", action="store_false", help="Do not push")
    args = parser.parse_args()

    repo_path = Path(args.repo).expanduser().resolve()
    if not (repo_path / ".git").exists():
        print(f"ERROR: Not a git repo: {repo_path}")
        return 1

    target_agents = list(AGENTS.keys()) if "all" in args.agents else args.agents

    # Pull first to avoid conflicts
    print("⬇️  Pulling latest changes...")
    try:
        run(["git", "pull"], cwd=repo_path)
    except subprocess.CalledProcessError as e:
        print(f"WARNING: git pull failed: {e.stderr}")

    print(f"\n📝 Copying skills to repo...")
    copied = copy_skills_to_repo(repo_path, target_agents, args.skill)

    if not copied:
        print("No skills to commit.")
        return 0

    # Commit
    run(["git", "add", "-A"], cwd=repo_path)
    result = subprocess.run(["git", "diff", "--cached", "--quiet"], cwd=repo_path, capture_output=True)
    if result.returncode == 0:
        print("No changes to commit.")
        return 0

    run(["git", "commit", "-m", args.message], cwd=repo_path)
    print(f"✅ Committed: {args.message}")

    if args.push:
        print("\n🚀 Pushing...")
        run(["git", "push"], cwd=repo_path)
        print("✅ Pushed successfully.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
