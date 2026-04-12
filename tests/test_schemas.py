"""Comprehensive tests for all schema modules."""

from __future__ import annotations

import json

from schemas import (
    Ability,
    BalanceReport,
    Biome,
    CharacterArtDescription,
    CombatSystem,
    Connection,
    DamageType,
    DerivedStat,
    DialogueNode,
    DialogueOption,
    DialogueTree,
    DungeonLayout,
    Encounter,
    EnemyDefinition,
    EnemyPlacement,
    GameConcept,
    GameGenre,
    GameProject,
    ItemCategory,
    ItemDefinition,
    ItemEffect,
    ItemRarity,
    LootTable,
    LootTableEntry,
    LoreEntry,
    NPCDefinition,
    NPCRole,
    NPCStats,
    OverworldMap,
    Personality,
    QAIssue,
    QAReport,
    Quest,
    QuestChain,
    QuestObjective,
    QuestObjectiveType,
    QuestReward,
    Region,
    Relationship,
    Room,
    RoomType,
    Schedule,
    Stat,
    StatModifier,
    StatSystem,
    StatusEffect,
    StyleGuide,
    TilesetDescription,
    UIArtDescription,
    WeaponType,
    WorldDefinition,
)


def test_world_hierarchy():
    """Build a full world with rooms, regions, dungeons, and overworld."""
    room1 = Room(id="r1", name="Entry Hall", room_type=RoomType.ENTRANCE, description="Grand entrance")
    room2 = Room(id="r2", name="Boss Chamber", room_type=RoomType.BOSS, description="Dark chamber", entities=["boss_01"])
    conn = Connection(from_id="r1", to_id="r2", locked=True, lock_key="golden_key")
    region = Region(id="reg1", name="Dark Forest", biome=Biome.FOREST, description="Spooky forest", level_range=(1, 5), rooms=[room1])
    dungeon = DungeonLayout(
        id="d1", name="Shadow Keep", theme="undead", difficulty=5,
        rooms=[room1, room2], connections=[conn],
        entry_room_id="r1", exit_room_id="r2", boss_room_id="r2",
    )
    overworld = OverworldMap(regions=[region], connections=[], starting_region_id="reg1")
    world = WorldDefinition(id="w1", name="Eldrathia", description="Dark fantasy", overworld=overworld, dungeons=[dungeon])

    assert world.name == "Eldrathia"
    assert len(world.dungeons) == 1
    assert world.overworld is not None
    assert len(world.overworld.regions) == 1
    assert world.dungeons[0].rooms[1].room_type == RoomType.BOSS


def test_quest_chain():
    """Build a quest chain with objectives, rewards, and branching."""
    obj = QuestObjective(id="obj1", description="Slay goblins", objective_type=QuestObjectiveType.KILL, target="goblin", count=5)
    reward = QuestReward(xp=100, gold=50, items=["sword_01"], reputation={"village": 10})
    quest = Quest(
        id="q1", title="Goblin Menace", description="Clear goblins",
        location_id="reg1", objectives=[obj], rewards=reward,
        branches={"spare_chief": "q2"},
    )
    chain = QuestChain(id="qc1", title="Village Salvation", description="Save the village", quests=[quest], is_main_story=True)

    assert chain.is_main_story
    assert len(chain.quests) == 1
    assert chain.quests[0].rewards.xp == 100
    assert "spare_chief" in chain.quests[0].branches


def test_dialogue_tree():
    """Build a dialogue tree with options and conditions."""
    opt1 = DialogueOption(text="Tell me more", next_node_id="n2")
    opt2 = DialogueOption(text="Goodbye", conditions={"reputation": 10})
    node1 = DialogueNode(id="n1", speaker="npc1", text="Greetings!", options=[opt1, opt2])
    node2 = DialogueNode(id="n2", speaker="npc1", text="The goblins...", auto_next=None)
    tree = DialogueTree(id="dt1", npc_id="npc1", context="first_meeting", root_node_id="n1", nodes=[node1, node2])

    assert tree.root_node_id == "n1"
    assert len(tree.nodes) == 2
    assert len(tree.nodes[0].options) == 2


