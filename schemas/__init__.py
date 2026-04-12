"""Game schema definitions for GameForge.

All Pydantic models that define the structure of game worlds,
characters, items, quests, combat, and other game entities.

Every model is re-exported here for convenience::

    from schemas import WorldDefinition, Quest, NPCDefinition
"""

# -- World & level structure ------------------------------------------------
from schemas.world import (
    Biome,
    Connection,
    DungeonLayout,
    OverworldMap,
    Region,
    Room,
    RoomType,
    WorldDefinition,
)

# -- Quest & narrative ------------------------------------------------------
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

# -- NPCs ------------------------------------------------------------------
from schemas.npc import (
    NPCDefinition,
    NPCRole,
    NPCStats,
    Personality,
    Relationship,
    Schedule,
)

# -- Items ------------------------------------------------------------------
from schemas.item import (
    ItemCategory,
    ItemDefinition,
    ItemEffect,
    ItemRarity,
    LootTable,
    LootTableEntry,
    StatModifier,
    WeaponType,
)

# -- Combat, stats, art, QA ------------------------------------------------
from schemas.combat import (
    Ability,
    BalanceReport,
    CharacterArtDescription,
    CombatSystem,
    DamageType,
    DerivedStat,
    Encounter,
    EnemyDefinition,
    EnemyPlacement,
    QAIssue,
    QAReport,
    Stat,
    StatSystem,
    StatusEffect,
    StyleGuide,
    TilesetDescription,
    UIArtDescription,
)

# -- Project-level ----------------------------------------------------------
from schemas.project import (
    GameConcept,
    GameGenre,
    GameProject,
)

# -- SIGNAL ops (intelligence analyst roguelike) ----------------------------
from schemas.signal_ops import (
    AnalystDefinition,
    AnalystSkill,
    AnalystSkillType,
    Campaign,
    CampaignTheme,
    Classification,
    ConnectionType,
    ConspiracyEdge,
    ConspiracyGraph,
    ConspiracyNode,
    ConspiracyNodeType,
    Credential,
    DetectionLevel,
    EmployeeProfile,
    EvidenceBoard,
    EvidenceConnection,
    EvidenceItem,
    EvidenceType,
    FacilityLayout,
    FileEntry,
    HostDefinition,
    HostOS,
    InheritancePackage,
    InterceptBatch,
    NetworkTopology,
    OpBriefing,
    OpGrade,
    OpPhase,
    OpResult,
    Operation,
    ServiceDefinition,
    ServiceType,
    SubnetDefinition,
    TargetProfile,
    ToolkitItem,
    ToolkitItemType,
    Vulnerability,
    VulnerabilityChain,
    VulnerabilityStep,
)


__all__ = [
    # world
    "Biome",
    "Connection",
    "DungeonLayout",
    "OverworldMap",
    "Region",
    "Room",
    "RoomType",
    "WorldDefinition",
    # quest
    "DialogueNode",
    "DialogueOption",
    "DialogueTree",
    "LoreEntry",
    "Quest",
    "QuestChain",
    "QuestObjective",
    "QuestObjectiveType",
    "QuestReward",
    # npc
    "NPCDefinition",
    "NPCRole",
    "NPCStats",
    "Personality",
    "Relationship",
    "Schedule",
    # item
    "ItemCategory",
    "ItemDefinition",
    "ItemEffect",
    "ItemRarity",
    "LootTable",
    "LootTableEntry",
    "StatModifier",
    "WeaponType",
    # combat
    "Ability",
    "BalanceReport",
    "CharacterArtDescription",
    "CombatSystem",
    "DamageType",
    "DerivedStat",
    "Encounter",
    "EnemyDefinition",
    "EnemyPlacement",
    "QAIssue",
    "QAReport",
    "Stat",
    "StatSystem",
    "StatusEffect",
    "StyleGuide",
    "TilesetDescription",
    "UIArtDescription",
    # project
    "GameConcept",
    "GameGenre",
    "GameProject",
    # signal_ops
    "AnalystDefinition",
    "AnalystSkill",
    "AnalystSkillType",
    "Campaign",
    "CampaignTheme",
    "Classification",
    "ConnectionType",
    "ConspiracyEdge",
    "ConspiracyGraph",
    "ConspiracyNode",
    "ConspiracyNodeType",
    "Credential",
    "DetectionLevel",
    "EmployeeProfile",
    "EvidenceBoard",
    "EvidenceConnection",
    "EvidenceItem",
    "EvidenceType",
    "FacilityLayout",
    "FileEntry",
    "HostDefinition",
    "HostOS",
    "InheritancePackage",
    "InterceptBatch",
    "NetworkTopology",
    "OpBriefing",
    "OpGrade",
    "OpPhase",
    "OpResult",
    "Operation",
    "ServiceDefinition",
    "ServiceType",
    "SubnetDefinition",
    "TargetProfile",
    "ToolkitItem",
    "ToolkitItemType",
    "Vulnerability",
    "VulnerabilityChain",
    "VulnerabilityStep",
]
