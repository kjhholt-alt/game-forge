"""Tools for managing game state during generation and testing.

State is stored in SQLite via :pypi:`aiosqlite` and acts as the single
source of truth — the LLM never gets to hallucinate state.  Every entity
the pipeline produces is tracked here.
"""

from __future__ import annotations

import json
import logging
from datetime import datetime, timezone
from typing import Any

import aiosqlite

from schemas import GameProject, WorldDefinition

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# SQL DDL
# ---------------------------------------------------------------------------

_CREATE_TABLES = """
CREATE TABLE IF NOT EXISTS projects (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT NOT NULL,
    data        TEXT NOT NULL,           -- full GameProject JSON
    created_at  TEXT NOT NULL,
    updated_at  TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS worlds (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id  INTEGER,
    name        TEXT NOT NULL,
    data        TEXT NOT NULL,           -- full WorldDefinition JSON
    created_at  TEXT NOT NULL,
    FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS entities (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    entity_type     TEXT NOT NULL,       -- 'npc', 'item', 'quest', etc.
    entity_id       TEXT NOT NULL,       -- caller-defined unique ID within type
    project_id      INTEGER,
    data            TEXT NOT NULL,       -- arbitrary JSON payload
    created_at      TEXT NOT NULL,
    updated_at      TEXT NOT NULL,
    UNIQUE(entity_type, entity_id)
);

CREATE TABLE IF NOT EXISTS generation_log (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id  INTEGER,
    step        TEXT NOT NULL,           -- pipeline step name
    status      TEXT NOT NULL DEFAULT 'started',  -- started, completed, failed
    detail      TEXT,                    -- freeform notes / error messages
    created_at  TEXT NOT NULL,
    completed_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_entities_type ON entities(entity_type);
CREATE INDEX IF NOT EXISTS idx_entities_type_id ON entities(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_generation_log_project ON generation_log(project_id);
"""


def _now() -> str:
    """ISO-8601 UTC timestamp."""
    return datetime.now(timezone.utc).isoformat()


# ---------------------------------------------------------------------------
# StateTools
# ---------------------------------------------------------------------------


