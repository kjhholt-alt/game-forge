"""Project-level schemas.

GameConcept captures the high-level game design document. GameProject is the
top-level aggregate that holds everything a GameForge run produces.
"""

from __future__ import annotations

from enum import Enum

from pydantic import BaseModel, Field

from schemas.combat import CombatSystem, Encounter, QAReport, StatSystem, StyleGuide
from schemas.item import ItemDefinition
from schemas.npc import NPCDefinition
from schemas.quest import Quest
from schemas.world import WorldDefinition


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------


class GameGenre(str, Enum):
    """Supported game genres."""
    RPG = "rpg"
    ROGUELIKE = "roguelike"
    PLATFORMER = "platformer"
    PUZZLE = "puzzle"
    STRATEGY = "strategy"
    ADVENTURE = "adventure"


# ---------------------------------------------------------------------------
# Concept
# ---------------------------------------------------------------------------


class GameConcept(BaseModel):
    """High-level game design document produced by the Director agent."""
    title: str
    genre: GameGenre
    setting: str
    core_mechanics: list[str]
    art_style: str
    target_mood: str
    player_count: int = 1
    estimated_playtime_hours: float = 10.0
    description: str = ""
    unique_selling_points: list[str] = Field(default_factory=list)


# ---------------------------------------------------------------------------
# Project aggregate
# ---------------------------------------------------------------------------


class GameProject(BaseModel):
    """Complete game project -- the final output of a GameForge run.

    Aggregates every piece of generated content: world, quests, NPCs, items,
    encounters, combat/stat systems, art specs, generated file paths, and QA.
    """
    id: str
    concept: GameConcept
    world: WorldDefinition | None = None
    quests: list[Quest] = Field(default_factory=list)
    npcs: list[NPCDefinition] = Field(default_factory=list)
    items: list[ItemDefinition] = Field(default_factory=list)
    encounters: list[Encounter] = Field(default_factory=list)
    stat_system: StatSystem | None = None
    combat_system: CombatSystem | None = None
    style_guide: StyleGuide | None = None
    scenes_generated: list[str] = Field(default_factory=list)
    scripts_generated: list[str] = Field(default_factory=list)
    qa_report: QAReport | None = None
    created_at: str = ""  # ISO timestamp
    updated_at: str = ""
