"""Tests for deterministic Godot export generation."""

from __future__ import annotations

from schemas import GameConcept, GameProject
from schemas.combat import QAIssue, QAReport
from orchestrator.godot_exporter import generate_godot_content


def test_generate_godot_content_writes_game_specific_files(tmp_path) -> None:
    project = GameProject(
        id="proj_export_test",
        concept=GameConcept(
            title="Clockwork Test",
            genre="roguelike",
            setting="A small test station between worlds.",
            core_mechanics=["repair clocks", "solve spirit puzzles"],
            art_style="brass pixel art",
            target_mood="quiet",
        ),
        qa_report=QAReport(
            project_id="proj_export_test",
            playable=False,
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
    (tmp_path / "project.godot").write_text(
        'run/main_scene="res://scenes/main/main.tscn"\n',
        encoding="utf-8",
    )

    scenes, scripts = generate_godot_content(project, tmp_path)

    assert "res://scenes/generated/generated_game.tscn" in scenes
    assert "res://scripts/generated/gameplay_loop.gd" in scripts
    assert project.qa_report is not None
    assert project.qa_report.issues[0].severity == "resolved"
    assert project.scenes_generated == scenes
    assert project.scripts_generated == scripts
    assert (tmp_path / "scenes" / "generated" / "generated_game.tscn").exists()
    assert (tmp_path / "scripts" / "generated" / "gameplay_loop.gd").exists()
    assert 'run/main_scene="res://scenes/generated/generated_game.tscn"' in (
        tmp_path / "project.godot"
    ).read_text(encoding="utf-8")
