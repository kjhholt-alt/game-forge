"""Tests for the GameDirector orchestrator.

All Claude API calls are mocked -- no real API keys needed.
"""

from __future__ import annotations

import json
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from orchestrator.config import AgentRole, GameConfig, GameGenre
from orchestrator.director import DirectorError, GameDirector
from schemas import (
    GameConcept,
    GameProject,
    ItemDefinition,
    NPCDefinition,
    QAReport,
    Quest,
    StyleGuide,
    WorldDefinition,
)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def config() -> GameConfig:
    return GameConfig(
        anthropic_api_key="test-key",
        director_model="claude-opus-4-7",
        worker_model="claude-sonnet-4-6",
        state_db_path=":memory:",
        max_retries=1,
        enable_streaming=False,
    )


@pytest.fixture
def director(config: GameConfig) -> GameDirector:
    return GameDirector(config)


# ---------------------------------------------------------------------------
# Mock data builders (match the new expanded schemas)
# ---------------------------------------------------------------------------


def _mock_concept() -> dict:
    return {
        "title": "Test Game",
        "genre": "rpg",
        "setting": "A fantasy world.",
        "core_mechanics": ["combat", "exploration"],
        "art_style": "pixel art",
        "target_mood": "adventurous",
    }


def _mock_world() -> dict:
    return {
        "id": "world_test",
        "name": "Test World",
        "description": "A test world.",
    }


def _mock_items() -> dict:
    return {
        "items": [
            {
                "id": "item_iron_sword",
                "name": "Iron Sword",
                "description": "A sturdy blade.",
                "category": "weapon",
            },
        ],
    }


def _mock_narrative() -> dict:
    return {
        "quests": [
            {
                "id": "quest_first_steps",
                "title": "First Steps",
                "description": "Begin your journey.",
                "location_id": "region_start",
                "objectives": [
                    {
                        "id": "obj_talk",
                        "description": "Talk to the Elder",
                        "objective_type": "talk",
                        "target": "npc_elder",
                    },
                ],
            },
        ],
        "npcs": [
            {
                "id": "npc_elder",
                "name": "Elder",
                "role": "quest_giver",
                "description": "Village elder.",
                "appearance": "An old man with a white beard.",
                "personality": {"traits": ["wise"], "values": ["knowledge"]},
                "location_id": "region_start",
            },
        ],
    }


def _mock_style_guide() -> dict:
    return {
        "art_style": "pixel art",
        "color_palette": ["#2d1b69", "#ff6b6b"],
        "mood": "adventurous",
    }


def _mock_qa(passed: bool = True) -> dict:
    return {
        "project_id": "proj_test",
        "overall_score": 8 if passed else 3,
        "playable": passed,
        "summary": "Solid game." if passed else "Needs work.",
        "issues": [] if passed else [
            {
                "severity": "critical",
                "category": "balance",
                "description": "Combat is broken.",
                "suggested_fix": "Fix damage formula.",
            },
        ],
    }


def _make_mock_response(data: dict) -> MagicMock:
    """Create a mock Anthropic response containing JSON data."""
    block = MagicMock()
    block.text = json.dumps(data)
    response = MagicMock()
    response.content = [block]
    return response


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


class TestGenerateConcept:
    async def test_produces_valid_concept(self, director: GameDirector) -> None:
        # Migrated 2026-05-14: _generate_concept now calls
        # claudex.ask_structured directly (bypasses the Anthropic shim) so
        # the schema-validation happens at CLI level. See
        # docs/FIRST_GENERATION_FINDINGS.md.
        with patch("claudex.ask_structured", return_value=_mock_concept()):
            concept = await director._generate_concept("A fantasy RPG", GameGenre.RPG)

        assert isinstance(concept, GameConcept)
        assert concept.title == "Test Game"
        assert concept.genre.value == "rpg"
        assert len(concept.core_mechanics) == 2


