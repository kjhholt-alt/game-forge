"""GameForge configuration.

Uses pydantic-settings to load config from environment variables and .env
files. All tunables for the agent pipeline live here.
"""

from __future__ import annotations

from enum import Enum

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class AgentRole(str, Enum):
    """Roles an agent can assume inside the GameForge pipeline."""

    DIRECTOR = "director"
    WORLD_BUILDER = "world_builder"
    NARRATIVE = "narrative"
    MECHANICS = "mechanics"
    ART_DIRECTOR = "art_director"
    QA_TESTER = "qa_tester"

    # SIGNAL ops agents
    CAMPAIGN_ARCHITECT = "campaign_architect"
    INTEL_ARCHITECT = "intel_architect"
    TARGET_PROFILER = "target_profiler"
    NETWORK_DESIGNER = "network_designer"
    SIGNAL_QA_VALIDATOR = "signal_qa_validator"


class GameGenre(str, Enum):
    """Supported game genres."""

    RPG = "rpg"
    ROGUELIKE = "roguelike"
    PLATFORMER = "platformer"
    PUZZLE = "puzzle"
    STRATEGY = "strategy"
    ADVENTURE = "adventure"


class GameConfig(BaseSettings):
    """Central configuration for every GameForge session.

    Values are loaded in priority order from explicit kwargs, ``FORGE_``
    environment variables, then a ``.env`` file in the working directory.
    """

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # --- Claude transport ---
    # Calls go through claudex (Max-sub `claude -p` subprocess). No API key
    # fields are loaded or required.
    llm_backend: str = Field(
        default="claude-cli",
        description="Model transport. Currently 'claude-cli' via claudex.",
    )

    # --- Models ---
    director_model: str = Field(
        default="claude-opus-4-7",
        description="Model used by the Director (Opus-tier coordinator).",
    )
    worker_model: str = Field(
        default="claude-sonnet-4-6",
        description="Model used by worker agents (WorldBuilder, Narrative, etc.).",
    )
    fast_model: str = Field(
        default="claude-haiku-4-5",
        description="Model used for fast, low-cost tasks (summaries, validation).",
    )

    # --- Godot / MCP ---
    godot_mcp_url: str = Field(
        default="ws://localhost:6100",
        description="WebSocket URL for the Godot MCP bridge server.",
    )
    godot_project_path: str = Field(
        default="./godot_template",
        description="Path to the Godot project template directory.",
    )

    # --- Unity ---
    unity_project_path: str = Field(
        default="./unity_template",
        description="Path to the Unity 6 project template directory (C# scene-builder backend).",
    )

    # --- Storage ---
    state_db_path: str = Field(
        default="./game_state.db",
        description="SQLite database for persisting project state between runs.",
    )
    asset_output_dir: str = Field(
        default="./godot_template/assets",
        description="Directory where generated assets are written.",
    )

    # --- Behaviour ---
    max_retries: int = Field(
        default=3,
        ge=1,
        le=10,
        description="Max retries for a failed agent task before giving up.",
    )
    enable_streaming: bool = Field(
        default=True,
        description="Stream Claude responses token-by-token to the console.",
    )
    log_level: str = Field(
        default="INFO",
        description="Logging verbosity (DEBUG, INFO, WARNING, ERROR).",
    )

    # --- Hermes integration ---
    hermes_review_enabled: bool = Field(
        default=False,
        description=(
            "After QA, submit the assembled GameProject to Hermes for an "
            "independent codex-based audit. Off by default; requires "
            "hermes installed + codex CLI on PATH."
        ),
    )
