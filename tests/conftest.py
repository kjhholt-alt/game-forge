"""Pytest fixtures for GameForge test suite.

Provides reusable sample data objects that mirror the Pydantic schemas.
All fixtures return valid, fully-populated instances.
"""

from __future__ import annotations

import pytest

from orchestrator.config import GameConfig
from schemas.game import (
    ArtAssetSpec,
    DialogueLine,
    DialogueNode,
    GameConcept,
    GameProject,
    Item,
    ItemType,
    NPC,
    NPCDisposition,
    QAIssue,
    QAReport,
    Quest,
    QuestObjective,
    QuestType,
    IssueSeverity,
    Region,
    WorldDefinition as GameWorldDefinition,
)
from schemas.quest import (
    DialogueNode as QuestDialogueNode,
    DialogueOption,
    DialogueTree,
    LoreEntry,
    Quest as DetailedQuest,
    QuestChain,
    QuestObjective as DetailedQuestObjective,
    QuestObjectiveType,
    QuestReward,
)
from schemas.world import (
    Biome,
    Connection,
    DungeonLayout,
    OverworldMap,
    Region as WorldRegion,
    Room,
    RoomType,
    WorldDefinition,
)


# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------


@pytest.fixture
def config() -> GameConfig:
    """GameConfig with test defaults (no paid API transport)."""
    return GameConfig(
        director_model="claude-opus-4-7",
        worker_model="claude-sonnet-4-6",
        fast_model="claude-haiku-4-5",
        godot_mcp_url="ws://localhost:6100",
        godot_project_path="./godot_template",
        state_db_path=":memory:",
        max_retries=2,
        enable_streaming=False,
        log_level="DEBUG",
    )


# ---------------------------------------------------------------------------
# Game-level schemas (schemas.game)
# ---------------------------------------------------------------------------


@pytest.fixture
def sample_concept() -> GameConcept:
    """A complete GameConcept for testing."""
    return GameConcept(
        title="Dungeon of Shadows",
        genre="roguelike",
        setting="A crumbling underground labyrinth beneath a ruined cathedral, filled with undead horrors and forgotten treasures.",
        core_mechanics=[
            "Turn-based combat",
            "Procedural dungeon generation",
            "Item crafting",
            "Permadeath with meta-progression",
        ],
        art_style="16-bit pixel art with dark palette",
        target_mood="tense",
        player_count=1,
        estimated_playtime="2-4 hours",
    )


@pytest.fixture
def sample_game_world() -> GameWorldDefinition:
    """A GameWorldDefinition (from schemas.game) for testing."""
    return GameWorldDefinition(
        name="The Shattered Depths",
        description="Ancient catacombs beneath the Cathedral of Light.",
        regions=[
            Region(
                name="Entrance Hall",
                description="The crumbling entry to the dungeon.",
                biome="ruins",
                connections=["Crypt Corridors"],
                points_of_interest=["Broken Altar", "Sealed Door"],
                enemy_types=["skeleton", "rat"],
                level_range=(1, 3),
            ),
            Region(
                name="Crypt Corridors",
                description="Narrow passages lined with ancient tombs.",
                biome="cave",
                connections=["Entrance Hall", "Bone Chamber"],
                points_of_interest=["Hidden Passage"],
                enemy_types=["skeleton", "ghost"],
                level_range=(2, 5),
            ),
            Region(
                name="Bone Chamber",
                description="A vast cavern of bones and darkness.",
                biome="cave",
                connections=["Crypt Corridors"],
                points_of_interest=["Bone Throne"],
                enemy_types=["skeleton_knight", "necromancer"],
                level_range=(4, 7),
            ),
        ],
        factions=["Undead Legion", "Forgotten Order"],
        history_summary="Once a holy site, corrupted by a necromancer's ritual centuries ago.",
        themes=["corruption", "redemption", "survival"],
    )