def test_npc_definition():
    """Build a full NPC with personality, relationships, and schedule."""
    personality = Personality(
        traits=["brave", "honest"], values=["honor"],
        fears=["darkness"], speech_pattern="formal",
    )
    rel = Relationship(target_npc_id="npc2", type="rival", trust=30)
    schedule = Schedule(entries=[{"time": "morning", "location": "market", "activity": "training"}])
    npc = NPCDefinition(
        id="npc1", name="Sir Galahad", role=NPCRole.QUEST_GIVER,
        description="Noble knight", appearance="Silver armor",
        personality=personality, location_id="reg1",
        relationships=[rel], schedule=schedule,
        quest_ids=["q1"], barks={"idle": ["The goblins grow bolder..."]},
        is_essential=True, faction="Knights",
    )

    assert npc.is_essential
    assert npc.faction == "Knights"
    assert len(npc.relationships) == 1
    assert npc.schedule is not None


def test_item_definition():
    """Build items with modifiers, effects, and weapon types."""
    mod = StatModifier(stat="attack", value=5)
    effect = ItemEffect(name="Fire Slash", description="Fire damage", trigger="on_hit", parameters={"damage": 10})
    item = ItemDefinition(
        id="sword_01", name="Flame Sword", description="A burning blade",
        category=ItemCategory.WEAPON, rarity=ItemRarity.RARE,
        weapon_type=WeaponType.SWORD, damage_range=(15, 25),
        stat_modifiers=[mod], effects=[effect], lore_text="Forged in dragonfire",
    )

    assert item.rarity == ItemRarity.RARE
    assert item.weapon_type == WeaponType.SWORD
    assert item.damage_range == (15, 25)
    assert len(item.stat_modifiers) == 1


def test_loot_table():
    """Build a loot table with entries and guaranteed drops."""
    entry = LootTableEntry(item_id="sword_01", weight=5, min_count=1, max_count=1)
    loot = LootTable(id="lt1", name="Boss Drops", entries=[entry], guaranteed_drops=["sword_01"], gold_range=(50, 100))

    assert len(loot.entries) == 1
    assert loot.gold_range == (50, 100)


def test_combat_system():
    """Build status effects, abilities, enemies, and encounters."""
    status = StatusEffect(id="se1", name="Burning", description="On fire", duration_turns=3, damage_per_turn=5)
    ability = Ability(
        id="ab1", name="Fireball", description="Launches fire",
        damage_type=DamageType.FIRE, base_damage=20, cost={"mana": 15},
        target="all_enemies", status_effects=["se1"],
    )
    enemy = EnemyDefinition(
        id="e1", name="Goblin", description="Small green creature",
        level=2, hp=15, weaknesses={"fire": 1.5}, abilities=["ab1"],
    )
    placement = EnemyPlacement(enemy_id="e1", count=3)
    encounter = Encounter(
        id="enc1", name="Goblin Ambush", description="Goblins attack!",
        location_id="reg1", difficulty=3, enemies=[placement], ambush=True,
    )

    assert encounter.ambush
    assert len(encounter.enemies) == 1
    assert encounter.enemies[0].count == 3


def test_stat_system():
    """Build a stat and progression system."""
    stat = Stat(name="Strength", abbreviation="STR", description="Physical power", base_value=10, growth_rate=1.2)
    derived = DerivedStat(name="Max HP", formula="con * 10 + level * 5", base_stats=["con", "level"])
    sys = StatSystem(stats=[stat], derived_stats=[derived], level_cap=50, xp_curve="exponential")

    assert sys.level_cap == 50
    assert len(sys.stats) == 1
    assert sys.stats[0].growth_rate == 1.2


def test_combat_config():
    """Build a full combat system configuration."""
    combat = CombatSystem(
        turn_order="speed_based", actions_per_turn=1,
        base_hit_chance=0.85, critical_hit_chance=0.1,
        damage_formula="attack * scaling - defense * 0.5",
        max_party_size=4,
    )

    assert combat.max_party_size == 4
    assert combat.critical_hit_multiplier == 1.5  # default


def test_art_schemas():
    """Build style guide and art descriptions."""
    style = StyleGuide(
        art_style="16-bit pixel art", color_palette=["#2d1b69", "#ff6b6b"],
        mood="dark fantasy", reference_games=["Chrono Trigger"],
    )
    tileset = TilesetDescription(biome="forest", tile_size=16, tiles={"grass": "Green grass"})
    char_art = CharacterArtDescription(
        npc_id="npc1", portrait_description="Noble knight",
        sprite_description="16x16 knight", expression_descriptions={"happy": "Smile"},
    )
    ui_art = UIArtDescription(theme="medieval", elements={"health_bar": "Red gradient bar"})

    assert style.art_style == "16-bit pixel art"
    assert tileset.tile_size == 16
    assert "happy" in char_art.expression_descriptions
    assert ui_art.theme == "medieval"


