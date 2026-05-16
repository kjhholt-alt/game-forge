"""NarrativeEngine agent -- generates quests, dialogue, lore, and NPC content.

Uses Claude Sonnet to produce interconnected narrative content: main quest
chains, side quests, NPC definitions with personalities and schedules,
branching dialogue trees, world lore, and contextual NPC barks.
"""

from __future__ import annotations

import json
import logging
from typing import Any

import claudex_client as claude

from schemas.combat import StyleGuide
from schemas.npc import NPCDefinition, NPCRole, Personality
from schemas.project import GameConcept
from schemas.quest import (
    DialogueNode,
    DialogueOption,
    DialogueTree,
    LoreEntry,
    Quest,
    QuestChain,
    QuestObjective,
    QuestObjectiveType,
    QuestReward,
)
from schemas.world import Region, WorldDefinition

logger = logging.getLogger(__name__)


class NarrativeEngine:
    """Generates narrative content: quests, dialogue trees, lore, NPC personalities, story arcs.

    Every public method makes one or more Claude CLI calls with a narrative-design-focused
    system prompt and returns validated Pydantic models from ``schemas.quest`` and
    ``schemas.npc``.
    """

    SYSTEM_PROMPT: str = """\
You are an expert **narrative designer and game writer** working inside GameForge,
an AI-powered game development toolkit that outputs 2-D Godot projects.

Your sole job is to create compelling narrative content: quests, NPC personalities,
dialogue trees, world lore, and ambient barks.  You receive world geometry and
game concepts as input and weave stories into that spatial fabric.

Storytelling principles you MUST follow:
1. **Show, don't tell** -- reveal lore through environmental details, NPC
   conversations, and quest discoveries rather than exposition dumps.  A
   crumbling statue with a plaque tells more than a textbook paragraph.
2. **Meaningful choices** -- every dialogue branch and quest fork should have
   consequences the player can feel.  Choices that change nothing are worse
   than no choice at all.  Mark consequences in the ``effects`` / ``branches``
   fields so downstream systems can implement them.
3. **Consistent tone** -- match the game concept's ``target_mood``.  A whimsical
   fairy-tale game should not have grimdark torture scenes; a survival horror
   game should not have slapstick comedy NPCs (unless intentionally
   juxtaposed for effect, and even then, sparingly).
4. **Interconnected narratives** -- side quests should reference main-story
   events or factions.  NPCs should mention each other.  The world should
   feel like a living web, not isolated quest bubbles.
5. **Character depth** -- every NPC needs wants, fears, a speech pattern, and
   at least one contradiction in their personality.  A cowardly guard who is
   brave for his daughter.  A greedy merchant who secretly funds orphans.
6. **Pacing** -- main quest chains should follow classic dramatic structure:
   hook -> rising action -> midpoint twist -> escalation -> climax -> resolution.
   Side quests should be self-contained arcs that can be completed in 5-15
   minutes of gameplay.
7. **Quest design** -- objectives should be varied (don't chain five kill-quests
   in a row).  Rewards should match effort.  Prerequisites must form a DAG
   (directed acyclic graph) with no circular dependencies.
8. **Dialogue craft** -- NPC dialogue should reflect personality, social status,
   and current emotional state.  Use speech_pattern from the NPC definition.
   Keep individual lines short (1-3 sentences) for readability.

Output rules:
- Respond ONLY with the requested JSON object -- no commentary, no markdown fences.
- Every ``id`` field must be a unique, URL-safe slug (lowercase, hyphens).
- Quest and NPC names should be evocative and setting-appropriate.
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

    async def generate_main_quest(
        self,
        concept: GameConcept,
        world: WorldDefinition,
    ) -> QuestChain:
        """Generate the main storyline as a chain of connected quests.

        The chain follows classic dramatic structure and spans the full
        world, guiding the player through regions in a logical order.
        """
        schema = QuestChain.model_json_schema()

        user_msg = (
            f"Create the main quest chain for this game:\n\n"
            f"Concept:\n{concept.model_dump_json(indent=2)}\n\n"
            f"World:\n{world.model_dump_json(indent=2)}\n\n"
            f"Requirements:\n"
            f"- 5-10 quests forming a complete story arc\n"
            f"- Each quest should take place in a different region when possible\n"
            f"- Include a clear inciting incident, midpoint twist, and climax\n"
            f"- Quest objectives should be varied (mix of explore, talk, kill, solve, collect)\n"
            f"- Prerequisites should chain linearly with optional branches\n"
            f"- Rewards should escalate with difficulty\n"
            f"- The final quest should be a boss-tier encounter\n"
            f"- Set is_main_story to true\n"
            f"- Reference actual region IDs and location IDs from the world\n\n"
            f"Respond with a JSON object matching this schema:\n"
            f"{json.dumps(schema, indent=2)}"
        )

        raw = await self._call(user_msg)
        return QuestChain.model_validate(raw)

    async def generate_side_quests(
        self,
        world: WorldDefinition,
        count: int,
    ) -> list[Quest]:
        """Generate side quests tied to world locations.

        Each side quest is a self-contained mini-arc connected to
        a specific region and its points of interest.
        """
        schema = Quest.model_json_schema()

        user_msg = (
            f"Create {count} side quests for this world:\n\n"
            f"World:\n{world.model_dump_json(indent=2)}\n\n"
            f"Requirements:\n"
            f"- Each quest should be tied to a specific region/location from the world\n"
            f"- Distribute quests across regions (don't cluster them all in one area)\n"
            f"- Vary quest types: fetch, kill, explore, puzzle, escort, dialogue\n"
            f"- Each quest should have 2-4 objectives\n"
            f"- Side quests should reference or hint at main story themes\n"
            f"- Include at least one quest that spans multiple regions\n"
            f"- Include at least one quest with branching outcomes\n"
            f"- Rewards should be appropriate for the quest's level_requirement\n\n"
            f"Respond with a JSON object: {{\"quests\": [...]}} where each quest "
            f"matches this schema:\n{json.dumps(schema, indent=2)}"
        )

        raw = await self._call(user_msg)
        quests_raw = raw.get("quests", raw) if isinstance(raw, dict) else raw
        if isinstance(quests_raw, list):
            return [Quest.model_validate(q) for q in quests_raw]
        return []

    async def generate_npc(
        self,
        role: str,
        location: str,
        personality_seed: str,
    ) -> NPCDefinition:
        """Generate a full NPC with personality, dialogue, relationships, and schedule.

        Parameters
        ----------
        role:
            Functional role (e.g. "merchant", "quest_giver", "companion").
        location:
            Region or room ID where the NPC resides.
        personality_seed:
            A brief personality direction (e.g. "grizzled veteran with a dry wit").
        """
        schema = NPCDefinition.model_json_schema()

        user_msg = (
            f"Create a detailed NPC definition:\n\n"
            f"- Role: {role}\n"
            f"- Location ID: {location}\n"
            f"- Personality seed: {personality_seed}\n\n"
            f"Requirements:\n"
            f"- Full personality with 3-5 traits, 2-3 values, 1-2 fears, and 1-2 quirks\n"
            f"- A distinctive speech_pattern that reflects their background\n"
            f"- An appearance description vivid enough for character art generation\n"
            f"- A daily schedule with at least 3 time-of-day entries\n"
            f"- At least one relationship with another potential NPC\n"
            f"- A backstory that connects to the location's narrative\n"
            f"- If the role involves combat, include appropriate stats\n"
            f"- Include at least 2-3 idle barks and 2-3 greeting barks\n\n"
            f"Respond with a JSON object matching this schema:\n"
            f"{json.dumps(schema, indent=2)}"
        )

        raw = await self._call(user_msg)
        return NPCDefinition.model_validate(raw)

    async def generate_dialogue_tree(
        self,
        npc: NPCDefinition,
        context: str,
    ) -> DialogueTree:
        """Generate a branching dialogue tree for an NPC in a specific context.

        Parameters
        ----------
        npc:
            The NPC definition to generate dialogue for.
        context:
            When this dialogue triggers (e.g. "first_meeting", "quest_complete",
            "shop_browse", "campfire_rest").
        """
        schema = DialogueTree.model_json_schema()

        user_msg = (
            f"Create a dialogue tree for this NPC in a specific context:\n\n"
            f"NPC:\n{npc.model_dump_json(indent=2)}\n\n"
            f"Context: {context}\n\n"
            f"Requirements:\n"
            f"- Start with a greeting that fits the NPC's speech_pattern\n"
            f"- Include at least 3 branching points with 2-4 player options each\n"
            f"- At least one branch should reveal backstory or lore\n"
            f"- At least one branch should have gameplay consequences (give item,\n"
            f"  change reputation, unlock quest)\n"
            f"- Include emotion tags on dialogue nodes (neutral, happy, angry, sad, etc.)\n"
            f"- Dead-end branches should gracefully loop back or end the conversation\n"
            f"- The NPC's personality traits should come through in word choice and tone\n"
            f"- Keep individual lines to 1-3 sentences for readability\n\n"
            f"Respond with a JSON object matching this schema:\n"
            f"{json.dumps(schema, indent=2)}"
        )

        raw = await self._call(user_msg)
        return DialogueTree.model_validate(raw)

    async def generate_lore(
        self,
        world: WorldDefinition,
        depth: int,
    ) -> list[LoreEntry]:
        """Generate world lore: history, factions, legends, items of note.

        Parameters
        ----------
        world:
            The world to generate lore for.
        depth:
            1 = surface-level (5-8 entries),
            3 = medium (10-15 entries with cross-references),
            5 = deep (20+ entries forming an interconnected history).
        """
        schema = LoreEntry.model_json_schema()
        target_count = max(5, depth * 5)

        user_msg = (
            f"Generate world lore for this game world (depth {depth}/5):\n\n"
            f"World:\n{world.model_dump_json(indent=2)}\n\n"
            f"Requirements:\n"
            f"- Create approximately {target_count} lore entries\n"
            f"- Categories to cover: history, faction, legend, geography, item_lore\n"
            f"- Entries should cross-reference each other via related_entities\n"
            f"- At least half should be discoverable in-game (books, inscriptions, NPCs)\n"
            f"- Include location_hint for discoverable entries\n"
            f"- History entries should form a coherent timeline\n"
            f"- Faction entries should explain motivations and conflicts\n"
            f"- Legends should hint at hidden game content or secrets\n"
            f"- Item lore should connect artifacts to historical events\n\n"
            f"Respond with a JSON object: {{\"lore\": [...]}} where each entry "
            f"matches this schema:\n{json.dumps(schema, indent=2)}"
        )

        raw = await self._call(user_msg)
        lore_raw = raw.get("lore", raw) if isinstance(raw, dict) else raw
        if isinstance(lore_raw, list):
            return [LoreEntry.model_validate(entry) for entry in lore_raw]
        return []

    async def generate_barks(
        self,
        npc: NPCDefinition,
        situations: list[str],
    ) -> dict[str, list[str]]:
        """Generate contextual NPC barks (idle chatter, combat, discovery, etc.).

        Parameters
        ----------
        npc:
            The NPC to generate barks for.
        situations:
            List of situations to cover (e.g. ["idle", "combat", "greeting",
            "player_nearby", "low_health", "item_found"]).

        Returns
        -------
        dict[str, list[str]]
            Mapping of situation -> list of bark strings.
        """
        user_msg = (
            f"Generate contextual barks for this NPC:\n\n"
            f"NPC:\n{npc.model_dump_json(indent=2)}\n\n"
            f"Situations to cover: {json.dumps(situations)}\n\n"
            f"Requirements:\n"
            f"- 3-5 unique barks per situation\n"
            f"- Each bark should be a single short sentence (under 15 words)\n"
            f"- Barks must reflect the NPC's personality and speech_pattern\n"
            f"- Idle barks should reveal character (muttering about worries, humming)\n"
            f"- Combat barks should reflect their role (brave, cowardly, tactical)\n"
            f"- No two barks should say the same thing with different words\n\n"
            f"Respond with a JSON object where keys are situation names and values "
            f"are arrays of bark strings.\n"
            f"Example: {{\"idle\": [\"Hmm, where did I put that...\", ...], "
            f"\"combat\": [\"For the king!\", ...]}}"
        )

        raw = await self._call(user_msg)

        # Validate shape: every value should be a list of strings
        result: dict[str, list[str]] = {}
        if isinstance(raw, dict):
            for situation, barks in raw.items():
                if isinstance(barks, list):
                    result[situation] = [str(b) for b in barks]
                else:
                    result[situation] = [str(barks)]

        return result

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
                    "NarrativeEngine Claude CLI attempt %d/%d (model=%s)",
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
                logger.info("NarrativeEngine call succeeded on attempt %d", attempt)
                return parsed  # type: ignore[no-any-return]

            except json.JSONDecodeError as exc:
                logger.warning(
                    "NarrativeEngine attempt %d/%d: invalid JSON -- %s",
                    attempt, max_retries, exc,
                )
                last_error = exc

            except claude.ClaudeCliError as exc:
                logger.warning(
                    "NarrativeEngine attempt %d/%d: API status error %d -- %s",
                    attempt, max_retries, exc.status_code, exc.message,
                )
                last_error = exc
                if exc.status_code == 401:
                    raise

            except claude.ConnectionError as exc:
                logger.warning(
                    "NarrativeEngine attempt %d/%d: connection error -- %s",
                    attempt, max_retries, exc,
                )
                last_error = exc

        raise RuntimeError(
            f"NarrativeEngine failed after {max_retries} attempts. Last error: {last_error}"
        )

    @staticmethod
    def _extract_text(response: claude.types.Message) -> str:
        """Pull the text content from a Claude response and strip code fences."""
        text = ""
        for block in response.content:
            if hasattr(block, "text"):
                text += block.text

        text = text.strip()

        if text.startswith("```"):
            first_newline = text.index("\n")
            text = text[first_newline + 1:]
        if text.endswith("```"):
            text = text[:-3]

        return text.strip()
