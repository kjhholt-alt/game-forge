"""Tests for all Pydantic schemas: game, quest, and world.

Covers creation, serialization, validation, enums, nesting, and edge cases.
At least 25 tests total.
"""

from __future__ import annotations

import json

import pytest
from pydantic import ValidationError

from schemas.game import (
    ArtAssetSpec,
    DialogueLine,
    DialogueNode,
    GameConcept,
    GameProject,
    IssueSeverity,
    Item,
    ItemType,
    NPC,
    NPCDisposition,
    QAIssue,
    QAReport,
    Quest,
    QuestObjective,
    QuestType,
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
# GameConcept
# ---------------------------------------------------------------------------


class TestGameConcept:
    def test_create_valid(self, sample_concept: GameConcept) -> None:
        assert sample_concept.title == "Dungeon of Shadows"
        assert sample_concept.genre == "roguelike"
        assert len(sample_concept.core_mechanics) == 4

    def test_serialize_json_roundtrip(self, sample_concept: GameConcept) -> None:
        raw = sample_concept.model_dump_json()
        restored = GameConcept.model_validate_json(raw)
        assert restored.title == sample_concept.title
        assert restored.core_mechanics == sample_concept.core_mechanics

    def test_serialize_dict(self, sample_concept: GameConcept) -> None:
        d = sample_concept.model_dump()
        assert isinstance(d, dict)
        assert d["title"] == "Dungeon of Shadows"

    def test_missing_required_fields_raises(self) -> None:
        with pytest.raises(ValidationError):
            GameConcept(
                title="Test",
                genre="rpg",
                # missing: setting, core_mechanics, art_style, target_mood
            )

    def test_default_player_count(self) -> None:
        concept = GameConcept(
            title="T",
            genre="rpg",
            setting="s",
            core_mechanics=["a"],
            art_style="pixel",
            target_mood="fun",
        )
        assert concept.player_count == 1
        assert concept.estimated_playtime == "1-2 hours"


# ---------------------------------------------------------------------------
# Item
# ---------------------------------------------------------------------------


class TestItem:
    def test_create_valid(self, sample_item: Item) -> None:
        assert sample_item.name == "Blessed Sword"
        assert sample_item.item_type == ItemType.WEAPON

    def test_all_item_type_enum_values(self) -> None:
        for t in ItemType:
            item = Item(name=f"Test {t.value}", item_type=t, description="A test item.")
            assert item.item_type == t

    def test_invalid_item_type_raises(self) -> None:
        with pytest.raises(ValidationError):
            Item(name="Bad", item_type="not_a_type", description="Should fail.")

    def test_default_values(self) -> None:
        item = Item(name="Basic", item_type=ItemType.CONSUMABLE, description="A basic item.")
        assert item.rarity == "common"
        assert item.value == 0
        assert item.stats == {}
        assert item.effects == []

    def test_json_roundtrip(self, sample_item: Item) -> None:
        raw = sample_item.model_dump_json()
        parsed = json.loads(raw)
        assert parsed["stats"]["attack"] == 12
        restored = Item.model_validate_json(raw)
        assert restored.name == sample_item.name

    def test_item_with_effects(self) -> None:
        item = Item(
            name="Fire Potion",
            item_type=ItemType.CONSUMABLE,
            description="Explodes on contact.",
            effects=["fire_damage", "burn_status"],
        )
        assert len(item.effects) == 2


# ---------------------------------------------------------------------------
# NPC
# ---------------------------------------------------------------------------


class TestNPC:
    def test_create_valid(self, sample_npc: NPC) -> None:
        assert sample_npc.name == "Brother Aldric"
        assert sample_npc.disposition == NPCDisposition.FRIENDLY
        assert len(sample_npc.dialogue) == 1

    def test_all_disposition_enum_values(self) -> None:
        for d in NPCDisposition:
            npc = NPC(name="Test", role="test", description="Test", disposition=d)
            assert npc.disposition == d

    def test_npc_dialogue_structure(self, sample_npc: NPC) -> None:
        node = sample_npc.dialogue[0]
        assert node.id == "greeting"
        assert len(node.lines) == 1
        assert node.lines[0].emotion == "pleading"
        assert len(node.choices) == 2


# ---------------------------------------------------------------------------
# Quest (schemas.game)
# ---------------------------------------------------------------------------


class TestQuest:
    def test_create_valid(self, sample_quest: Quest) -> None:
        assert sample_quest.name == "Cleanse the Altar"
        assert sample_quest.quest_type == QuestType.MAIN
        assert len(sample_quest.objectives) == 2

    def test_all_quest_type_enum_values(self) -> None:
        for qt in QuestType:
            q = Quest(name=f"Test {qt.value}", quest_type=qt, description="A test quest.")
            assert q.quest_type == qt

    def test_empty_objectives_allowed(self) -> None:
        q = Quest(name="Empty", quest_type=QuestType.EXPLORE, description="No objectives.")
        assert q.objectives == []


# ---------------------------------------------------------------------------
# WorldDefinition (schemas.game)
# ---------------------------------------------------------------------------


class TestGameWorldDefinition:
    def test_create_valid(self, sample_game_world: GameWorldDefinition) -> None:
        assert sample_game_world.name == "The Shattered Depths"
        assert len(sample_game_world.regions) == 3

    def test_region_connections(self, sample_game_world: GameWorldDefinition) -> None:
        entrance = sample_game_world.regions[0]
        assert "Crypt Corridors" in entrance.connections

    def test_json_roundtrip(self, sample_game_world: GameWorldDefinition) -> None:
        raw = sample_game_world.model_dump_json()
        restored = GameWorldDefinition.model_validate_json(raw)
        assert restored.name == sample_game_world.name
        assert len(restored.regions) == len(sample_game_world.regions)


# ---------------------------------------------------------------------------
# QA Report
# ---------------------------------------------------------------------------


class TestQAReport:
    def test_create_valid(self) -> None:
        report = QAReport(
            overall_score=7.5,
            summary="Solid game.",
            issues=[
                QAIssue(
                    severity=IssueSeverity.MINOR,
                    category="balance",
                    description="Sword too strong.",
                ),
            ],
            strengths=["Great atmosphere"],
            passed=True,
        )
        assert report.overall_score == 7.5
        assert report.passed is True

    def test_score_below_min_raises(self) -> None:
        with pytest.raises(ValidationError):
            QAReport(overall_score=-1.0, summary="Bad")

    def test_score_above_max_raises(self) -> None:
        with pytest.raises(ValidationError):
            QAReport(overall_score=11.0, summary="Bad")

    def test_all_severity_values(self) -> None:
        for sev in IssueSeverity:
            issue = QAIssue(severity=sev, category="test", description="Test.")
            assert issue.severity == sev


# ---------------------------------------------------------------------------
# ArtAssetSpec
# ---------------------------------------------------------------------------


class TestArtAssetSpec:
    def test_create_valid(self) -> None:
        spec = ArtAssetSpec(
            name="hero_sprite",
            asset_type="sprite",
            description="A knight in shining armor.",
            dimensions=(64, 64),
        )
        assert spec.dimensions == (64, 64)
        assert spec.priority == "normal"


# ---------------------------------------------------------------------------
# GameProject
# ---------------------------------------------------------------------------


class TestGameProject:
    def test_create_minimal(self, sample_concept: GameConcept) -> None:
        project = GameProject(concept=sample_concept)
        assert project.concept.title == "Dungeon of Shadows"
        assert project.world is None
        assert project.quests == []
        assert project.qa_report is None

    def test_full_project_roundtrip(
        self,
        sample_concept: GameConcept,
        sample_game_world: GameWorldDefinition,
        sample_quest: Quest,
        sample_npc: NPC,
        sample_item: Item,
    ) -> None:
        project = GameProject(
            concept=sample_concept,
            world=sample_game_world,
            quests=[sample_quest],
            npcs=[sample_npc],
            items=[sample_item],
        )
        raw = project.model_dump_json()
        restored = GameProject.model_validate_json(raw)
        assert restored.concept.title == "Dungeon of Shadows"
        assert len(restored.quests) == 1
        assert len(restored.npcs) == 1
        assert len(restored.items) == 1


# ---------------------------------------------------------------------------
# DialogueTree (schemas.quest)
# ---------------------------------------------------------------------------


class TestDialogueTree:
    def test_create_valid(self, sample_dialogue_tree: DialogueTree) -> None:
        assert sample_dialogue_tree.npc_id == "npc_aldric"
        assert sample_dialogue_tree.root_node_id == "node_greeting"
        assert len(sample_dialogue_tree.nodes) == 4

    def test_branching_options(self, sample_dialogue_tree: DialogueTree) -> None:
        root = sample_dialogue_tree.nodes[0]
        assert len(root.options) == 3
        assert root.options[0].effects == {"flag_accepted_quest": True}
        assert root.options[2].conditions == {"stat_int": 12}

    def test_json_roundtrip(self, sample_dialogue_tree: DialogueTree) -> None:
        raw = sample_dialogue_tree.model_dump_json()
        restored = DialogueTree.model_validate_json(raw)
        assert restored.id == sample_dialogue_tree.id
        assert len(restored.nodes) == len(sample_dialogue_tree.nodes)


# ---------------------------------------------------------------------------
# QuestChain (schemas.quest)
# ---------------------------------------------------------------------------


class TestQuestChain:
    def test_create_valid(self, sample_quest_chain: QuestChain) -> None:
        assert sample_quest_chain.title == "The Cathedral's Secret"
        assert len(sample_quest_chain.quests) == 2
        assert sample_quest_chain.is_main_story is True

    def test_linked_quests(self, sample_quest_chain: QuestChain) -> None:
        first = sample_quest_chain.quests[0]
        second = sample_quest_chain.quests[1]
        assert first.id in second.prerequisites

    def test_quest_rewards_structure(self, sample_quest_chain: QuestChain) -> None:
        rewards = sample_quest_chain.quests[0].rewards
        assert rewards.xp == 100
        assert rewards.gold == 50
        assert "item_blessed_sword" in rewards.items
        assert rewards.reputation == {"forgotten_order": 10}
        assert "quest_deeper_descent" in rewards.unlocks


# ---------------------------------------------------------------------------
# Quest objective types (schemas.quest)
# ---------------------------------------------------------------------------


class TestQuestObjectiveTypes:
    def test_all_objective_types(self) -> None:
        for obj_type in QuestObjectiveType:
            obj = DetailedQuestObjective(
                id=f"obj_{obj_type.value}",
                description=f"Test {obj_type.value}",
                objective_type=obj_type,
                target="target",
            )
            assert obj.objective_type == obj_type

    def test_optional_objective(self) -> None:
        obj = DetailedQuestObjective(
            id="opt",
            description="Optional",
            objective_type=QuestObjectiveType.COLLECT,
            target="bonus",
            count=5,
            optional=True,
        )
        assert obj.optional is True
        assert obj.count == 5


# ---------------------------------------------------------------------------
# World schemas (schemas.world)
# ---------------------------------------------------------------------------


class TestWorldDefinition:
    def test_create_valid(self, sample_world: WorldDefinition) -> None:
        assert sample_world.name == "The Shattered Depths"
        assert sample_world.overworld is not None
        assert len(sample_world.dungeons) == 1

    def test_dungeon_structure(self, sample_world: WorldDefinition) -> None:
        dungeon = sample_world.dungeons[0]
        assert dungeon.name == "Cathedral Depths"
        assert len(dungeon.rooms) == 5
        assert len(dungeon.connections) == 4
        assert dungeon.difficulty == 5

    def test_dungeon_difficulty_too_low_raises(self) -> None:
        with pytest.raises(ValidationError):
            DungeonLayout(
                id="bad", name="Bad", theme="t", difficulty=0,
                rooms=[], connections=[], entry_room_id="a", exit_room_id="b",
            )

    def test_dungeon_difficulty_too_high_raises(self) -> None:
        with pytest.raises(ValidationError):
            DungeonLayout(
                id="bad", name="Bad", theme="t", difficulty=11,
                rooms=[], connections=[], entry_room_id="a", exit_room_id="b",
            )

    def test_all_room_types(self) -> None:
        for rt in RoomType:
            room = Room(id=f"r_{rt.value}", name=f"Test {rt.value}", room_type=rt, description="t")
            assert room.room_type == rt

    def test_all_biome_types(self) -> None:
        for b in Biome:
            region = WorldRegion(id=f"r_{b.value}", name=f"T {b.value}", biome=b, description="t")
            assert region.biome == b

    def test_locked_connection(self) -> None:
        conn = Connection(from_id="a", to_id="b", locked=True, lock_key="golden_key")
        assert conn.locked is True
        assert conn.lock_key == "golden_key"
        assert conn.bidirectional is True

    def test_hidden_connection(self) -> None:
        conn = Connection(from_id="a", to_id="b", hidden=True)
        assert conn.hidden is True

    def test_json_roundtrip(self, sample_world: WorldDefinition) -> None:
        raw = sample_world.model_dump_json()
        restored = WorldDefinition.model_validate_json(raw)
        assert restored.name == sample_world.name
        assert len(restored.dungeons) == 1
        assert len(restored.dungeons[0].rooms) == 5


# ---------------------------------------------------------------------------
# Lore
# ---------------------------------------------------------------------------


class TestLoreEntry:
    def test_create_valid(self, sample_lore_entry: LoreEntry) -> None:
        assert sample_lore_entry.title == "The Fall of the Cathedral"
        assert sample_lore_entry.discoverable is True

    def test_hidden_lore(self) -> None:
        lore = LoreEntry(
            id="hidden", title="Dev Note", category="meta",
            content="Hidden.", discoverable=False,
        )
        assert lore.discoverable is False


# ---------------------------------------------------------------------------
# JSON Schema generation (used for Claude prompts)
# ---------------------------------------------------------------------------


class TestJsonSchemaGeneration:
    @pytest.mark.parametrize(
        "model_cls",
        [GameConcept, Item, NPC, Quest, QAReport, ArtAssetSpec, WorldDefinition, DungeonLayout, DialogueTree],
    )
    def test_json_schema_has_properties(self, model_cls: type) -> None:
        schema = model_cls.model_json_schema()
        # Every schema should produce a JSON-serializable dict with 'properties'
        json_str = json.dumps(schema)
        assert len(json_str) > 50
        assert "properties" in schema or "$defs" in schema
