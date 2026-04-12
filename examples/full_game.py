"""Example: Generate a complete game with all systems.

Demonstrates the full GameForge pipeline including concept generation,
world building, narrative design, QA testing, iteration, and export.

Usage:
    python examples/full_game.py

Requires ANTHROPIC_API_KEY to be set in the environment or .env file.
"""

from __future__ import annotations

import asyncio
import sys
from pathlib import Path

# Ensure the project root is on sys.path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from orchestrator import GameForge
from orchestrator.config import GameConfig, GameGenre


async def main() -> None:
    config = GameConfig()

    if not config.anthropic_api_key:
        print("ERROR: Set ANTHROPIC_API_KEY in your environment or .env file.")
        sys.exit(1)

    forge = GameForge(config)

    # ------------------------------------------------------------------
    # Phase 1: Generate
    # ------------------------------------------------------------------

    print("=" * 60)
    print("PHASE 1: Generate")
    print("=" * 60)

    project = await forge.create(
        prompt="""\
A cozy pixel-art RPG set in a floating island archipelago.
The player is a mail carrier who delivers letters between sky islands.
Turn-based combat against sky pirates and storm elementals.
Befriend islanders and learn their stories.
Art style: 16-bit SNES era with warm pastel colours.
5-8 sky islands connected by airship routes.
A mail office hub where quests are picked up.
Hidden treasure on remote islands.""",
        genre=GameGenre.RPG,
    )

    print(f"\n=== {project.concept.title} ===")
    print(f"Setting: {project.concept.setting}")
    print(f"Mood: {project.concept.target_mood}")
    print(f"Art: {project.concept.art_style}")
    print(f"Mechanics: {', '.join(project.concept.core_mechanics)}")
    print(f"Playtime: {project.concept.estimated_playtime}")

    if project.world:
        print(f"\nWorld: {project.world.name}")
        print(f"Regions: {len(project.world.regions)}")
        for region in project.world.regions:
            print(f"  - {region.name} ({region.biome}) [Lv.{region.level_range[0]}-{region.level_range[1]}]")

    print(f"\nQuests: {len(project.quests)}")
    print(f"NPCs: {len(project.npcs)}")
    print(f"Items: {len(project.items)}")
    print(f"Art Specs: {len(project.art_specs)}")

    # ------------------------------------------------------------------
    # Phase 2: Iterate based on QA
    # ------------------------------------------------------------------

    print("\n" + "=" * 60)
    print("PHASE 2: QA & Iteration")
    print("=" * 60)

    if project.qa_report:
        print(f"QA Score: {project.qa_report.overall_score}/10")
        print(f"Passed: {project.qa_report.passed}")
        print(f"Summary: {project.qa_report.summary}")

        if project.qa_report.strengths:
            print("\nStrengths:")
            for s in project.qa_report.strengths:
                print(f"  + {s}")

        if project.qa_report.issues:
            print(f"\nIssues ({len(project.qa_report.issues)}):")
            for issue in project.qa_report.issues:
                print(f"  [{issue.severity.value}] {issue.category}: {issue.description}")

        if not project.qa_report.passed:
            print("\nIterating to fix issues...")
            project = await forge.iterate(
                "Fix all critical and major issues found in QA. "
                "Add more variety to encounters and ensure quest rewards scale appropriately."
            )
            if project.qa_report:
                print(f"New QA Score: {project.qa_report.overall_score}/10")

    # ------------------------------------------------------------------
    # Phase 3: Export
    # ------------------------------------------------------------------

    print("\n" + "=" * 60)
    print("PHASE 3: Export")
    print("=" * 60)

    output_dir = Path("./my-sky-island-game")
    forge.export(output_dir)
    print(f"\nExported to {output_dir.resolve()}")
    print("Open the folder in Godot 4.6 to play!")

    # ------------------------------------------------------------------
    # Summary
    # ------------------------------------------------------------------

    status = forge.status()
    print("\n" + "=" * 60)
    print("PROJECT SUMMARY")
    print("=" * 60)
    for key, value in status.items():
        print(f"  {key}: {value}")


if __name__ == "__main__":
    asyncio.run(main())
