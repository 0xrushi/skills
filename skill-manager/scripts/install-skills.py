#!/usr/bin/env python3
"""Install skills from a shared git repository into agent skill directories.

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


def install_skill(skill_src: Path, skill_dst: Path) -> None:
    """Copy a single skill directory to destination, preserving structure."""
    if skill_dst.exists():
        shutil.rmtree(skill_dst)
    shutil.copytree(skill_src, skill_dst, symlinks=True)
    print(f"  Installed: {skill_dst}")


def discover_skills(repo_path: Path) -> list[Path]:
    """Discover skill directories in a repo."""
    skills = []
    if not repo_path.exists():
        return skills
    # Direct SKILL.md files at root (pi style)
    for md in repo_path.glob("*.md"):
        skills.append(repo_path / md.stem)
    # Subdirectories with SKILL.md
    for subdir in repo_path.iterdir():
        if subdir.is_dir() and (subdir / "SKILL.md").exists():
            skills.append(subdir)
    return skills


def main() -> int:
    parser = argparse.ArgumentParser(description="Install skills from repo to agents")
    parser.add_argument("--repo", default=".", help="Path to skills git repo (default: current directory)")
    parser.add_argument("--agents", nargs="+", choices=list(AGENTS.keys()) + ["all"],
                        default=["all"], help="Target agents")
    parser.add_argument("--skill", default=None, help="Install only this skill name")
    args = parser.parse_args()

    repo_path = Path(args.repo).expanduser().resolve()
    if not repo_path.exists():
        print(f"ERROR: Repo not found: {repo_path}")
        return 1

    target_agents = list(AGENTS.keys()) if "all" in args.agents else args.agents

    # Discover skills in repo
    repo_skills = {}
    for skill_dir in discover_skills(repo_path):
        # Determine skill name from frontmatter or dirname
        skill_md = skill_dir / "SKILL.md" if skill_dir.is_dir() else skill_dir.parent / f"{skill_dir.name}.md"
        if not skill_md.exists():
            skill_md = skill_dir / "SKILL.md"
        name = skill_dir.name
        if skill_md.exists():
            with open(skill_md, "r") as f:
                for line in f:
                    if line.startswith("name:"):
                        name = line.split(":", 1)[1].strip()
                        break
        repo_skills[name] = skill_dir

    if args.skill and args.skill not in repo_skills:
        print(f"ERROR: Skill '{args.skill}' not found in repo. Available: {list(repo_skills.keys())}")
        return 1

    skills_to_install = [args.skill] if args.skill else list(repo_skills.keys())

    for agent in target_agents:
        print(f"\n📦 Installing to {agent}...")
        for skill_dir in AGENTS[agent]:
            skill_dir.mkdir(parents=True, exist_ok=True)
            for skill_name in skills_to_install:
                src = repo_skills[skill_name]
                dst = skill_dir / skill_name
                install_skill(src, dst)

    print("\n✅ Done. Restart agents to pick up new skills.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