class StateTools:
    """Async interface to the GameForge state database.

    Parameters
    ----------
    db_path:
        Path to the SQLite database file.  Created automatically if it
        does not exist.
    """

    def __init__(self, db_path: str) -> None:
        self._db_path = db_path
        self._db: aiosqlite.Connection | None = None

    # ------------------------------------------------------------------
    # Lifecycle
    # ------------------------------------------------------------------

    async def initialize(self) -> None:
        """Open the database and create tables if they do not exist."""
        self._db = await aiosqlite.connect(self._db_path)
        self._db.row_factory = aiosqlite.Row
        await self._db.executescript(_CREATE_TABLES)
        await self._db.commit()
        logger.info("State database initialized at %s", self._db_path)

    async def close(self) -> None:
        """Close the database connection."""
        if self._db is not None:
            await self._db.close()
            self._db = None
            logger.info("State database closed")

    def _ensure_db(self) -> aiosqlite.Connection:
        """Return the open connection or raise."""
        if self._db is None:
            raise RuntimeError("StateTools not initialized — call initialize() first")
        return self._db

    # ------------------------------------------------------------------
    # World
    # ------------------------------------------------------------------

    async def save_world(self, world: WorldDefinition, project_id: int | None = None) -> int:
        """Persist a :class:`WorldDefinition` and return its row ID.

        Parameters
        ----------
        world:
            The world to save.
        project_id:
            Optional owning project ID.

        Returns
        -------
        int
            The database row ID of the saved world.
        """
        db = self._ensure_db()
        now = _now()
        cursor = await db.execute(
            "INSERT INTO worlds (project_id, name, data, created_at) VALUES (?, ?, ?, ?)",
            (project_id, world.name, world.model_dump_json(), now),
        )
        await db.commit()
        row_id = cursor.lastrowid
        assert row_id is not None
        logger.info("Saved world '%s' (id=%d)", world.name, row_id)
        return row_id

    async def load_world(self, world_id: int) -> WorldDefinition:
        """Load a :class:`WorldDefinition` by its database ID.

        Raises
        ------
        KeyError
            If no world with that ID exists.
        """
        db = self._ensure_db()
        row = await db.execute_fetchall(
            "SELECT data FROM worlds WHERE id = ?", (world_id,)
        )
        if not row:
            raise KeyError(f"No world with id={world_id}")
        return WorldDefinition.model_validate_json(row[0][0])

    # ------------------------------------------------------------------
    # Entities (generic)
    # ------------------------------------------------------------------

    async def save_entity(
        self,
        entity_type: str,
        entity_id: str,
        data: dict[str, Any],
        project_id: int | None = None,
    ) -> None:
        """Upsert a game entity (NPC, item, quest, etc.).

        Parameters
        ----------
        entity_type:
            Category string (e.g. ``"npc"``, ``"item"``, ``"quest"``).
        entity_id:
            Caller-defined unique identifier within the type.
        data:
            Arbitrary JSON-serialisable payload.
        project_id:
            Optional owning project ID.
        """
        db = self._ensure_db()
        now = _now()
        json_data = json.dumps(data, default=str)
        await db.execute(
            """
            INSERT INTO entities (entity_type, entity_id, project_id, data, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(entity_type, entity_id) DO UPDATE SET
                data = excluded.data,
                updated_at = excluded.updated_at
            """,
            (entity_type, entity_id, project_id, json_data, now, now),
        )
        await db.commit()
        logger.debug("Saved entity %s/%s", entity_type, entity_id)

    async def load_entity(self, entity_type: str, entity_id: str) -> dict[str, Any]:
        """Load a single entity by type and ID.

        Raises
        ------
        KeyError
            If the entity does not exist.
        """
        db = self._ensure_db()
        rows = await db.execute_fetchall(
            "SELECT data FROM entities WHERE entity_type = ? AND entity_id = ?",
            (entity_type, entity_id),
        )
        if not rows:
            raise KeyError(f"No entity {entity_type}/{entity_id}")
        return json.loads(rows[0][0])

    async def query_entities(
        self,
        entity_type: str,
        filters: dict[str, Any] | None = None,
    ) -> list[dict[str, Any]]:
        """Query entities of a given type, with optional JSON-field filters.

        Parameters
        ----------
        entity_type:
            The entity category to query.
        filters:
            Dict of ``{json_field: expected_value}`` applied via
            ``json_extract``.  All conditions are ANDed.

        Returns
        -------
        list[dict]
            Matching entity data payloads.
        """
        db = self._ensure_db()
        query = "SELECT data FROM entities WHERE entity_type = ?"
        params: list[Any] = [entity_type]

        if filters:
            for key, value in filters.items():
                query += f" AND json_extract(data, '$.{key}') = ?"
                params.append(value)

        rows = await db.execute_fetchall(query, params)
        return [json.loads(r[0]) for r in rows]

    # ------------------------------------------------------------------
    # Projects
    # ------------------------------------------------------------------

    async def save_project(self, project: GameProject) -> int:
        """Persist a :class:`GameProject` and return its row ID.

        If the project's concept title matches an existing row, the
        existing row is updated.
        """
        db = self._ensure_db()
        now = _now()
        json_data = project.model_dump_json()

        # Check for existing project by name
        existing = await db.execute_fetchall(
            "SELECT id FROM projects WHERE name = ?", (project.concept.title,)
        )

        if existing:
            row_id = existing[0][0]
            await db.execute(
                "UPDATE projects SET data = ?, updated_at = ? WHERE id = ?",
                (json_data, now, row_id),
            )
            await db.commit()
            logger.info("Updated project '%s' (id=%d)", project.concept.title, row_id)
            return row_id

        cursor = await db.execute(
            "INSERT INTO projects (name, data, created_at, updated_at) VALUES (?, ?, ?, ?)",
            (project.concept.title, json_data, now, now),
        )
        await db.commit()
        row_id = cursor.lastrowid
        assert row_id is not None
        logger.info("Saved project '%s' (id=%d)", project.concept.title, row_id)
        return row_id

    async def load_project(self, project_id: int) -> GameProject:
        """Load a :class:`GameProject` by database ID.

        Raises
        ------
        KeyError
            If no project with that ID exists.
        """
        db = self._ensure_db()
        rows = await db.execute_fetchall(
            "SELECT data FROM projects WHERE id = ?", (project_id,)
        )
        if not rows:
            raise KeyError(f"No project with id={project_id}")
        return GameProject.model_validate_json(rows[0][0])

    async def list_projects(self) -> list[dict[str, Any]]:
        """Return summary information for all saved projects.

        Each item contains ``id``, ``name``, ``created_at``, ``updated_at``.
        """
        db = self._ensure_db()
        rows = await db.execute_fetchall(
            "SELECT id, name, created_at, updated_at FROM projects ORDER BY updated_at DESC"
        )
        return [
            {
                "id": r[0],
                "name": r[1],
                "created_at": r[2],
                "updated_at": r[3],
            }
            for r in rows
        ]

    async def delete_project(self, project_id: int) -> None:
        """Delete a project and all associated entities and worlds.

        Parameters
        ----------
        project_id:
            The database ID of the project to remove.
        """
        db = self._ensure_db()
        await db.execute("DELETE FROM entities WHERE project_id = ?", (project_id,))
        await db.execute("DELETE FROM worlds WHERE project_id = ?", (project_id,))
        await db.execute("DELETE FROM generation_log WHERE project_id = ?", (project_id,))
        await db.execute("DELETE FROM projects WHERE id = ?", (project_id,))
        await db.commit()
        logger.info("Deleted project id=%d and associated data", project_id)

    # ------------------------------------------------------------------
    # Generation log
    # ------------------------------------------------------------------

    async def log_generation_step(
        self,
        project_id: int,
        step: str,
        status: str = "started",
        detail: str | None = None,
    ) -> int:
        """Record a pipeline generation step.

        Parameters
        ----------
        project_id:
            Owning project.
        step:
            Step name (e.g. ``"world_building"``, ``"quest_design"``).
        status:
            ``"started"``, ``"completed"``, or ``"failed"``.
        detail:
            Optional freeform notes or error message.

        Returns
        -------
        int
            The log entry row ID.
        """
        db = self._ensure_db()
        now = _now()
        completed_at = now if status in ("completed", "failed") else None
        cursor = await db.execute(
            """
            INSERT INTO generation_log (project_id, step, status, detail, created_at, completed_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (project_id, step, status, detail, now, completed_at),
        )
        await db.commit()
        row_id = cursor.lastrowid
        assert row_id is not None
        return row_id

    async def complete_generation_step(
        self,
        log_id: int,
        status: str = "completed",
        detail: str | None = None,
    ) -> None:
        """Mark a previously-started generation step as completed or failed."""
        db = self._ensure_db()
        now = _now()
        await db.execute(
            "UPDATE generation_log SET status = ?, detail = ?, completed_at = ? WHERE id = ?",
            (status, detail, now, log_id),
        )
        await db.commit()
