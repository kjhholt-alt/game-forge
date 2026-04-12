"""World and level structure schemas.

Defines the spatial hierarchy: WorldDefinition > OverworldMap > Region > Room,
plus DungeonLayout for procedurally-generated dungeon content.
"""

from __future__ import annotations

from enum import Enum

from pydantic import BaseModel, Field


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------


class Biome(str, Enum):
    """Environmental biome types for regions."""
    FOREST = "forest"
    DESERT = "desert"
    MOUNTAIN = "mountain"
    CAVE = "cave"
    OCEAN = "ocean"
    TUNDRA = "tundra"
    SWAMP = "swamp"
    VOLCANIC = "volcanic"
    URBAN = "urban"
    RUINS = "ruins"
    VOID = "void"


class RoomType(str, Enum):
    """Functional room types within a dungeon or building."""
    COMBAT = "combat"
    PUZZLE = "puzzle"
    TREASURE = "treasure"
    REST = "rest"
    BOSS = "boss"
    SHOP = "shop"
    NPC = "npc"
    ENTRANCE = "entrance"
    EXIT = "exit"
    SECRET = "secret"
    TRAP = "trap"
    EVENT = "event"


# ---------------------------------------------------------------------------
# Building blocks
# ---------------------------------------------------------------------------


class Connection(BaseModel):
    """A connection between two rooms or regions."""
    from_id: str
    to_id: str
    bidirectional: bool = True
    locked: bool = False
    lock_key: str | None = None
    hidden: bool = False
    description: str = ""


class Room(BaseModel):
    """A single room or area in a dungeon or building."""
    id: str
    name: str
    room_type: RoomType
    description: str
    width: int = 1  # Grid units
    height: int = 1
    position: tuple[int, int] = (0, 0)  # Grid position
    entities: list[str] = Field(default_factory=list, description="Entity IDs (NPCs, items, enemies)")
    properties: dict[str, object] = Field(default_factory=dict, description="Arbitrary room-specific data")


class Region(BaseModel):
    """A region in the overworld."""
    id: str
    name: str
    biome: Biome
    description: str
    level_range: tuple[int, int] = (1, 5)
    rooms: list[Room] = Field(default_factory=list)
    points_of_interest: list[str] = Field(default_factory=list)
    ambient_mood: str = "neutral"


# ---------------------------------------------------------------------------
# Composite structures
# ---------------------------------------------------------------------------


class DungeonLayout(BaseModel):
    """A complete dungeon with rooms and connections."""
    id: str
    name: str
    theme: str
    difficulty: int = Field(ge=1, le=10)
    rooms: list[Room]
    connections: list[Connection]
    entry_room_id: str
    exit_room_id: str
    boss_room_id: str | None = None
    loot_table_id: str | None = None
    estimated_clear_time_minutes: int = 30


class OverworldMap(BaseModel):
    """The full overworld map comprising regions and their connections."""
    regions: list[Region]
    connections: list[Connection]
    starting_region_id: str


class WorldDefinition(BaseModel):
    """Complete world definition for a game.

    This is the top-level spatial model that the WorldBuilder agent produces.
    It contains the overworld, any dungeons, and global world properties.
    """
    id: str
    name: str
    description: str
    lore_summary: str = ""
    overworld: OverworldMap | None = None
    dungeons: list[DungeonLayout] = Field(default_factory=list)
    global_properties: dict[str, object] = Field(default_factory=dict)
