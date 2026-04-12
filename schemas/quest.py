"""Quest and narrative schemas.

Covers the full quest lifecycle: objectives, rewards, branching, dialogue
trees, and discoverable lore entries.
"""

from __future__ import annotations

from enum import Enum

from pydantic import BaseModel, Field


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------


class QuestObjectiveType(str, Enum):
    """Types of objectives a quest can contain."""
    KILL = "kill"
    COLLECT = "collect"
    DELIVER = "deliver"
    ESCORT = "escort"
    EXPLORE = "explore"
    TALK = "talk"
    SOLVE = "solve"
    SURVIVE = "survive"
    CRAFT = "craft"
    DEFEND = "defend"


# ---------------------------------------------------------------------------
# Quest components
# ---------------------------------------------------------------------------


class QuestObjective(BaseModel):
    """A single objective within a quest."""
    id: str
    description: str
    objective_type: QuestObjectiveType
    target: str  # Entity/location ID
    count: int = 1
    optional: bool = False


class QuestReward(BaseModel):
    """Rewards granted on quest completion."""
    xp: int = 0
    gold: int = 0
    items: list[str] = Field(default_factory=list, description="Item IDs")
    reputation: dict[str, int] = Field(
        default_factory=dict,
        description="Faction name -> reputation change",
    )
    unlocks: list[str] = Field(
        default_factory=list,
        description="Quest/area IDs unlocked on completion",
    )


class Quest(BaseModel):
    """A quest or mission definition.

    Supports branching narratives, prerequisite chains, failure conditions,
    and optional time limits.
    """
    id: str
    title: str
    description: str
    quest_giver_npc_id: str | None = None
    location_id: str
    level_requirement: int = 1
    objectives: list[QuestObjective]
    rewards: QuestReward = Field(default_factory=QuestReward)
    prerequisites: list[str] = Field(default_factory=list, description="Quest IDs")
    branches: dict[str, str] = Field(
        default_factory=dict,
        description="choice -> next_quest_id",
    )
    failure_conditions: list[str] = Field(default_factory=list)
    time_limit_turns: int | None = None


class QuestChain(BaseModel):
    """An ordered chain of related quests."""
    id: str
    title: str
    description: str
    quests: list[Quest]
    is_main_story: bool = False


# ---------------------------------------------------------------------------
# Dialogue
# ---------------------------------------------------------------------------


class DialogueOption(BaseModel):
    """A player choice within a dialogue node."""
    text: str
    next_node_id: str | None = None  # None = end conversation
    conditions: dict[str, object] = Field(
        default_factory=dict,
        description="Required flags/stats to show this option",
    )
    effects: dict[str, object] = Field(
        default_factory=dict,
        description="Set flags, give items, change reputation",
    )


class DialogueNode(BaseModel):
    """A single node in a dialogue tree."""
    id: str
    speaker: str  # NPC ID or "player"
    text: str
    emotion: str = "neutral"
    options: list[DialogueOption] = Field(default_factory=list)
    auto_next: str | None = None  # For non-choice (linear) nodes


class DialogueTree(BaseModel):
    """A complete dialogue tree attached to an NPC."""
    id: str
    npc_id: str
    context: str  # When this dialogue triggers (e.g., "first_meeting", "quest_complete")
    root_node_id: str
    nodes: list[DialogueNode]


# ---------------------------------------------------------------------------
# Lore
# ---------------------------------------------------------------------------


class LoreEntry(BaseModel):
    """A discoverable lore entry in the game world."""
    id: str
    title: str
    category: str  # history, faction, legend, item, location
    content: str
    related_entities: list[str] = Field(default_factory=list)
    discoverable: bool = True  # Can the player find this in-game?
    location_hint: str | None = None  # Where to find it
