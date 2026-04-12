"""Example: Generate a detailed NPC with dialogue.

Demonstrates using the orchestrator to create a single NPC character
with personality traits, dialogue trees, and contextual barks.

Usage:
    python examples/create_npc.py

Requires ANTHROPIC_API_KEY to be set in the environment or .env file.
"""

from __future__ import annotations

import asyncio
import json
import sys
from pathlib import Path

# Ensure the project root is on sys.path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import anthropic

from orchestrator.config import GameConfig
from orchestrator.prompts import NARRATIVE_SYSTEM
from schemas.game import NPC


async def main() -> None:
    config = GameConfig()

    if not config.anthropic_api_key:
        print("ERROR: Set ANTHROPIC_API_KEY in your environment or .env file.")
        sys.exit(1)

    client = anthropic.AsyncAnthropic(api_key=config.anthropic_api_key)

    npc_schema = json.dumps(NPC.model_json_schema(), indent=2)
    prompt = f"""Create a detailed NPC for a dark fantasy RPG:

Role: Merchant
Location: Blackwater Market — a shadowy underground bazaar
Personality: A grizzled ex-adventurer who settled down to sell exotic wares.
    Tells tall tales of their past exploits. Has a soft spot for young adventurers.
    Secretly knows about a hidden treasure vault.

Include:
- Full name and description
- At least 2 dialogue nodes with branching player choices
- Combat stats (they can fight if provoked)
- A "merchant" disposition

Respond with a JSON object matching this schema:
{npc_schema}"""

    print("Generating NPC...")
    response = await client.messages.create(
        model=config.worker_model,
        max_tokens=4096,
        system=NARRATIVE_SYSTEM,
        messages=[{"role": "user", "content": prompt}],
    )

    # Extract and parse JSON
    text = ""
    for block in response.content:
        if hasattr(block, "text"):
            text += block.text

    text = text.strip()
    if text.startswith("```"):
        first_nl = text.index("\n")
        text = text[first_nl + 1:]
    if text.endswith("```"):
        text = text[:-3]
    text = text.strip()

    npc = NPC.model_validate_json(text)

    print(f"\nNPC: {npc.name}")
    print(f"Role: {npc.role}")
    print(f"Disposition: {npc.disposition.value}")
    print(f"Location: {npc.location}")
    print(f"Description: {npc.description}")

    if npc.stats:
        print(f"\nStats:")
        for stat, val in npc.stats.items():
            print(f"  {stat}: {val}")

    if npc.dialogue:
        print(f"\nDialogue nodes: {len(npc.dialogue)}")
        for node in npc.dialogue:
            print(f"\n  [{node.id}]")
            for line in node.lines:
                emotion_tag = f" ({line.emotion})" if line.emotion != "neutral" else ""
                print(f"    {line.speaker}{emotion_tag}: {line.text[:80]}...")
            if node.choices:
                for choice in node.choices:
                    print(f"    > {choice.get('text', '...')} -> {choice.get('next_node_id', 'end')}")


if __name__ == "__main__":
    asyncio.run(main())
