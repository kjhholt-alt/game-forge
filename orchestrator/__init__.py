"""GameForge -- AI agents that build games, not just play them.

Public API
----------
``GameForge``   - High-level entry point for programmatic usage.
``GameConfig``  - Pydantic settings for the entire pipeline.
"""

from __future__ import annotations

__version__ = "0.1.0"

from orchestrator.config import GameConfig
from orchestrator.forge import GameForge
from schemas import GameGenre

__all__ = ["GameConfig", "GameForge", "GameGenre", "__version__"]
