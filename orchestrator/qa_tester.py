"""QATester agent -- simulates playtesting by analyzing game content for issues.

Uses Claude Haiku for fast, thorough analysis of game content across
multiple dimensions: softlocks, balance, narrative consistency, reference
integrity, and overall completeness.  Haiku is chosen because QA review
requires checking many small things quickly rather than deep generation.
"""

from __future__ import annotations

import json
import logging
import uuid
from typing import Any

import claudex_anthropic_shim as anthropic  # Max-sub via claudex; no API key

from schemas.combat import (
    BalanceReport,
    CombatSystem,
    Encounter,
    QAIssue,
    QAReport,
)
from schemas.item import ItemDefinition
from schemas.npc import NPCDefinition
from schemas.project import GameProject
from schemas.quest import Quest
from schemas.world import DungeonLayout

logger = logging.getLogger(__name__)


class QATester:
    """Simulates playtesting by analyzing game content for issues.

    Every public method makes one or more Claude API calls with a QA-focused
    system prompt and returns validated ``QAReport`` models with issues,
    warnings, suggestions, and an overall quality score.
    """

    SYSTEM_PROMPT: str = """\
You are an expert **QA analyst and game tester** working inside GameForge,
an AI-powered game development toolkit that outputs 2-D Godot projects.

Your sole job is to find problems.  You simulate a player walking through
the game content and flag everything that would cause a bad experience:
softlocks, dead ends, plot holes, balance spikes, broken references,
missing content, and unfun patterns.

You are not a cheerleader.  You are the last line of defense before the
game reaches players.  Be thorough, be specific, be honest.

QA principles you MUST follow:
1. **Softlock detection** -- if a player can reach a state where progress
   is impossible (missing key, unreachable area, circular dependency),
   that is a CRITICAL issue.  Check every locked connection has a
   reachable key.  Check every quest prerequisite chain is completable.
2. **Dead end detection** -- rooms, dialogue branches, or quest paths that
   lead nowhere are HIGH severity.  Every path should either loop back,
   lead forward, or explicitly end.
3. **Reference integrity** -- every ID referenced (NPC ID in a quest,
   location ID in a dialogue, item ID in a loot table) must actually
   exist in the project data.  Missing references are HIGH severity.
4. **Balance analysis** -- check damage numbers, HP pools, reward values,
   and XP curves for spikes and valleys.  A level-5 area with level-20
   enemies is a balance issue.  A quest that rewards 10 XP when the next
   level requires 10,000 is a balance issue.
5. **Narrative consistency** -- NPCs should not contradict themselves or
   each other (unless intentionally unreliable).  Quest descriptions
   should match their objectives.  Lore should form a coherent timeline.
6. **Pacing review** -- flag sequences of 4+ combat encounters without a
   rest point.  Flag quest chains where 3+ objectives are the same type
   in a row.  Flag regions where the player has nothing to do.
7. **Completeness check** -- every region should have at least one quest.
   Every quest should have rewards.  Every NPC should have dialogue.
   Missing content is MEDIUM severity.
8. **Player experience** -- think like a real player.  Would this be
   confusing?  Would this feel unfair?  Would the player know where to
   go next?  Flag UX issues as suggestions.
9. **Economy health** -- can the player afford necessary items at each
   progression point?  Are gold sinks balanced against gold sources?
   Is there a reason to visit shops?
10. **Scoring rubric** -- assign a score 1-10:
    - 1-3: Fundamentally broken, multiple softlocks or critical issues
    - 4-5: Playable but significant issues that harm the experience
    - 6-7: Solid with room for improvement, no critical issues
    - 8-9: Polished, only minor suggestions remain
    - 10: Exceptional, publication-ready

Set ``playable`` to true ONLY if:
- Zero critical issues
- Zero high-severity softlock issues
- Overall score >= 6

Output rules:
- Respond ONLY with the requested JSON object -- no commentary, no markdown fences.
- Every issue needs: severity, category, description, location, and suggested_fix.
- Categories: softlock, balance, narrative, reference, completeness, pacing, ux, economy.
- Be specific: name the exact IDs, locations, and values involved.
- Use the schemas provided in each prompt exactly; do not invent extra fields.
"""

    # ------------------------------------------------------------------
    # Construction
    # ------------------------------------------------------------------

    def __init__(self, client: anthropic.AsyncAnthropic, model: str = "claude-haiku-4-5") -> None:
        self._client = client
        self._model = model

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    async def playtest_dungeon(
        self,
        dungeon: DungeonLayout,
        mechanics: CombatSystem,
    ) -> QAReport:
        """Simulate a player run through a dungeon.

        Checks for softlocks, difficulty spikes, dead ends, pacing issues,
        and verifies that the dungeon is completable from entrance to exit
        and from entrance to boss.
        """
        qa_schema = QAReport.model_json_schema()

        user_msg = (
            f"Playtest this dungeon and report issues:\n\n"
            f"Dungeon:\n{dungeon.model_dump_json(indent=2)}\n\n"
            f"Combat system:\n{mechanics.model_dump_json(indent=2)}\n\n"
            f"Simulate a player run and check:\n"
            f"1. Can the player reach the exit from the entrance? Trace all paths.\n"
            f"2. Can the player reach the boss room? Is there a path back if they need to retreat?\n"
            f"3. Are there any rooms with no outgoing connections (dead ends without purpose)?\n"
            f"4. Are locked connections matchable to keys/items in preceding rooms?\n"
            f"5. Does difficulty escalate smoothly toward the boss, or are there spikes?\n"
            f"6. Are there rest points between difficult sequences (safe rooms)?\n"
            f"7. Is loot placed to reward exploration of side paths?\n"
            f"8. Are puzzle rooms solvable with available information?\n"
            f"9. Is the estimated clear time realistic given room count and encounter density?\n"
            f"10. Would a player know where to go next at each junction?\n\n"
            f"Set report_type to 'dungeon'. Set project_id to '{dungeon.id}'.\n\n"
            f"Respond with a JSON object matching this schema:\n"
            f"{json.dumps(qa_schema, indent=2)}"
        )

        raw = await self._call(user_msg)
        return QAReport.model_validate(raw)

    async def review_balance(
        self,
        encounters: list[Encounter],
        items: list[ItemDefinition],
    ) -> QAReport:
        """Review encounters and items for balance issues.

        Checks damage curves, HP pools, item tier consistency, reward
        proportionality, and economy health.
        """
        qa_schema = QAReport.model_json_schema()

        user_msg = (
            f"Review game balance for these encounters and items:\n\n"
            f"Encounters ({len(encounters)}):\n"
            f"{json.dumps([e.model_dump(mode='json') for e in encounters], indent=2)}\n\n"
            f"Items ({len(items)}):\n"
            f"{json.dumps([i.model_dump(mode='json') for i in items], indent=2)}\n\n"
            f"Check for:\n"
            f"1. Difficulty spikes: encounters that are dramatically harder than adjacent ones\n"
            f"2. Stat consistency: do enemy stats scale smoothly with difficulty?\n"
            f"3. Reward proportionality: harder encounters should give better rewards\n"
            f"4. Item tier integrity: higher-tier items must be strictly better than lower\n"
            f"5. Economy: can players afford gear upgrades at each progression point?\n"
            f"6. One-shot potential: can any enemy kill a same-level player in one hit?\n"
            f"7. Useless items: are there items no player would ever want?\n"
            f"8. Counter-play: is every enemy beatable by multiple strategies?\n\n"
            f"Set report_type to 'balance'. Set project_id to 'balance-review'.\n\n"
            f"Respond with a JSON object matching this schema:\n"
            f"{json.dumps(qa_schema, indent=2)}"
        )

        raw = await self._call(user_msg)
        return QAReport.model_validate(raw)

    async def review_narrative(
        self,
        quests: list[Quest],
        npcs: list[NPCDefinition],
    ) -> QAReport:
        """Check narrative for plot holes, inconsistencies, dead references.

        Reviews quest chains for circular dependencies, NPC personality
        consistency, dialogue completeness, and narrative coherence.
        """
        qa_schema = QAReport.model_json_schema()

        user_msg = (
            f"Review the narrative content for issues:\n\n"
            f"Quests ({len(quests)}):\n"
            f"{json.dumps([q.model_dump(mode='json') for q in quests], indent=2)}\n\n"
            f"NPCs ({len(npcs)}):\n"
            f"{json.dumps([n.model_dump(mode='json') for n in npcs], indent=2)}\n\n"
            f"Check for:\n"
            f"1. Circular quest dependencies: A requires B which requires A\n"
            f"2. Orphan quests: quests with prerequisites that don't exist\n"
            f"3. NPC consistency: do NPCs contradict themselves?\n"
            f"4. Quest-NPC linkage: do quest givers actually exist in the NPC list?\n"
            f"5. Location references: do quest locations exist?\n"
            f"6. Dialogue completeness: do quest-giver NPCs have dialogue trees?\n"
            f"7. Narrative pacing: is the main story structured well?\n"
            f"8. Objective variety: are there too many identical objective types in a row?\n"
            f"9. Reward variety: do quest rewards feel meaningful and varied?\n"
            f"10. NPC purpose: does every NPC serve a narrative function?\n\n"
            f"Set report_type to 'narrative'. Set project_id to 'narrative-review'.\n\n"
            f"Respond with a JSON object matching this schema:\n"
            f"{json.dumps(qa_schema, indent=2)}"
        )

        raw = await self._call(user_msg)
        return QAReport.model_validate(raw)

    async def review_completeness(self, project: GameProject) -> QAReport:
        """Check that all pieces fit together.

        Verifies that every referenced ID exists: locations referenced in
        quests exist in the world, NPCs referenced in quests exist in the
        NPC list, items referenced in loot tables exist in the item list, etc.
        """
        qa_schema = QAReport.model_json_schema()

        user_msg = (
            f"Perform a completeness review of this game project:\n\n"
            f"{project.model_dump_json(indent=2)}\n\n"
            f"Check ALL cross-references:\n"
            f"1. Every quest's location_id exists in world regions/rooms\n"
            f"2. Every quest's quest_giver_npc_id exists in the NPC list\n"
            f"3. Every quest prerequisite references an existing quest\n"
            f"4. Every NPC's location_id exists in world regions/rooms\n"
            f"5. Every NPC's inventory item IDs exist in the item list\n"
            f"6. Every encounter's location_id exists in world regions/rooms\n"
            f"7. Every encounter's enemy ability IDs exist in the combat system\n"
            f"8. Every room's entity references exist (NPCs, items, enemies)\n"
            f"9. Every connection's target_id exists as a room or region\n"
            f"10. Every region has at least one quest and one NPC\n"
            f"11. The world has a viable critical path from start to end\n"
            f"12. Art specs cover all major characters and biomes\n\n"
            f"Set report_type to 'completeness'. Set project_id to '{project.id}'.\n\n"
            f"Respond with a JSON object matching this schema:\n"
            f"{json.dumps(qa_schema, indent=2)}"
        )

        raw = await self._call(user_msg)
        return QAReport.model_validate(raw)

    async def full_review(self, project: GameProject) -> QAReport:
        """Run all QA checks and compile a comprehensive report.

        Performs dungeon playtests, balance review, narrative review, and
        completeness check, then merges all findings into a single report
        with a unified score.
        """
        qa_schema = QAReport.model_json_schema()

        user_msg = (
            f"Perform a FULL QA review of this complete game project:\n\n"
            f"{project.model_dump_json(indent=2)}\n\n"
            f"This is a comprehensive review covering ALL dimensions:\n\n"
            f"**Level Design:**\n"
            f"- World connectivity (can player reach all regions?)\n"
            f"- Dungeon completability (entrance to boss to exit)\n"
            f"- Dead ends and softlocks\n"
            f"- Pacing (rest points, difficulty curve)\n\n"
            f"**Balance:**\n"
            f"- Stat scaling across levels\n"
            f"- Encounter difficulty progression\n"
            f"- Item tier consistency\n"
            f"- Economy health (gold sources vs sinks)\n"
            f"- One-shot potential\n\n"
            f"**Narrative:**\n"
            f"- Quest chain integrity (no circular deps)\n"
            f"- Plot coherence and tone consistency\n"
            f"- NPC purpose and characterization\n"
            f"- Dialogue completeness\n\n"
            f"**Completeness:**\n"
            f"- All cross-references resolve to existing entities\n"
            f"- Every region has content (quests, NPCs, encounters)\n"
            f"- Art specs cover necessary assets\n"
            f"- No placeholder or stub content\n\n"
            f"**Player Experience:**\n"
            f"- Clear progression path\n"
            f"- Adequate onboarding\n"
            f"- Fair difficulty\n"
            f"- Satisfying reward loop\n\n"
            f"Score the game holistically (1-10).  Set playable to true only if\n"
            f"there are zero critical issues and the score is >= 6.\n\n"
            f"Set report_type to 'full'. Set project_id to '{project.id}'.\n\n"
            f"Respond with a JSON object matching this schema:\n"
            f"{json.dumps(qa_schema, indent=2)}"
        )

        raw = await self._call(user_msg)
        return QAReport.model_validate(raw)

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    async def _call(self, user_message: str, max_retries: int = 3) -> dict[str, Any]:
        """Make a Claude API call and parse the JSON response.

        Retries on transient API errors and JSON parse failures.
        """
        last_error: Exception | None = None

        for attempt in range(1, max_retries + 1):
            try:
                logger.debug(
                    "QATester API call attempt %d/%d (model=%s)",
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
                logger.info("QATester call succeeded on attempt %d", attempt)
                return parsed  # type: ignore[no-any-return]

            except json.JSONDecodeError as exc:
                logger.warning(
                    "QATester attempt %d/%d: invalid JSON -- %s",
                    attempt, max_retries, exc,
                )
                last_error = exc

            except anthropic.APIStatusError as exc:
                logger.warning(
                    "QATester attempt %d/%d: API status error %d -- %s",
                    attempt, max_retries, exc.status_code, exc.message,
                )
                last_error = exc
                if exc.status_code == 401:
                    raise

            except anthropic.APIConnectionError as exc:
                logger.warning(
                    "QATester attempt %d/%d: connection error -- %s",
                    attempt, max_retries, exc,
                )
                last_error = exc

        raise RuntimeError(
            f"QATester failed after {max_retries} attempts. Last error: {last_error}"
        )

    @staticmethod
    def _extract_text(response: anthropic.types.Message) -> str:
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
