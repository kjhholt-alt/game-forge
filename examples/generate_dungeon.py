"""Example: Generate a procedural dungeon using GameForge agents.

This script demonstrates the full pipeline — from a natural-language prompt
to a complete game project with dungeon layout, NPCs, items, and QA report.

Usage:
    python examples/generate_dungeon.py

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

    project = await forge.create(
        prompt=(
            "A dark gothic dungeon beneath a ruined cathedral. "
            "10 rooms connected by narrow corridors. "
            "Undead enemies (skeletons, ghosts, wraiths). "
            "A vampire lord as the final boss. "
            "Treasure rooms with cursed artifacts. "
            "A merchant ghost who sells holy water."
        ),
        genre=GameGenre.ROGUELIKE,
    )

    print(f"\nGenerated: {project.concept.title}")
    print(f"Setting: {project.concept.setting}")
    print(f"Mechanics: {', '.join(project.concept.core_mechanics)}")

    if project.world:
        print(f"\nWorld: {project.world.name}")
        print(f"Regions: {len(project.world.regions)}")

    print(f"\nNPCs: {len(project.npcs)}")
    for npc in project.npcs:
        print(f"  - {npc.name} ({npc.role}) [{npc.disposition.value}]")

    print(f"\nItems: {len(project.items)}")
    for item in project.items:
        print(f"  - {item.name} ({item.item_type.value}) [rarity: {item.rarity}]")

    print(f"\nQuests: {len(project.quests)}")
    for quest in project.quests:
        print(f"  - {quest.name} ({quest.quest_type.value}) [{len(quest.objectives)} objectives]")

    if project.qa_report:
        status = "PASSED" if project.qa_report.passed else "FAILED"
        print(f"\nQA Score: {project.qa_report.overall_score}/10 ({status})")
        print(f"Summary: {project.qa_report.summary}")
        if project.qa_report.issues:
            print(f"Issues: {len(project.qa_report.issues)}")
            for issue in project.qa_report.issues[:5]:
                print(f"  [{issue.severity.value}] {issue.description}")

    # Export to disk
    output_dir = Path("./my-dungeon-game")
    forge.export(output_dir)
    print(f"\nExported to {output_dir.resolve()} -- open in Godot!")


if __name__ == "__main__":
    asyncio.run(main())