@pytest.fixture
def sample_quest() -> Quest:
    """A Quest (schemas.game) for testing."""
    return Quest(
        name="Cleanse the Altar",
        quest_type=QuestType.MAIN,
        description="Find the holy water and cleanse the broken altar in the Entrance Hall.",
        giver="Spirit of the High Priest",
        region="Entrance Hall",
        objectives=[
            QuestObjective(
                description="Find the Holy Water",
                objective_type="collect",
                target="holy_water",
                quantity=1,
            ),
            QuestObjective(
                description="Cleanse the Broken Altar",
                objective_type="interact",
                target="broken_altar",
                quantity=1,
            ),
        ],
        rewards=["Blessed Sword", "100 XP"],
        prerequisites=[],
        level_requirement=1,
    )


@pytest.fixture
def sample_npc() -> NPC:
    """An NPC (schemas.game) for testing."""
    return NPC(
        name="Brother Aldric",
        role="quest_giver",
        description="The ghost of a priest who once tended the cathedral. He seeks redemption.",
        disposition=NPCDisposition.FRIENDLY,
        location="Entrance Hall",
        dialogue=[
            DialogueNode(
                id="greeting",
                lines=[
                    DialogueLine(
                        speaker="Brother Aldric",
                        text="Traveler... you can see me? The altar... it must be cleansed.",
                        emotion="pleading",
                    ),
                ],
                choices=[
                    {"text": "I'll help you.", "next_node_id": "accept"},
                    {"text": "Not my problem.", "next_node_id": "refuse"},
                ],
            ),
        ],
        stats={"hp": 1, "attack": 0, "defense": 0},
    )


@pytest.fixture
def sample_item() -> Item:
    """An Item (schemas.game) for testing."""
    return Item(
        name="Blessed Sword",
        item_type=ItemType.WEAPON,
        description="A sword imbued with holy light. Effective against undead.",
        rarity="rare",
        value=150,
        stats={"attack": 12, "defense": 2},
        effects=["bonus_vs_undead"],
    )


@pytest.fixture
def sample_encounter() -> dict:
    """Raw encounter data matching the Godot combat system's expected format."""
    return {
        "id": "enc_crypt_01",
        "name": "Crypt Ambush",
        "enemies": [
            {
                "name": "Skeleton Warrior",
                "combat_id": "skeleton_warrior_0",
                "hp": 60,
                "max_hp": 60,
                "attack": 8,
                "defense": 4,
                "speed": 3,
                "xp_reward": 25,
                "gold_reward": 10,
                "abilities": [
                    {"name": "Bone Strike", "power": 5, "mp_cost": 0, "damage_type": "physical"},
                ],
                "loot": [
                    {"id": "bone_fragment", "name": "Bone Fragment", "drop_chance": 0.4},
                ],
            },
            {
                "name": "Skeleton Archer",
                "combat_id": "skeleton_archer_0",
                "hp": 40,
                "max_hp": 40,
                "attack": 10,
                "defense": 2,
                "speed": 5,
                "xp_reward": 20,
                "gold_reward": 8,
                "abilities": [],
                "loot": [],
            },
        ],
        "formation": "line",
        "rewards": {"xp": 10, "gold": 5, "items": []},
    }


# ---------------------------------------------------------------------------
# Detailed quest schemas (schemas.quest)
# ---------------------------------------------------------------------------


@pytest.fixture
def sample_detailed_quest() -> DetailedQuest:
    """A Quest from schemas.quest with full structure."""
    return DetailedQuest(
        id="quest_cleanse_altar",
        title="Cleanse the Altar",
        description="Find the holy water and cleanse the broken altar.",
        quest_giver_npc_id="npc_aldric",
        location_id="region_entrance_hall",
        level_requirement=1,
        objectives=[
            DetailedQuestObjective(
                id="obj_find_water",
                description="Find the Holy Water",
                objective_type=QuestObjectiveType.COLLECT,
                target="item_holy_water",
                count=1,
            ),
            DetailedQuestObjective(
                id="obj_cleanse",
                description="Cleanse the Broken Altar",
                objective_type=QuestObjectiveType.TALK,
                target="poi_broken_altar",
                count=1,
            ),
        ],
        rewards=QuestReward(
            xp=100,
            gold=50,
            items=["item_blessed_sword"],
            reputation={"forgotten_order": 10},
            unlocks=["quest_deeper_descent"],
        ),
        prerequisites=[],
        branches={"spare_ghost": "quest_ghost_ally", "banish_ghost": "quest_solo_descent"},
        failure_conditions=["player_dies"],
        time_limit_turns=None,
    )


