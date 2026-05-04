"""MechanicsEngine agent -- designs and balances game mechanics.

Uses Claude Haiku for fast iteration on stats, combat rules, progression
curves, items, and encounter balance.  Haiku is chosen for this role because
balance tuning requires many rapid iterations rather than deep creative
generation, and the output is primarily numeric/formulaic.
"""

from __future__ import annotations

import json
import logging
from typing import Any

import claudex_anthropic_shim as anthropic  # Max-sub via claudex; no API key

from schemas.combat import (
    Ability,
    BalanceReport,
    CombatSystem,
    DamageType,
    DerivedStat,
    Encounter,
    EnemyDefinition,
    EnemyPlacement,
    Stat,
    StatSystem,
    StatusEffect,
)
from schemas.item import (
    ItemCategory,
    ItemDefinition,
    ItemRarity,
    LootTable,
    LootTableEntry,
    StatModifier,
)
from schemas.project import GameConcept

logger = logging.getLogger(__name__)


class MechanicsEngine:
    """Designs and balances game mechanics: stats, combat, progression, items, encounters.

    Every public method makes one or more Claude API calls with a game-balance-focused
    system prompt and returns validated Pydantic models from ``schemas.combat`` and
    ``schemas.item``.
    """

    SYSTEM_PROMPT: str = """\
You are an expert **game balance designer and systems programmer** working inside
GameForge, an AI-powered game development toolkit that outputs 2-D Godot projects.

Your sole job is to design and balance the mechanical layer of games: stat systems,
combat formulas, item tables, encounter tuning, and progression curves.  You think
in spreadsheets, damage-per-second calculations, and power budgets.

Balance principles you MUST follow:
1. **Power curves** -- player power should grow in a satisfying curve.  Early
   levels should feel impactful (big relative jumps), while high levels provide
   incremental mastery.  Avoid flat spots where leveling feels meaningless.
2. **Risk vs. reward** -- harder content must drop better loot.  A difficulty-10
   dungeon boss that drops common-tier items feels terrible.  Conversely,
   trivial content should not shower the player with epics.
3. **No one-shots** -- no enemy should be able to kill a same-level player in a
   single hit from full health under normal circumstances.  Boss attacks can
   deal 40-60% max HP at most.  Avoidable/telegraphed attacks can deal more.
4. **Player agency** -- every stat point investment should have a noticeable
   effect on gameplay.  Avoid dump stats that do nothing useful.  Every
   stat should benefit at least two derived stats or combat formulas.
5. **Counter-play** -- every strong strategy should have a counter.  High-armor
   builds should be vulnerable to magic.  Glass-cannon builds should fear
   status effects.  This creates meaningful gear/build decisions.
6. **Economy sanity** -- item buy prices should be ~4x sell prices.  Gold
   rewards from quests should let players afford gear upgrades every 3-5
   levels.  Consumable costs should be low enough that players use them.
7. **Stat scaling** -- use clear, predictable formulas.  Document every formula
   as a string so downstream systems can evaluate them.  Avoid magic numbers;
   prefer formulas that reference named stats.
8. **Internal consistency** -- a level-5 sword should always be weaker than a
   level-8 sword of the same rarity.  Item stat budgets per tier must be
   monotonically increasing.  No exceptions.
9. **Encounter design** -- encounters should test different skills.  Mix melee,
   ranged, and status-effect enemies.  Boss encounters should have phases
   that change the tactical situation.
10. **Avoid unfun patterns** -- no unavoidable instant-death, no
    mandatory grinding, no encounters that require one specific build to win.

Output rules:
- Respond ONLY with the requested JSON object -- no commentary, no markdown fences.
- Every ``id`` field must be a unique, URL-safe slug (lowercase, hyphens).
- All formulas should be written as evaluable Python-like expressions using
  stat names as variables (e.g., "attack * 1.2 - defense * 0.5").
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

    async def design_stat_system(self, concept: GameConcept) -> StatSystem:
        """Design the core stat system (attributes, derived stats, scaling curves).

        Returns a StatSystem with primary stats, derived stats, level cap,
        and experience curve parameters.
        """
        schema = StatSystem.model_json_schema()

        user_msg = (
            f"Design a stat system for this game concept:\n\n"
            f"{concept.model_dump_json(indent=2)}\n\n"
            f"Requirements:\n"
            f"- 4-6 primary stats appropriate for the genre (e.g., STR, DEX, INT)\n"
            f"- 3-5 derived stats computed from primaries (HP, MP, crit chance, etc.)\n"
            f"- Every primary stat should affect at least 2 derived stats\n"
            f"- No dump stats -- every stat should matter for at least one playstyle\n"
            f"- Include growth_rate per stat (how much it increases per level)\n"
            f"- Set a level cap appropriate for the estimated_playtime\n"
            f"- Define the XP curve formula (xp_base, xp_factor)\n"
            f"- All formulas must be Python-evaluable strings\n\n"
            f"Respond with a JSON object matching this schema:\n"
            f"{json.dumps(schema, indent=2)}"
        )

        raw = await self._call(user_msg)
        return StatSystem.model_validate(raw)

    async def design_combat_system(
        self,
        concept: GameConcept,
        stat_system: StatSystem,
    ) -> CombatSystem:
        """Design combat rules: turn order, actions, damage formulas, status effects.

        Returns a CombatSystem with all combat rules, abilities, and
        status effects defined.
        """
        schema = CombatSystem.model_json_schema()

        user_msg = (
            f"Design a combat system for this game:\n\n"
            f"Concept:\n{concept.model_dump_json(indent=2)}\n\n"
            f"Stat system:\n{stat_system.model_dump_json(indent=2)}\n\n"
            f"Requirements:\n"
            f"- Turn order based on the stat system's speed-equivalent stat\n"
            f"- 8-15 combat abilities spanning melee, ranged, magic, and support\n"
            f"- Damage formula that references actual stat names from the stat system\n"
            f"- 4-8 status effects (poison, stun, buff, debuff, etc.)\n"
            f"- Critical hit system with chance and multiplier\n"
            f"- Flee mechanic with a formula\n"
            f"- Resource costs (mana/stamina) for abilities to prevent spamming\n"
            f"- Healing formula for recovery abilities\n"
            f"- Every ability should have a clear use case -- no strictly-worse options\n\n"
            f"Respond with a JSON object matching this schema:\n"
            f"{json.dumps(schema, indent=2)}"
        )

        raw = await self._call(user_msg)
        return CombatSystem.model_validate(raw)

    async def generate_item_table(
        self,
        tier: int,
        count: int,
        stat_system: StatSystem,
    ) -> list[ItemDefinition]:
        """Generate a balanced item table for a given tier.

        Parameters
        ----------
        tier:
            Power tier 1-5 (maps to rarity: common through legendary).
        count:
            Number of items to generate.
        stat_system:
            The stat system to reference for stat modifiers.
        """
        schema = ItemDefinition.model_json_schema()
        rarity_map = {
            1: "common",
            2: "uncommon",
            3: "rare",
            4: "epic",
            5: "legendary",
        }
        target_rarity = rarity_map.get(tier, "common")

        stat_names = [s.name for s in stat_system.stats]

        user_msg = (
            f"Generate {count} items at tier {tier} ({target_rarity} rarity):\n\n"
            f"Stat system stats: {json.dumps(stat_names)}\n\n"
            f"Requirements:\n"
            f"- Mix of categories: weapons, armor, accessories, consumables\n"
            f"- Stat modifiers should reference actual stat names: {json.dumps(stat_names)}\n"
            f"- Stat budgets: tier 1 = 3-5 total stat points, tier 2 = 6-10,\n"
            f"  tier 3 = 11-18, tier 4 = 19-30, tier 5 = 31-50\n"
            f"- Value should scale with tier: tier 1 = 10-50g, tier 2 = 50-200g,\n"
            f"  tier 3 = 200-800g, tier 4 = 800-3000g, tier 5 = 3000-10000g\n"
            f"- Sell value should be ~25% of buy value\n"
            f"- Weapons need damage_range tuples\n"
            f"- Armor needs armor_value\n"
            f"- Consumables should be stackable with clear effects\n"
            f"- Level requirements: tier 1 = 1-5, tier 2 = 5-15, tier 3 = 15-25,\n"
            f"  tier 4 = 25-35, tier 5 = 35-50\n"
            f"- Include lore_text flavor for rare+ items\n"
            f"- Include icon_description for art generation\n\n"
            f"Respond with a JSON object: {{\"items\": [...]}} where each item "
            f"matches this schema:\n{json.dumps(schema, indent=2)}"
        )

        raw = await self._call(user_msg)
        items_raw = raw.get("items", raw) if isinstance(raw, dict) else raw
        if isinstance(items_raw, list):
            return [ItemDefinition.model_validate(i) for i in items_raw]
        return []

    async def generate_encounter(
        self,
        difficulty: int,
        party_level: int,
        location: str,
    ) -> Encounter:
        """Generate a balanced encounter (enemies, formations, rewards).

        Parameters
        ----------
        difficulty:
            1-10 difficulty rating.
        party_level:
            Expected player party level.
        location:
            Location ID where the encounter takes place.
        """
        schema = Encounter.model_json_schema()
        enemy_schema = EnemyDefinition.model_json_schema()

        user_msg = (
            f"Generate a combat encounter:\n\n"
            f"- Difficulty: {difficulty}/10\n"
            f"- Party level: {party_level}\n"
            f"- Location ID: {location}\n\n"
            f"Requirements:\n"
            f"- 1-5 enemy types with stats appropriate for the difficulty and party level\n"
            f"- Enemy HP should scale: ~(10 + party_level * 5) for normal, ~3x for bosses\n"
            f"- Include enemy placement positions (front, back, flanking)\n"
            f"- At difficulty 8+ include a boss enemy\n"
            f"- Mix melee and ranged enemies for tactical variety\n"
            f"- Include terrain_effects if the location suggests hazards\n"
            f"- XP and gold rewards proportional to difficulty\n"
            f"- Boss encounters should have pre_battle_dialogue\n"
            f"- Set escape_difficulty based on encounter difficulty\n\n"
            f"Enemy schema:\n{json.dumps(enemy_schema, indent=2)}\n\n"
            f"Respond with a JSON object matching this schema:\n"
            f"{json.dumps(schema, indent=2)}"
        )

        raw = await self._call(user_msg)
        return Encounter.model_validate(raw)

    async def balance_check(
        self,
        stat_system: StatSystem,
        items: list[ItemDefinition],
        encounters: list[Encounter],
    ) -> BalanceReport:
        """Run a balance analysis on current game data.

        Analyzes power curves, difficulty spikes, item tuning, and economy
        health.  Returns a BalanceReport with issues and recommendations.
        """
        schema = BalanceReport.model_json_schema()

        user_msg = (
            f"Perform a balance analysis on this game data:\n\n"
            f"Stat system:\n{stat_system.model_dump_json(indent=2)}\n\n"
            f"Items ({len(items)} total):\n"
            f"{json.dumps([i.model_dump(mode='json') for i in items], indent=2)}\n\n"
            f"Encounters ({len(encounters)} total):\n"
            f"{json.dumps([e.model_dump(mode='json') for e in encounters], indent=2)}\n\n"
            f"Analyze the following aspects:\n"
            f"1. Power curve: Do stats scale smoothly across levels?\n"
            f"2. Difficulty spikes: Are there sudden jumps in encounter difficulty?\n"
            f"3. Item balance: Are any items over/under-tuned for their tier?\n"
            f"4. Economy: Are gold rewards sufficient for gear progression?\n"
            f"5. Stat relevance: Are there any stats that don't matter?\n"
            f"6. Counter-play: Can every enemy type be handled by multiple strategies?\n\n"
            f"Respond with a JSON object matching this schema:\n"
            f"{json.dumps(schema, indent=2)}"
        )

        raw = await self._call(user_msg)
        return BalanceReport.model_validate(raw)

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
                    "MechanicsEngine API call attempt %d/%d (model=%s)",
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
                logger.info("MechanicsEngine call succeeded on attempt %d", attempt)
                return parsed  # type: ignore[no-any-return]

            except json.JSONDecodeError as exc:
                logger.warning(
                    "MechanicsEngine attempt %d/%d: invalid JSON -- %s",
                    attempt, max_retries, exc,
                )
                last_error = exc

            except anthropic.APIStatusError as exc:
                logger.warning(
                    "MechanicsEngine attempt %d/%d: API status error %d -- %s",
                    attempt, max_retries, exc.status_code, exc.message,
                )
                last_error = exc
                if exc.status_code == 401:
                    raise

            except anthropic.APIConnectionError as exc:
                logger.warning(
                    "MechanicsEngine attempt %d/%d: connection error -- %s",
                    attempt, max_retries, exc,
                )
                last_error = exc

        raise RuntimeError(
            f"MechanicsEngine failed after {max_retries} attempts. Last error: {last_error}"
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
