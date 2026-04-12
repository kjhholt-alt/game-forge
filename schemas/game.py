"""Legacy / simplified game schemas.

This module preserves the original flat model definitions used by early
GameForge prototypes and the test fixtures.  Production code should prefer
the detailed schema modules (``schemas.world``, ``schemas.quest``,
``schemas.npc``, ``schemas.item``, ``schemas.combat``, ``schemas.project``).

The models here are intentionally simpler and are used for:
- Test fixtures in ``tests/conftest.py``
- Quick prototyping without the full schema hierarchy
- Backwards-compatible ``GameProject`` for the ``forge.py`` facade
"""

from __future__ import annotations

from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

class ItemType(str, Enum):
    """Categories of in-game items."""
    WEAPON = "weapon"
    ARMOR = "armor"
    CONSUMABLE = "consumable"
    KEY_ITEM = "key_item"
    MATERIAL = "material"
    CURRENCY = "currency"
    ACCESSORY = "accessory"


class QuestType(str, Enum):
    """Quest archetypes."""
    MAIN = "main"
    SIDE = "side"
    FETCH = "fetch"
    ESCORT = "escort"
    KILL = "kill"
    EXPLORE = "explore"
    PUZZLE = "puzzle"
    BOSS = "boss"


class NPCDisposition(str, Enum):
    """Starting relationship toward the player."""
    FRIENDLY = "friendly"
    NEUTRAL = "neutral"
    HOSTILE = "hostile"
    MERCHANT = "merchant"
    QUEST_GIVER = "quest_giver"


class IssueSeverity(str, Enum):
    """QA issue severity levels."""
    CRITICAL = "critical"
    MAJOR = "major"
    MINOR = "minor"
    SUGGESTION = "suggestion"


# ---------------------------------------------------------------------------
# World
# ---------------------------------------------------------------------------

class Region(BaseModel):
    """A distinct area within the game world."""
    name: str
    description: str
    biome: str = Field(description="Visual/environmental theme (e.g. forest, cave, desert)")
    connections: list[str] = Field(
        default_factory=list,
        description="Names of regions this area connects to",
    )
    points_of_interest: list[str] = Field(default_factory=list)
    enemy_types: list[str] = Field(default_factory=list)
    level_range: tuple[int, int] = Field(
        default=(1, 5),
        description="Recommended player level range (min, max)",
    )


class WorldDefinition(BaseModel):
    """Complete world structure produced by the WorldBuilder agent."""
    name: str = Field(description="Name of the game world")
    description: str = Field(description="High-level world lore summary")
    regions: list[Region] = Field(default_factory=list)
    factions: list[str] = Field(default_factory=list)
    history_summary: str = Field(
        default="",
        description="Brief history / backstory of the world",
    )
    themes: list[str] = Field(
        default_factory=list,
        description="Narrative themes (e.g. redemption, survival)",
    )


# ---------------------------------------------------------------------------
# NPCs & Dialogue
# ---------------------------------------------------------------------------

class DialogueLine(BaseModel):
    """A single line of dialogue."""
    speaker: str
    text: str
    emotion: str = "neutral"


class DialogueNode(BaseModel):
    """A dialogue tree node with optional player choices."""
    id: str
    lines: list[DialogueLine]
    choices: list[dict[str, str]] = Field(
        default_factory=list,
        description="List of {text: str, next_node_id: str} player options",
    )


class NPC(BaseModel):
    """A non-player character definition."""
    name: str
    role: str = Field(description="Narrative role (e.g. blacksmith, sage, villain)")
    description: str
    disposition: NPCDisposition = NPCDisposition.NEUTRAL
    location: str = Field(default="", description="Region or area name where the NPC resides")
    dialogue: list[DialogueNode] = Field(default_factory=list)
    stats: dict[str, int] = Field(
        default_factory=dict,
        description="Optional combat or skill stats",
    )


# ---------------------------------------------------------------------------
# Items
# ---------------------------------------------------------------------------