@pytest.fixture
def sample_quest_chain(sample_detailed_quest: DetailedQuest) -> QuestChain:
    """A QuestChain containing the sample quest."""
    sequel = DetailedQuest(
        id="quest_deeper_descent",
        title="The Deeper Descent",
        description="Venture into the Bone Chamber.",
        location_id="region_crypt_corridors",
        level_requirement=3,
        objectives=[
            DetailedQuestObjective(
                id="obj_reach_chamber",
                description="Reach the Bone Chamber",
                objective_type=QuestObjectiveType.EXPLORE,
                target="region_bone_chamber",
            ),
        ],
        rewards=QuestReward(xp=200, gold=100),
        prerequisites=["quest_cleanse_altar"],
    )
    return QuestChain(
        id="chain_main_story",
        title="The Cathedral's Secret",
        description="Uncover the truth of the fallen cathedral.",
        quests=[sample_detailed_quest, sequel],
        is_main_story=True,
    )


@pytest.fixture
def sample_dialogue_tree() -> DialogueTree:
    """A DialogueTree with branching options."""
    return DialogueTree(
        id="dlg_aldric_greeting",
        npc_id="npc_aldric",
        context="first_meeting",
        root_node_id="node_greeting",
        nodes=[
            QuestDialogueNode(
                id="node_greeting",
                speaker="npc_aldric",
                text="Traveler... you can see me? The altar must be cleansed.",
                emotion="pleading",
                options=[
                    DialogueOption(
                        text="I'll help you.",
                        next_node_id="node_accept",
                        effects={"flag_accepted_quest": True},
                    ),
                    DialogueOption(
                        text="Not my problem.",
                        next_node_id="node_refuse",
                    ),
                    DialogueOption(
                        text="Tell me more about this place.",
                        next_node_id="node_lore",
                        conditions={"stat_int": 12},
                    ),
                ],
            ),
            QuestDialogueNode(
                id="node_accept",
                speaker="npc_aldric",
                text="Thank you, brave soul. Seek the holy water in the Crypt Corridors.",
                emotion="grateful",
                auto_next=None,
            ),
            QuestDialogueNode(
                id="node_refuse",
                speaker="npc_aldric",
                text="Then the darkness will consume us all...",
                emotion="despair",
                auto_next=None,
            ),
            QuestDialogueNode(
                id="node_lore",
                speaker="npc_aldric",
                text="This was once the Cathedral of Light, until the Necromancer Valdris performed his dark ritual.",
                emotion="somber",
                auto_next="node_greeting",
            ),
        ],
    )


@pytest.fixture
def sample_lore_entry() -> LoreEntry:
    """A LoreEntry for testing."""
    return LoreEntry(
        id="lore_cathedral_history",
        title="The Fall of the Cathedral",
        category="history",
        content="Three centuries ago, the Cathedral of Light stood as a beacon of hope...",
        related_entities=["npc_aldric", "region_entrance_hall"],
        discoverable=True,
        location_hint="Found on a crumbling scroll near the Broken Altar.",
    )


# ---------------------------------------------------------------------------
# World schemas (schemas.world)
# ---------------------------------------------------------------------------


