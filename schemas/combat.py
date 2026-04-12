"""Combat, encounter, stat system, art, and QA schemas.

Defines the full combat layer (damage types, abilities, status effects,
encounters), the stat/progression system, art direction specs, and
QA/balance reporting models.
"""

from __future__ import annotations

from enum import Enum

from pydantic import BaseModel, Field


# ---------------------------------------------------------------------------
# Damage & status
# ---------------------------------------------------------------------------


class DamageType(str, Enum):
    """Elemental and physical damage types."""
    PHYSICAL = "physical"
    FIRE = "fire"
    ICE = "ice"
    LIGHTNING = "lightning"
    POISON = "poison"
    HOLY = "holy"
    DARK = "dark"
    PSYCHIC = "psychic"


class StatusEffect(BaseModel):
    """A status effect (buff or debuff) that can be applied in combat."""
    id: str
    name: str
    description: str
    duration_turns: int = 3
    damage_per_turn: int = 0
    stat_modifiers: list[dict[str, object]] = Field(
        default_factory=list,
        description='E.g., [{"stat": "speed", "value": -2}]',
    )
    prevents_action: bool = False


# ---------------------------------------------------------------------------
# Abilities
# ---------------------------------------------------------------------------


class Ability(BaseModel):
    """A combat ability usable by players or enemies."""
    id: str
    name: str
    description: str
    damage_type: DamageType | None = None
    base_damage: int = 0
    scaling_stat: str | None = None
    scaling_factor: float = 1.0
    cost: dict[str, int] = Field(
        default_factory=dict,
        description='Resource cost, e.g., {"mana": 10}',
    )
    cooldown_turns: int = 0
    target: str = "single_enemy"  # single_enemy, all_enemies, self, single_ally, all_allies, aoe
    status_effects: list[str] = Field(
        default_factory=list,
        description="StatusEffect IDs to apply on hit",
    )
    hit_chance_modifier: float = 0.0


# ---------------------------------------------------------------------------
# Enemies & encounters
# ---------------------------------------------------------------------------


class EnemyDefinition(BaseModel):
    """Full enemy definition with stats, resistances, and loot."""
    id: str
    name: str
    description: str
    level: int = 1
    hp: int = 10
    attack: int = 5
    defense: int = 5
    speed: int = 5
    resistances: dict[str, float] = Field(
        default_factory=dict,
        description="DamageType -> multiplier (0.5 = half damage)",
    )
    weaknesses: dict[str, float] = Field(
        default_factory=dict,
        description="DamageType -> multiplier (1.5 = extra damage)",
    )
    abilities: list[str] = Field(default_factory=list, description="Ability IDs")
    loot_table_id: str | None = None
    xp_reward: int = 10
    gold_reward_range: tuple[int, int] = (1, 5)
    is_boss: bool = False
    sprite_description: str = ""


class EnemyPlacement(BaseModel):
    """Placement of an enemy type within an encounter."""
    enemy_id: str
    count: int = 1
    position: str = "front"  # front, back, flanking


class Encounter(BaseModel):
    """A combat encounter at a specific location."""
    id: str
    name: str
    description: str
    location_id: str
    difficulty: int = Field(ge=1, le=10)
    enemies: list[EnemyPlacement]
    is_boss_fight: bool = False
    ambush: bool = False
    escape_difficulty: int = 5
    terrain_effects: list[str] = Field(default_factory=list)
    pre_battle_dialogue: str | None = None
    post_battle_dialogue: str | None = None
    rewards_override: dict[str, object] | None = None


# ---------------------------------------------------------------------------
# Stat & progression system
# ---------------------------------------------------------------------------


class Stat(BaseModel):
    """Definition of a single character stat."""
    name: str
    abbreviation: str
    description: str
    base_value: int = 10
    min_value: int = 1
    max_value: int = 99
    growth_rate: float = 1.0  # Per-level scaling


class DerivedStat(BaseModel):
    """A stat computed from one or more base stats."""
    name: str
    formula: str  # e.g., "hp = con * 10 + level * 5"
    base_stats: list[str]  # Stats it depends on


class StatSystem(BaseModel):
    """The complete stat and levelling system for the game."""
    stats: list[Stat]
    derived_stats: list[DerivedStat] = Field(default_factory=list)
    level_cap: int = 50
    xp_curve: str = "exponential"  # linear, exponential, custom
    xp_base: int = 100  # XP required for level 2
    xp_factor: float = 1.5  # Multiplier per level for exponential curve


class CombatSystem(BaseModel):
    """Top-level combat system configuration."""
    turn_order: str = "speed_based"  # speed_based, round_robin, atb
    actions_per_turn: int = 1
    base_hit_chance: float = 0.85
    critical_hit_chance: float = 0.1
    critical_hit_multiplier: float = 1.5
    damage_formula: str = "attack * scaling - defense * 0.5"
    healing_formula: str = "magic * scaling"
    status_effects: list[StatusEffect] = Field(default_factory=list)
    abilities: list[Ability] = Field(default_factory=list)
    max_party_size: int = 4
    flee_base_chance: float = 0.5


# ---------------------------------------------------------------------------
# Art direction
# ---------------------------------------------------------------------------


class StyleGuide(BaseModel):
    """Visual style guide for consistent art direction."""
    art_style: str  # e.g., "16-bit pixel art", "hand-drawn watercolor"
    color_palette: list[str]  # Hex color codes
    mood: str
    reference_games: list[str] = Field(default_factory=list)
    line_weight: str = "medium"
    texture_style: str = "clean"
    lighting: str = "warm"


class TilesetDescription(BaseModel):
    """Description of a tileset for image generation."""
    biome: str
    tile_size: int = 16
    tiles: dict[str, str]  # tile_name -> visual description for image gen


class CharacterArtDescription(BaseModel):
    """Art generation spec for a character."""
    npc_id: str
    portrait_description: str
    sprite_description: str
    expression_descriptions: dict[str, str] = Field(
        default_factory=dict,
        description="emotion -> visual description",
    )


class UIArtDescription(BaseModel):
    """Art generation spec for UI elements."""
    theme: str
    elements: dict[str, str]  # element_name -> visual description


# ---------------------------------------------------------------------------
# QA & balance
# ---------------------------------------------------------------------------


class QAIssue(BaseModel):
    """A single issue found during QA review."""
    severity: str  # critical, warning, suggestion
    category: str  # balance, narrative, level_design, softlock, missing_reference
    description: str
    location: str = ""  # Where in the game
    suggested_fix: str = ""


class QAReport(BaseModel):
    """Full QA playtest report."""
    project_id: str
    issues: list[QAIssue] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)
    suggestions: list[str] = Field(default_factory=list)
    overall_score: int = Field(default=5, ge=1, le=10)
    playable: bool = True
    summary: str = ""


class BalanceReport(BaseModel):
    """Balance analysis report for tuning game difficulty."""
    power_curve_assessment: str
    difficulty_spikes: list[str] = Field(default_factory=list)
    undertuned_items: list[str] = Field(default_factory=list)
    overtuned_items: list[str] = Field(default_factory=list)
    recommendations: list[str] = Field(default_factory=list)
    score: int = Field(default=5, ge=1, le=10)
