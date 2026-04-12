"""NPC and character schemas.

Defines non-player characters with personality, relationships, schedules,
combat stats, and dialogue hooks.
"""

from __future__ import annotations

from enum import Enum

from pydantic import BaseModel, Field


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------


class NPCRole(str, Enum):
    """Functional roles an NPC can serve."""
    QUEST_GIVER = "quest_giver"
    MERCHANT = "merchant"
    COMPANION = "companion"
    ENEMY = "enemy"
    BOSS = "boss"
    GUARD = "guard"
    CIVILIAN = "civilian"
    MENTOR = "mentor"
    RIVAL = "rival"
    MYSTERIOUS = "mysterious"


# ---------------------------------------------------------------------------
# Components
# ---------------------------------------------------------------------------


class Personality(BaseModel):
    """Personality profile used to guide dialogue generation."""
    traits: list[str]  # e.g., ["brave", "sarcastic", "loyal"]
    values: list[str]  # e.g., ["honor", "family", "gold"]
    fears: list[str] = Field(default_factory=list)
    quirks: list[str] = Field(default_factory=list)
    speech_pattern: str = "normal"  # e.g., "formal", "slang", "cryptic", "terse"


class Relationship(BaseModel):
    """A directional relationship between two NPCs."""
    target_npc_id: str
    type: str  # friend, rival, family, enemy, mentor, etc.
    trust: int = Field(default=50, ge=0, le=100)
    description: str = ""


class Schedule(BaseModel):
    """NPC daily schedule defining where they are and what they do."""
    entries: list[dict[str, str]] = Field(
        default_factory=list,
        description='E.g., [{"time": "morning", "location": "market", "activity": "selling"}]',
    )


class NPCStats(BaseModel):
    """Basic combat stats for an NPC."""
    level: int = 1
    hp: int = 10
    attack: int = 5
    defense: int = 5
    speed: int = 5
    special_abilities: list[str] = Field(default_factory=list)


# ---------------------------------------------------------------------------
# Top-level NPC
# ---------------------------------------------------------------------------


class NPCDefinition(BaseModel):
    """Full NPC definition — the contract between Narrative and game runtime.

    Includes appearance, personality, stats, dialogue hooks, inventory,
    quests, and ambient barks.
    """
    id: str
    name: str
    role: NPCRole
    description: str
    appearance: str
    personality: Personality
    location_id: str
    stats: NPCStats = Field(default_factory=NPCStats)
    relationships: list[Relationship] = Field(default_factory=list)
    schedule: Schedule | None = None
    dialogue_tree_ids: list[str] = Field(default_factory=list)
    inventory: list[str] = Field(default_factory=list, description="Item IDs")
    quest_ids: list[str] = Field(default_factory=list, description="Quests this NPC gives")
    barks: dict[str, list[str]] = Field(
        default_factory=dict,
        description="situation -> list of bark strings (idle, combat, greeting, etc.)",
    )
    is_essential: bool = False  # Cannot be killed
    faction: str | None = None