def test_qa_and_balance():
    """Build QA and balance reports."""
    issue = QAIssue(severity="warning", category="balance", description="Sword too strong", suggested_fix="Raise level req")
    qa = QAReport(project_id="p1", issues=[issue], overall_score=7, playable=True, summary="Solid foundation")
    balance = BalanceReport(
        power_curve_assessment="Smooth",
        difficulty_spikes=["Boss at level 5"],
        score=7,
    )

    assert qa.playable
    assert len(qa.issues) == 1
    assert balance.score == 7


def test_lore_entry():
    """Build a lore entry."""
    lore = LoreEntry(
        id="lore1", title="The Fall of Eldrath", category="history",
        content="Long ago the kingdom fell...",
        related_entities=["reg1"], discoverable=True,
        location_hint="Ancient library",
    )

    assert lore.discoverable
    assert lore.category == "history"


def test_game_project_full():
    """Build a complete GameProject and verify serialization round-trip."""
    concept = GameConcept(
        title="Shadow Quest", genre=GameGenre.RPG,
        setting="Dark fantasy", core_mechanics=["combat", "exploration"],
        art_style="pixel art", target_mood="dark",
        unique_selling_points=["AI companions"],
    )
    world = WorldDefinition(id="w1", name="Eldrathia", description="Dark world")
    obj = QuestObjective(id="obj1", description="Slay goblins", objective_type=QuestObjectiveType.KILL, target="goblin")
    quest = Quest(id="q1", title="Goblin Menace", description="Clear goblins", location_id="reg1", objectives=[obj])
    personality = Personality(traits=["brave"], values=["honor"])
    npc = NPCDefinition(
        id="npc1", name="Knight", role=NPCRole.QUEST_GIVER,
        description="A knight", appearance="Armor",
        personality=personality, location_id="reg1",
    )
    item = ItemDefinition(
        id="i1", name="Sword", description="A blade",
        category=ItemCategory.WEAPON, rarity=ItemRarity.COMMON,
    )
    placement = EnemyPlacement(enemy_id="e1", count=2)
    encounter = Encounter(
        id="enc1", name="Fight", description="Combat",
        location_id="reg1", difficulty=3, enemies=[placement],
    )
    stat = Stat(name="STR", abbreviation="STR", description="Strength")
    stat_sys = StatSystem(stats=[stat])
    combat = CombatSystem()
    style = StyleGuide(art_style="pixel art", color_palette=["#000"], mood="dark")
    qa = QAReport(project_id="p1", overall_score=8, playable=True, summary="Good")

    project = GameProject(
        id="proj1", concept=concept, world=world,
        quests=[quest], npcs=[npc], items=[item],
        encounters=[encounter], stat_system=stat_sys,
        combat_system=combat, style_guide=style, qa_report=qa,
    )

    # Serialize to JSON
    json_str = project.model_dump_json(indent=2)
    assert len(json_str) > 100

    # Parse back
    restored = GameProject.model_validate_json(json_str)
    assert restored.id == "proj1"
    assert restored.concept.title == "Shadow Quest"
    assert restored.concept.genre == GameGenre.RPG
    assert len(restored.quests) == 1
    assert len(restored.npcs) == 1
    assert len(restored.items) == 1
    assert len(restored.encounters) == 1
    assert restored.stat_system is not None
    assert restored.combat_system is not None
    assert restored.style_guide is not None
    assert restored.qa_report is not None
    assert restored.qa_report.playable


def test_game_project_minimal():
    """Verify a GameProject can be created with just required fields."""
    concept = GameConcept(
        title="Minimal", genre=GameGenre.PUZZLE,
        setting="Abstract", core_mechanics=["match"],
        art_style="minimalist", target_mood="calm",
    )
    project = GameProject(id="p2", concept=concept)

    assert project.world is None
    assert project.quests == []
    assert project.encounters == []
    assert project.qa_report is None


def test_all_enums():
    """Verify all enum values are accessible."""
    assert len(Biome) == 11
    assert len(RoomType) == 12
    assert len(QuestObjectiveType) == 10
    assert len(NPCRole) == 10
    assert len(ItemRarity) == 6
    assert len(ItemCategory) == 8
    assert len(WeaponType) == 8
    assert len(DamageType) == 8
    assert len(GameGenre) == 6


def test_json_schema_generation():
    """Verify JSON schema generation for key types (used for Claude prompts)."""
    for model in [GameConcept, WorldDefinition, Quest, NPCDefinition, ItemDefinition, Encounter, QAReport, CombatSystem, StatSystem, StyleGuide]:
        schema = model.model_json_schema()
        assert "properties" in schema
        json_str = json.dumps(schema)
        assert len(json_str) > 50
