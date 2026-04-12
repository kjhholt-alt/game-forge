"""Item and equipment schemas.

Covers item definitions, stat modifiers, special effects, weapon types,
and loot tables for drops and treasure.
"""

from __future__ import annotations

from enum import Enum

from pydantic import BaseModel, Field


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------


class ItemRarity(str, Enum):
    """Item rarity tiers."""
    COMMON = "common"
    UNCOMMON = "uncommon"
    RARE = "rare"
    EPIC = "epic"
    LEGENDARY = "legendary"
    UNIQUE = "unique"


class ItemCategory(str, Enum):
    """Broad item categories."""
    WEAPON = "weapon"
    ARMOR = "armor"
    ACCESSORY = "accessory"
    CONSUMABLE = "consumable"
    MATERIAL = "material"
    KEY_ITEM = "key_item"
    QUEST_ITEM = "quest_item"
    CURRENCY = "currency"


class WeaponType(str, Enum):
    """Weapon sub-types for equipment."""
    SWORD = "sword"
    AXE = "axe"
    BOW = "bow"
    STAFF = "staff"
    DAGGER = "dagger"
    HAMMER = "hammer"
    SPEAR = "spear"
    WAND = "wand"


# ---------------------------------------------------------------------------
# Components
# ---------------------------------------------------------------------------


class StatModifier(BaseModel):
    """A single stat modifier applied by an item."""
    stat: str
    value: int
    is_percentage: bool = False


class ItemEffect(BaseModel):
    """A special effect an item can trigger."""
    name: str
    description: str
    trigger: str = "on_use"  # on_use, on_hit, on_equip, passive
    parameters: dict[str, object] = Field(default_factory=dict)


# ---------------------------------------------------------------------------
# Item definition
# ---------------------------------------------------------------------------


class ItemDefinition(BaseModel):
    """Full item definition — the contract between Mechanics and game runtime.

    Supports weapons, armor, consumables, quest items, and more.
    """
    id: str
    name: str
    description: str
    category: ItemCategory
    rarity: ItemRarity = ItemRarity.COMMON
    level_requirement: int = 1
    value: int = 0  # Buy price
    sell_value: int = 0
    stackable: bool = False
    max_stack: int = 1
    stat_modifiers: list[StatModifier] = Field(default_factory=list)
    effects: list[ItemEffect] = Field(default_factory=list)
    weapon_type: WeaponType | None = None
    damage_range: tuple[int, int] | None = None
    armor_value: int | None = None
    lore_text: str = ""
    icon_description: str = ""  # For AI art generation


# ---------------------------------------------------------------------------
# Loot tables
# ---------------------------------------------------------------------------


class LootTableEntry(BaseModel):
    """A single entry in a loot table with a weight and count range."""
    item_id: str
    weight: int = 10
    min_count: int = 1
    max_count: int = 1


class LootTable(BaseModel):
    """A loot table defining probabilistic drops from enemies or chests."""
    id: str
    name: str
    entries: list[LootTableEntry] = Field(default_factory=list)
    guaranteed_drops: list[str] = Field(
        default_factory=list,
        description="Item IDs that always drop",
    )
    gold_range: tuple[int, int] = (0, 0)
    xp_range: tuple[int, int] = (0, 0)
