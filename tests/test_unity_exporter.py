"""Tests for deterministic Unity export generation.

Pure-Python: these never invoke Unity, so they keep CI green on any machine.
The headless-render gate (an actual Unity batchmode PNG) is run manually/locally.
"""

from __future__ import annotations

import json

from schemas import GameConcept, GameProject
from schemas.combat import QAIssue, QAReport
from orchestrator.unity_exporter import generate_unity_content


def _project_with_gap() -> GameProject:
    return GameProject(
        id="proj_unity_test",
        concept=GameConcept(
            title="Clockwork Test",
            genre="roguelike",
            setting="A small test station between worlds.",
            core_mechanics=["repair clocks", "solve spirit puzzles"],
            art_style="brass pixel art",
            target_mood="quiet",
        ),
        qa_report=QAReport(
            project_id="proj_unity_test",
            playable=False,
            overall_score=6.0,
            issues=[
                QAIssue(
                    severity="medium",
                    category="content",
                    description="No scenes or scripts have been generated yet.",
                    location="project.scenes_generated, project.scripts_generated",
                )
            ],
        ),
    )


def test_generate_unity_content_writes_scene_model_and_cs(tmp_path) -> None:
    project = _project_with_gap()

    scenes, scripts = generate_unity_content(project, tmp_path)

    # Return contract mirrors the Godot backend.
    assert "Assets/GameForge/Scenes/Generated.unity" in scenes
    assert any("GeneratedGameInfo.cs" in s for s in scripts)
    assert project.scenes_generated == scenes
    assert project.scripts_generated == scripts

    # Files actually written.
    scene_json = tmp_path / "Assets" / "StreamingAssets" / "gameforge_scene.json"
    generated_cs = tmp_path / "Assets" / "GameForge" / "Generated" / "GeneratedGameInfo.cs"
    assert scene_json.exists()
    assert generated_cs.exists()

    # Scene model carries the manifest's headline data + at least one play space.
    model = json.loads(scene_json.read_text(encoding="utf-8"))
    assert model["title"] == "Clockwork Test"
    assert model["genre"] == "roguelike"
    assert model["spaces"], "expected at least one play space"
    assert "qa" in model and model["qa"]["score"] == 6.0

    # Generated C# bakes the same data in as constants.
    cs = generated_cs.read_text(encoding="utf-8")
    assert "GeneratedGameInfo" in cs
    assert '"Clockwork Test"' in cs
    assert "SpaceNames" in cs

    # The "no scenes generated" QA gap is flipped to resolved, like the Godot path.
    assert project.qa_report is not None
    assert project.qa_report.issues[0].severity == "resolved"


def test_unity_play_spaces_match_world_rooms(tmp_path) -> None:
    """Regions + their rooms become play spaces (same extraction as Godot)."""
    from schemas.world import (
        Biome,
        OverworldMap,
        Region as WorldRegion,
        Room,
        RoomType,
        WorldDefinition,
    )

    room = Room(
        id="room_lab",
        name="Forgotten Lab",
        room_type=RoomType.COMBAT,
        description="Cracked vials line the shelves.",
    )
    region = WorldRegion(
        id="region_spire",
        name="The Spire",
        biome=Biome.RUINS,
        description="A leaning tower of clocks.",
        rooms=[room],
    )
    world = WorldDefinition(
        id="world_test",
        name="Test World",
        description="t",
        overworld=OverworldMap(
            regions=[region], connections=[], starting_region_id="region_spire"
        ),
    )
    project = GameProject(
        id="proj_unity_world",
        concept=GameConcept(
            title="Spire",
            genre="adventure",
            setting="ticking",
            core_mechanics=["wind the gears"],
            art_style="brass",
            target_mood="curious",
        ),
        world=world,
    )

    generate_unity_content(project, tmp_path)
    model = json.loads(
        (tmp_path / "Assets" / "StreamingAssets" / "gameforge_scene.json").read_text(encoding="utf-8")
    )
    names = [s["name"] for s in model["spaces"]]
    assert "The Spire" in names
    assert "Forgotten Lab" in names


def test_generated_info_cs_escapes_quotes(tmp_path) -> None:
    project = GameProject(
        id="proj_unity_escape",
        concept=GameConcept(
            title='Quote " Maker',
            genre="puzzle",
            setting="x",
            core_mechanics=["click"],
            art_style="flat",
            target_mood="wry",
        ),
    )

    generate_unity_content(project, tmp_path)
    cs = (tmp_path / "Assets" / "GameForge" / "Generated" / "GeneratedGameInfo.cs").read_text(
        encoding="utf-8"
    )
    # Embedded double-quote must be escaped so the C# compiles.
    assert '\\"' in cs