class Item(BaseModel):
    """An in-game item."""
    name: str
    item_type: ItemType
    description: str
    rarity: str = "common"
    value: int = Field(default=0, description="Base gold / currency value")
    stats: dict[str, int] = Field(
        default_factory=dict,
        description="Stat modifiers (e.g. {attack: 5, defense: 2})",
    )
    effects: list[str] = Field(
        default_factory=list,
        description="Special effects or abilities",
    )


# ---------------------------------------------------------------------------
# Quests
# ---------------------------------------------------------------------------

class QuestObjective(BaseModel):
    """A single step within a quest."""
    description: str
    objective_type: str = "generic"
    target: str = Field(default="", description="NPC/item/location this objective refers to")
    quantity: int = 1
    optional: bool = False


class Quest(BaseModel):
    """A quest or mission definition."""
    name: str
    quest_type: QuestType
    description: str
    giver: str = Field(default="", description="NPC name who gives the quest")
    region: str = Field(default="", description="Primary region for this quest")
    objectives: list[QuestObjective] = Field(default_factory=list)
    rewards: list[str] = Field(
        default_factory=list,
        description="Item names or reward descriptions",
    )
    prerequisites: list[str] = Field(
        default_factory=list,
        description="Quest names that must be completed first",
    )
    level_requirement: int = 1


# ---------------------------------------------------------------------------
# Art / Assets
# ---------------------------------------------------------------------------

class ArtAssetSpec(BaseModel):
    """Specification for a visual asset to be generated."""
    name: str
    asset_type: str = Field(description="sprite, tileset, portrait, background, ui_element")
    description: str = Field(description="Detailed visual description for generation")
    dimensions: tuple[int, int] = (64, 64)
    style_notes: str = ""
    priority: str = "normal"


# ---------------------------------------------------------------------------
# QA
# ---------------------------------------------------------------------------

class QAIssue(BaseModel):
    """A single issue found during QA testing."""
    severity: IssueSeverity
    category: str = Field(description="e.g. balance, narrative, mechanics, art, ux")
    description: str
    suggested_fix: str = ""
    affected_entity: str = Field(
        default="",
        description="Name of the quest/NPC/item/region affected",
    )


class QAReport(BaseModel):
    """Full QA playtest report."""
    overall_score: float = Field(ge=0.0, le=10.0, description="Quality score 0-10")
    summary: str
    issues: list[QAIssue] = Field(default_factory=list)
    strengths: list[str] = Field(default_factory=list)
    passed: bool = Field(
        default=False,
        description="True if the game meets minimum quality bar",
    )


# ---------------------------------------------------------------------------
# Top-level aggregates
# ---------------------------------------------------------------------------

class GameConcept(BaseModel):
    """High-level game design document produced by the Director."""
    title: str
    genre: str
    setting: str = Field(description="World setting description")
    core_mechanics: list[str] = Field(
        description="List of primary gameplay mechanics",
    )
    art_style: str = Field(description="Visual style direction")
    target_mood: str = Field(description="Emotional tone (e.g. dark, whimsical, tense)")
    player_count: int = Field(default=1, description="Number of simultaneous players")
    estimated_playtime: str = Field(
        default="1-2 hours",
        description="Estimated playtime for a full run",
    )


class GameProject(BaseModel):
    """Complete game project -- the final output of a GameForge run."""
    concept: GameConcept
    world: Optional[WorldDefinition] = None
    quests: list[Quest] = Field(default_factory=list)
    npcs: list[NPC] = Field(default_factory=list)
    items: list[Item] = Field(default_factory=list)
    art_specs: list[ArtAssetSpec] = Field(default_factory=list)
    scenes_generated: list[str] = Field(
        default_factory=list,
        description="Paths to generated Godot .tscn files",
    )
    scripts_generated: list[str] = Field(
        default_factory=list,
        description="Paths to generated GDScript files",
    )
    qa_report: Optional[QAReport] = None