@pytest.fixture
def sample_world() -> WorldDefinition:
    """A WorldDefinition (from schemas.world) with dungeon."""
    entrance = Room(
        id="room_entrance",
        name="Dungeon Entrance",
        room_type=RoomType.ENTRANCE,
        description="A narrow stairway descends into darkness.",
        width=6,
        height=6,
        position=(0, 0),
    )
    combat_room = Room(
        id="room_combat_01",
        name="Guard Post",
        room_type=RoomType.COMBAT,
        description="Skeletons patrol this hallway.",
        width=8,
        height=8,
        position=(8, 0),
        entities=["skeleton_warrior_0", "skeleton_archer_0"],
    )
    treasure_room = Room(
        id="room_treasure",
        name="Hidden Vault",
        room_type=RoomType.TREASURE,
        description="Ancient riches lie within.",
        width=5,
        height=5,
        position=(8, 10),
    )
    boss_room = Room(
        id="room_boss",
        name="Bone Throne",
        room_type=RoomType.BOSS,
        description="The Necromancer awaits atop a throne of bones.",
        width=12,
        height=12,
        position=(20, 0),
        entities=["necromancer_boss"],
    )
    exit_room = Room(
        id="room_exit",
        name="Escape Tunnel",
        room_type=RoomType.EXIT,
        description="A narrow tunnel leading to the surface.",
        width=4,
        height=4,
        position=(20, 14),
    )

    dungeon = DungeonLayout(
        id="dungeon_cathedral_depths",
        name="Cathedral Depths",
        theme="gothic_undead",
        difficulty=5,
        rooms=[entrance, combat_room, treasure_room, boss_room, exit_room],
        connections=[
            Connection(from_id="room_entrance", to_id="room_combat_01"),
            Connection(from_id="room_combat_01", to_id="room_treasure", hidden=True),
            Connection(from_id="room_combat_01", to_id="room_boss", locked=True, lock_key="boss_key"),
            Connection(from_id="room_boss", to_id="room_exit"),
        ],
        entry_room_id="room_entrance",
        exit_room_id="room_exit",
        boss_room_id="room_boss",
    )

    region = WorldRegion(
        id="region_entrance_hall",
        name="Entrance Hall",
        biome=Biome.RUINS,
        description="The crumbling entry.",
        level_range=(1, 3),
        rooms=[entrance, combat_room],
        points_of_interest=["Broken Altar"],
        ambient_mood="eerie",
    )

    overworld = OverworldMap(
        regions=[region],
        connections=[],
        starting_region_id="region_entrance_hall",
    )

    return WorldDefinition(
        id="world_shattered_depths",
        name="The Shattered Depths",
        description="Ancient catacombs beneath the Cathedral of Light.",
        lore_summary="Once a holy site, corrupted centuries ago.",
        overworld=overworld,
        dungeons=[dungeon],
        global_properties={"max_dungeon_depth": 5, "world_theme": "gothic"},
    )


@pytest.fixture
def sample_stat_system() -> dict:
    """A sample stat system configuration dict."""
    return {
        "base_stats": {
            "hp": 100,
            "max_hp": 100,
            "mp": 50,
            "max_mp": 50,
            "str": 10,
            "dex": 10,
            "int": 10,
            "con": 10,
            "wis": 10,
            "cha": 10,
            "attack": 5,
            "defense": 5,
            "speed": 5,
        },
        "level_up_bonuses": {
            "max_hp": 10,
            "max_mp": 5,
            "str": 1,
            "dex": 1,
            "int": 1,
            "con": 1,
            "wis": 1,
            "cha": 1,
        },
        "xp_growth_factor": 1.5,
    }


@pytest.fixture
def sample_combat_system() -> dict:
    """A sample combat system configuration dict."""
    return {
        "damage_formula": "attack * 2 - defense",
        "variance_range": [0.85, 1.15],
        "minimum_damage": 1,
        "flee_base_chance": 0.5,
        "flee_speed_modifier": 0.05,
        "status_effects": [
            {"name": "poison", "damage_per_turn": 5, "max_duration": 5},
            {"name": "regen", "heal_per_turn": 10, "max_duration": 3},
            {"name": "burn", "damage_per_turn": 8, "max_duration": 3},
        ],
    }
