"""WorldBuilder agent -- generates game worlds, dungeons, and overworld maps.

Uses Claude Sonnet to produce structured world geometry: regions, rooms,
connections, terrain, points of interest, and procedural dungeon layouts.
The Director dispatches this agent first in the pipeline so that all
downstream agents (Narrative, Mechanics, Art) have spatial context.
"""

from __future__ import annotations

import json
import logging
import uuid
from typing import Any

import claudex_client as claude

from schemas.project import GameConcept
from schemas.world import (
    Biome,
    Connection,
    DungeonLayout,
    OverworldMap,
    Region,
    Room,
    RoomType,
    WorldDefinition,
)

logger = logging.getLogger(__name__)


class WorldBuilder:
    """Generates game worlds: maps, regions, rooms, connections, terrain, points of interest.

    Every public method makes one or more Claude CLI calls with a level-design-focused
    system prompt and returns validated Pydantic models from ``schemas.world``.
    """

    SYSTEM_PROMPT: str = """\
You are an expert **level designer and world architect** working inside GameForge,
an AI-powered game development toolkit that outputs 2-D Godot projects.

Your sole job is to design the spatial structure of game worlds.  When you
receive a game concept or an expansion request, you produce **valid JSON**
describing regions, rooms, connections, dungeons, and overworld maps.

Design principles you MUST follow:
1. **Player flow** -- the world should guide the player naturally from easy to hard
   areas.  Use visual landmarks and connection structure to create a sense of
   direction without heavy hand-holding.
2. **Pacing** -- alternate high-tension areas (combat rooms, boss arenas) with
   low-tension ones (safe rooms, scenic vistas, shops).  Never place more than
   three combat rooms in a row without a breather.
3. **Difficulty curves** -- level ranges must progress logically outward from the
   starting area.  Adjacent regions should overlap by 1-2 levels so the player
   always has a choice of where to go next.
4. **Visual variety** -- avoid repeating the same biome for adjacent regions.
   Contrast biomes to make each transition memorable (e.g., lush forest -> arid
   canyon -> frozen peaks).
5. **Secrets and exploration** -- every region should contain at least one hidden
   connection, secret room, or optional area that rewards curious players.
6. **Connectivity** -- the region/room graph must be fully connected.  No orphan
   nodes.  Include shortcuts and loops so the world feels interconnected, not
   linear.
7. **Feasibility** -- everything you design must be implementable in a 2-D
   tile-based Godot game.  No features that require 3-D geometry.

Output rules:
- Respond ONLY with the requested JSON object -- no commentary, no markdown fences.
- Every ``id`` field must be a unique, URL-safe slug (lowercase, hyphens).
- Room descriptions should be 1-3 atmospheric sentences in second person
  ("You step into a dimly lit corridor...").
- Use the schemas provided in each prompt exactly; do not invent extra fields.
"""

    # ------------------------------------------------------------------
    # Construction
    # ------------------------------------------------------------------

    def __init__(self, client: claude.AsyncClaudeClient, model: str = "claude-sonnet-4-6") -> None:
        self._client = client
        self._model = model

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    async def generate_world(self, concept: GameConcept) -> WorldDefinition:
        """Generate a complete world from a game concept.

        Produces an overworld map with multiple regions, each populated with
        rooms, connections, and points of interest.  The world structure is
        designed to support the concept's mechanics, mood, and target playtime.
        """
        schema = WorldDefinition.model_json_schema()
        region_schema = Region.model_json_schema()

        user_msg = (
            f"Create a complete world definition for this game concept:\n\n"
            f"{concept.model_dump_json(indent=2)}\n\n"
            f"Requirements:\n"
            f"- Include 4-8 distinct regions with varied biomes\n"
            f"- Each region needs 3-6 rooms with connections\n"
            f"- At least one dungeon entrance per region\n"
            f"- A clear starting region with level_range (1, 3)\n"
            f"- Factions should align with the setting\n"
            f"- Include points of interest that can anchor quests\n\n"
            f"Region schema:\n{json.dumps(region_schema, indent=2)}\n\n"
            f"Respond with a JSON object matching this top-level schema:\n"
            f"{json.dumps(schema, indent=2)}"
        )

        raw = await self._call(user_msg)
        return WorldDefinition.model_validate(raw)

    async def generate_dungeon(
        self,
        theme: str,
        difficulty: int,
        room_count: int,
    ) -> DungeonLayout:
        """Generate a procedural dungeon layout.

        Creates a dungeon with rooms, connections, enemy placements, loot
        tables, traps, and puzzles.  The dungeon is designed around the
        given theme and difficulty level.

        Parameters
        ----------
        theme:
            Visual/narrative theme (e.g. "haunted crypt", "goblin mine").
        difficulty:
            Difficulty rating 1-10.
        room_count:
            Target number of rooms (actual may vary slightly for pacing).
        """
        schema = DungeonLayout.model_json_schema()

        user_msg = (
            f"Generate a dungeon layout with these parameters:\n\n"
            f"- Theme: {theme}\n"
            f"- Difficulty: {difficulty}/10\n"
            f"- Target room count: {room_count}\n\n"
            f"Requirements:\n"
            f"- Include an entrance room, an exit room, and a boss room\n"
            f"- At least one rest/safe room between the midpoint and the boss\n"
            f"- At least one secret room accessible via a hidden connection\n"
            f"- At least one puzzle room and one treasure room\n"
            f"- Enemy placement should escalate toward the boss\n"
            f"- Loot should be placed to reward exploration of side paths\n"
            f"- Connections should form loops, not just a linear corridor\n\n"
            f"Respond with a JSON object matching this schema:\n"
            f"{json.dumps(schema, indent=2)}"
        )

        raw = await self._call(user_msg)
        return DungeonLayout.model_validate(raw)

    async def generate_overworld(
        self,
        regions: int,
        biomes: list[str],
    ) -> OverworldMap:
        """Generate an overworld map with regions and connections.

        Parameters
        ----------
        regions:
            Number of regions to generate.
        biomes:
            List of biome types to distribute across regions.
        """
        schema = OverworldMap.model_json_schema()
        biome_values = [b.value if isinstance(b, Biome) else b for b in biomes]

        user_msg = (
            f"Generate an overworld map with these parameters:\n\n"
            f"- Number of regions: {regions}\n"
            f"- Biomes to use: {json.dumps(biome_values)}\n\n"
            f"Requirements:\n"
            f"- Every region must connect to at least one other region\n"
            f"- The starting region should be relatively safe (level 1-3)\n"
            f"- Level ranges should increase as you move away from start\n"
            f"- Include at least one long-distance connection (shortcut) between\n"
            f"  non-adjacent regions to add exploration depth\n"
            f"- Each region should have a distinct ambient_mood\n"
            f"- Include 2-4 points of interest per region\n\n"
            f"Respond with a JSON object matching this schema:\n"
            f"{json.dumps(schema, indent=2)}"
        )

        raw = await self._call(user_msg)
        return OverworldMap.model_validate(raw)

    async def expand_region(self, region: Region, detail_level: int) -> Region:
        """Add detail to an existing region (sub-rooms, hidden areas, secrets).

        Parameters
        ----------
        region:
            The region to expand with more detail.
        detail_level:
            1 = light detail (a few extra rooms),
            3 = medium (side areas, hidden paths),
            5 = maximum (every corner fleshed out, multiple secrets).
        """
        schema = Region.model_json_schema()

        user_msg = (
            f"Expand this region with additional detail (level {detail_level}/5):\n\n"
            f"Current region:\n{region.model_dump_json(indent=2)}\n\n"
            f"Requirements based on detail level {detail_level}:\n"
            f"- Add {detail_level * 2} new rooms to the region\n"
            f"- Add at least {detail_level} hidden connections or secret areas\n"
            f"- Add environmental storytelling in room descriptions\n"
            f"- Ensure new rooms connect logically to existing ones\n"
            f"- Maintain the region's biome and ambient_mood\n"
            f"- Add new points of interest that could anchor side quests\n"
            f"- Preserve all existing room IDs and connections\n\n"
            f"Respond with the COMPLETE updated region (not just the new parts) "
            f"matching this schema:\n{json.dumps(schema, indent=2)}"
        )

        raw = await self._call(user_msg)
        return Region.model_validate(raw)

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    async def _call(self, user_message: str, max_retries: int = 3) -> dict[str, Any]:
        """Make a Claude CLI call and parse the JSON response.

        Retries on transient API errors and JSON parse failures.
        """
        last_error: Exception | None = None

        for attempt in range(1, max_retries + 1):
            try:
                logger.debug(
                    "WorldBuilder Claude CLI attempt %d/%d (model=%s)",
                    attempt, max_retries, self._model,
                )

                response = await self._client.messages.create(
                    model=self._model,
                    max_tokens=8192,
                    system=self.SYSTEM_PROMPT,
                    messages=[{"role": "user", "content": user_message}],
                )

                text = self._extract_text(response)
                parsed = json.loads(text)
                logger.info("WorldBuilder call succeeded on attempt %d", attempt)
                return parsed  # type: ignore[no-any-return]

            except json.JSONDecodeError as exc:
                logger.warning(
                    "WorldBuilder attempt %d/%d: invalid JSON -- %s",
                    attempt, max_retries, exc,
                )
                last_error = exc

            except claude.ClaudeCliError as exc:
                logger.warning(
                    "WorldBuilder attempt %d/%d: API status error %d -- %s",
                    attempt, max_retries, exc.status_code, exc.message,
                )
                last_error = exc
                # Don't retry on auth errors
                if exc.status_code == 401:
                    raise

            except claude.ConnectionError as exc:
                logger.warning(
                    "WorldBuilder attempt %d/%d: connection error -- %s",
                    attempt, max_retries, exc,
                )
                last_error = exc

        raise RuntimeError(
            f"WorldBuilder failed after {max_retries} attempts. Last error: {last_error}"
        )

    @staticmethod
    def _extract_text(response: claude.types.Message) -> str:
        """Pull the text content from a Claude response and strip code fences."""
        text = ""
        for block in response.content:
            if hasattr(block, "text"):
                text += block.text

        text = text.strip()

        # Strip markdown code fences
        if text.startswith("```"):
            first_newline = text.index("\n")
            text = text[first_newline + 1:]
        if text.endswith("```"):
            text = text[:-3]

        return text.strip()
