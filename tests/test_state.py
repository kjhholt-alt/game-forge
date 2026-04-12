"""Tests for StateTools (SQLite persistence layer).

Uses in-memory SQLite for isolation. No real files are created.
"""

from __future__ import annotations

import pytest

from schemas import GameConcept, GameProject
from schemas.world import WorldDefinition
from tools.state_tools import StateTools


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
async def state() -> StateTools:
    """Initialized in-memory StateTools instance."""
    st = StateTools(":memory:")
    await st.initialize()
    yield st
    await st.close()


@pytest.fixture
def minimal_project() -> GameProject:
    """Minimal GameProject for persistence testing."""
    return GameProject(
        id="proj_test_001",
        concept=GameConcept(
            title="Test Game",
            genre="rpg",
            setting="A test world.",
            core_mechanics=["combat"],
            art_style="pixel art",
            target_mood="fun",
        ),
    )


@pytest.fixture
def minimal_world(sample_world: WorldDefinition) -> WorldDefinition:
    """Use the world fixture from conftest."""
    return sample_world


# ---------------------------------------------------------------------------
# Database initialization
# ---------------------------------------------------------------------------


class TestInitialize:
    async def test_initialize_creates_tables(self, state: StateTools) -> None:
        """Tables should exist after initialize()."""
        db = state._ensure_db()
        rows = await db.execute_fetchall(
            "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
        )
        table_names = [r[0] for r in rows]
        assert "projects" in table_names
        assert "worlds" in table_names
        assert "entities" in table_names
        assert "generation_log" in table_names

    async def test_double_initialize_is_safe(self) -> None:
        """Calling initialize() twice should not raise."""
        st = StateTools(":memory:")
        await st.initialize()
        await st.initialize()
        await st.close()

    async def test_not_initialized_raises(self) -> None:
        """Accessing db before initialize() should raise."""
        st = StateTools(":memory:")
        with pytest.raises(RuntimeError, match="not initialized"):
            st._ensure_db()


# ---------------------------------------------------------------------------
# World CRUD
# ---------------------------------------------------------------------------


class TestWorldPersistence:
    async def test_save_and_load_world(
        self, state: StateTools, minimal_world: WorldDefinition
    ) -> None:
        row_id = await state.save_world(minimal_world)
        assert row_id > 0

        loaded = await state.load_world(row_id)
        assert loaded.name == minimal_world.name
        assert loaded.id == minimal_world.id

    async def test_load_missing_world_raises(self, state: StateTools) -> None:
        with pytest.raises(KeyError, match="No world"):
            await state.load_world(9999)


# ---------------------------------------------------------------------------
# Entity CRUD
# ---------------------------------------------------------------------------


class TestEntityPersistence:
    async def test_save_and_load_entity(self, state: StateTools) -> None:
        data = {"name": "Test NPC", "role": "merchant", "hp": 50}
        await state.save_entity("npc", "npc_test_01", data)
        loaded = await state.load_entity("npc", "npc_test_01")
        assert loaded["name"] == "Test NPC"
        assert loaded["hp"] == 50

    async def test_upsert_entity(self, state: StateTools) -> None:
        """Saving an entity with the same type+id should update it."""
        await state.save_entity("item", "item_01", {"name": "Old Name"})
        await state.save_entity("item", "item_01", {"name": "New Name"})
        loaded = await state.load_entity("item", "item_01")
        assert loaded["name"] == "New Name"

    async def test_load_missing_entity_raises(self, state: StateTools) -> None:
        with pytest.raises(KeyError, match="No entity"):
            await state.load_entity("npc", "nonexistent")

    async def test_query_entities_by_type(self, state: StateTools) -> None:
        await state.save_entity("npc", "npc_a", {"name": "Alice", "role": "merchant"})
        await state.save_entity("npc", "npc_b", {"name": "Bob", "role": "guard"})
        await state.save_entity("item", "item_a", {"name": "Sword"})

        npcs = await state.query_entities("npc")
        assert len(npcs) == 2

        items = await state.query_entities("item")
        assert len(items) == 1

    async def test_query_entities_with_filters(self, state: StateTools) -> None:
        await state.save_entity("npc", "npc_a", {"name": "Alice", "role": "merchant"})
        await state.save_entity("npc", "npc_b", {"name": "Bob", "role": "guard"})

        merchants = await state.query_entities("npc", filters={"role": "merchant"})
        assert len(merchants) == 1
        assert merchants[0]["name"] == "Alice"


# ---------------------------------------------------------------------------
# Project CRUD
# ---------------------------------------------------------------------------


class TestProjectPersistence:
    async def test_save_and_load_project(
        self, state: StateTools, minimal_project: GameProject
    ) -> None:
        row_id = await state.save_project(minimal_project)
        assert row_id > 0

        loaded = await state.load_project(row_id)
        assert loaded.concept.title == "Test Game"

    async def test_save_project_upsert(
        self, state: StateTools, minimal_project: GameProject
    ) -> None:
        """Saving a project with the same title should update in place."""
        id1 = await state.save_project(minimal_project)
        id2 = await state.save_project(minimal_project)
        assert id1 == id2

    async def test_load_missing_project_raises(self, state: StateTools) -> None:
        with pytest.raises(KeyError, match="No project"):
            await state.load_project(9999)

    async def test_list_projects(
        self, state: StateTools, minimal_project: GameProject
    ) -> None:
        await state.save_project(minimal_project)
        projects = await state.list_projects()
        assert len(projects) == 1
        assert projects[0]["name"] == "Test Game"

    async def test_delete_project(
        self, state: StateTools, minimal_project: GameProject
    ) -> None:
        row_id = await state.save_project(minimal_project)
        # Also save associated entities
        await state.save_entity("npc", "npc_01", {"name": "Test"}, project_id=row_id)

        await state.delete_project(row_id)

        with pytest.raises(KeyError):
            await state.load_project(row_id)

        # Associated entities should also be deleted
        entities = await state.query_entities("npc")
        assert len(entities) == 0


# ---------------------------------------------------------------------------
# Generation log
# ---------------------------------------------------------------------------


class TestGenerationLog:
    async def test_log_and_complete(
        self, state: StateTools, minimal_project: GameProject
    ) -> None:
        pid = await state.save_project(minimal_project)
        log_id = await state.log_generation_step(pid, "world_building", "started")
        assert log_id > 0

        await state.complete_generation_step(log_id, "completed", "Built 3 regions")

        db = state._ensure_db()
        rows = await db.execute_fetchall(
            "SELECT status, detail FROM generation_log WHERE id = ?", (log_id,)
        )
        assert rows[0][0] == "completed"
        assert rows[0][1] == "Built 3 regions"