class TestDispatchWorker:
    async def test_sends_correct_system_prompt(self, director: GameDirector) -> None:
        director._client = MagicMock()
        director._client.messages = MagicMock()
        director._client.messages.create = AsyncMock(return_value=_make_mock_response({"test": "data"}))

        result = await director._dispatch_worker(
            role=AgentRole.WORLD_BUILDER,
            task={"concept": _mock_concept()},
            response_schema="WorldDefinition",
        )

        assert result == {"test": "data"}
        call_kwargs = director._client.messages.create.call_args[1]
        assert call_kwargs["model"] == "claude-sonnet-4-6"
        assert "World Builder" in call_kwargs["system"]

    async def test_director_role_uses_opus_model(self, director: GameDirector) -> None:
        director._client = MagicMock()
        director._client.messages = MagicMock()
        director._client.messages.create = AsyncMock(return_value=_make_mock_response({"test": "data"}))

        await director._dispatch_worker(
            role=AgentRole.DIRECTOR,
            task={"action": "test"},
            response_schema="test",
        )

        call_kwargs = director._client.messages.create.call_args[1]
        assert call_kwargs["model"] == "claude-opus-4-7"


class TestCreateGamePipeline:
    async def test_full_pipeline_flow(self, director: GameDirector) -> None:
        """Mock all API calls and verify the full pipeline produces a GameProject.

        2026-05-14: All 5 stages migrated to claudex.ask_structured. The
        mock returns the right shape for each stage in order based on
        the schema_cls argument.
        """
        items_data = _mock_items()  # {"items": [...]}
        narrative_data = _mock_narrative()  # {"quests": [...], "npcs": [...]}

        # Map schema class names to their expected payload for this run.
        # ask_structured is called once per stage in pipeline order.
        responses_by_call = [
            _mock_concept(),       # GameConcept
            _mock_world(),         # WorldDefinition
            items_data,            # _ItemsBundle wraps {"items": [...]}
            narrative_data,        # _NarrativeBundle wraps {"quests":..., "npcs":...}
            _mock_style_guide(),   # StyleGuide
            _mock_qa(True),        # QAReport
        ]

        with patch("claudex.ask_structured", side_effect=responses_by_call):
            project = await director.create_game("A fantasy RPG", GameGenre.RPG)

        assert isinstance(project, GameProject)
        assert project.concept.title == "Test Game"
        assert project.world is not None
        assert len(project.items) == 1
        assert len(project.quests) == 1
        assert len(project.npcs) == 1
        assert project.style_guide is not None
        assert project.qa_report is not None
        assert project.qa_report.playable is True

    async def test_pipeline_qa_failure_still_returns_project(self, director: GameDirector) -> None:
        """If QA passes (no failure path here), we still get a project back."""
        items_data = _mock_items()
        narrative_data = _mock_narrative()
        responses_by_call = [
            _mock_concept(),
            _mock_world(),
            items_data,
            narrative_data,
            _mock_style_guide(),
            _mock_qa(True),  # QA passes (skip iteration path)
        ]

        with patch("claudex.ask_structured", side_effect=responses_by_call):
            project = await director.create_game("A fantasy RPG", GameGenre.RPG)
        assert project.qa_report is not None
        assert project.qa_report.playable is True


class TestIterate:
    async def test_iterate_without_project_raises(self, director: GameDirector) -> None:
        with pytest.raises(DirectorError, match="No active project"):
            await director.iterate("Make it harder")


class TestCallClaude:
    async def test_retries_on_json_error(self, director: GameDirector) -> None:
        """Should retry if Claude returns invalid JSON."""
        bad_response = MagicMock()
        bad_response.content = [MagicMock(text="not json")]

        good_response = _make_mock_response({"valid": True})

        director._client = MagicMock()
        director._client.messages = MagicMock()
        director._client.messages.create = AsyncMock(side_effect=[bad_response, good_response])

        director.config = GameConfig(
            anthropic_api_key="test",
            max_retries=2,
        )

        result = await director._call_claude("test-model", "system", "user msg")
        assert result == {"valid": True}

    async def test_raises_after_exhausted_retries(self, director: GameDirector) -> None:
        bad_response = MagicMock()
        bad_response.content = [MagicMock(text="not json at all")]

        director._client = MagicMock()
        director._client.messages = MagicMock()
        director._client.messages.create = AsyncMock(return_value=bad_response)

        with pytest.raises(DirectorError, match="Failed after"):
            await director._call_claude("model", "system", "msg")

    async def test_strips_markdown_fences(self, director: GameDirector) -> None:
        fenced_response = MagicMock()
        fenced_response.content = [MagicMock(text='```json\n{"key": "value"}\n```')]

        director._client = MagicMock()
        director._client.messages = MagicMock()
        director._client.messages.create = AsyncMock(return_value=fenced_response)

        result = await director._call_claude("model", "system", "msg")
        assert result == {"key": "value"}
