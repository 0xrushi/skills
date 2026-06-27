#!/usr/bin/env python3
"""Pull latest changes from the shared git repo and update local agent skill directories.

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


def discover_skills(repo_path: Path) -> list[Path]:
    """Discover skill directories in a repo."""
    skills = []
    if not repo_path.exists():
        return skills
    for subdir in repo_path.iterdir():
        if subdir.is_dir() and (subdir / "SKILL.md").exists():
            skills.append(subdir)
    return skills


def install_skill(skill_src: Path, skill_dst: Path) -> None:
    """Copy a single skill directory to destination."""
    if skill_dst.exists():
        shutil.rmtree(skill_dst)
    shutil.copytree(skill_src, skill_dst, symlinks=True)
    print(f"  Updated: {skill_dst}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Pull latest skills from repo and update agents")
    parser.add_argument("--repo", default=".", help="Path to skills git repo (default: current directory)")
    parser.add_argument("--agents", nargs="+", choices=list(AGENTS.keys()) + ["all"],
                        default=["all"], help="Target agents")
    parser.add_argument("--skill", default=None, help="Update only this skill name")
    args = parser.parse_args()

    repo_path = Path(args.repo).expanduser().resolve()
    if not repo_path.exists():
        print(f"ERROR: Repo not found: {repo_path}")
        return 1
    if not (repo_path / ".git").exists():
        print(f"ERROR: Not a git repo: {repo_path}")
        return 1

    target_agents = list(AGENTS.keys()) if "all" in args.agents else args.agents

    # Pull latest
    print("⬇️  Pulling latest changes...")
    try:
        out = run(["git", "pull"], cwd=repo_path)
        print(out.stdout.strip())
    except subprocess.CalledProcessError as e:
        print(f"ERROR: git pull failed: {e.stderr}")
        return 1

    # Discover skills in repo
    repo_skills = {}
    for skill_dir in discover_skills(repo_path):
        skill_md = skill_dir / "SKILL.md"
        name = skill_dir.name
        with open(skill_md, "r") as f:
            for line in f:
                if line.startswith("name:"):
                    name = line.split(":", 1)[1].strip()
                    break
        repo_skills[name] = skill_dir

    if args.skill and args.skill not in repo_skills:
        print(f"ERROR: Skill '{args.skill}' not found in repo. Available: {list(repo_skills.keys())}")
        return 1

    skills_to_update = [args.skill] if args.skill else list(repo_skills.keys())

    for agent in target_agents:
        print(f"\n📦 Updating {agent}...")
        for skill_dir in AGENTS[agent]:
            skill_dir.mkdir(parents=True, exist_ok=True)
            for skill_name in skills_to_update:
                src = repo_skills[skill_name]
                dst = skill_dir / skill_name
                install_skill(src, dst)

    print("\n✅ Done. Restart agents to pick up updated skills.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
