"""Tools for generating and managing GDScript files in the Godot project.

Handles writing, reading, and programmatically generating ``.gd`` files
through the MCP bridge as well as direct filesystem access when needed.
"""

from __future__ import annotations

import logging
import re
from typing import Any

from tools.godot_bridge import GodotBridge

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# GDScript validation
# ---------------------------------------------------------------------------

# Minimal syntax checks — not a full parser, just catches the most common
# mistakes before we ship content to Godot.
_GDSCRIPT_KEYWORDS = frozenset({
    "extends", "class_name", "var", "const", "func", "signal", "enum",
    "if", "elif", "else", "for", "while", "match", "break", "continue",
    "return", "pass", "class", "static", "export", "onready", "await",
    "self", "super", "true", "false", "null", "void", "preload", "load",
})

_EXTENDS_RE = re.compile(r"^extends\s+\w+", re.MULTILINE)


def _validate_gdscript_basics(content: str) -> list[str]:
    """Run basic sanity checks on *content*.

    Returns a list of warning strings (empty == OK).  This is NOT a full
    syntax check — Godot does that — but it catches things like missing
    ``extends`` or unmatched indentation levels.
    """
    warnings: list[str] = []

    stripped = content.strip()
    if not stripped:
        warnings.append("Script content is empty")
        return warnings

    # Every GDScript should have an extends declaration
    if not _EXTENDS_RE.search(stripped):
        warnings.append("Missing 'extends' declaration — Godot scripts should extend a base class")

    # Check for spaces-as-indentation (Godot uses tabs)
    for lineno, line in enumerate(stripped.splitlines(), start=1):
        if line and line[0] == " " and not line.lstrip().startswith("#"):
            warnings.append(
                f"Line {lineno}: leading spaces detected — GDScript uses tabs for indentation"
            )
            break  # one warning is enough

    return warnings


# ---------------------------------------------------------------------------
# GDScript code generation helpers
# ---------------------------------------------------------------------------

def _build_export_line(export: dict[str, Any]) -> str:
    """Build an ``@export`` variable declaration from a structured dict.

    Expected keys: ``name`` (str), ``type`` (str), ``default`` (optional).
    """
    name = export["name"]
    gdtype = export.get("type", "Variant")
    default = export.get("default")

    line = f"@export var {name}: {gdtype}"
    if default is not None:
        line += f" = {_gdscript_literal(default)}"
    return line


def _build_method(method: dict[str, Any]) -> str:
    """Build a ``func`` block from a structured dict.

    Expected keys: ``name`` (str), ``args`` (list[str], optional),
    ``body`` (str, optional — defaults to ``"pass"``).
    """
    name = method["name"]
    args = ", ".join(method.get("args", []))
    body = method.get("body", "pass")

    lines = [f"func {_func_name(name)}({args}):"]
    for body_line in body.splitlines():
        lines.append(f"\t{body_line}" if body_line.strip() else "")
    return "\n".join(lines)


def _func_name(name: str) -> str:
    """Ensure lifecycle methods get the underscore prefix."""
    lifecycle = {"ready", "process", "physics_process", "input", "enter_tree", "exit_tree"}
    if name in lifecycle:
        return f"_{name}"
    return name


def _gdscript_literal(value: Any) -> str:
    """Convert a Python value to its GDScript literal representation."""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, str):
        return f'"{value}"'
    if isinstance(value, list):
        items = ", ".join(_gdscript_literal(v) for v in value)
        return f"[{items}]"
    if isinstance(value, dict):
        items = ", ".join(
            f"{_gdscript_literal(k)}: {_gdscript_literal(v)}" for k, v in value.items()
        )
        return "{" + items + "}"
    if value is None:
        return "null"
    return repr(value)


# ---------------------------------------------------------------------------
# ScriptTools
# ---------------------------------------------------------------------------


class ScriptTools:
    """Tools for generating and managing GDScript files in the Godot project.

    Parameters
    ----------
    bridge:
        Active :class:`GodotBridge` instance.
    project_path:
        Absolute path to the Godot project root on disk.
    """

    def __init__(self, bridge: GodotBridge, project_path: str) -> None:
        self._bridge = bridge
        self._project_path = project_path

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def _res_path(self, relative: str) -> str:
        """Ensure *relative* uses the ``res://`` prefix."""
        if relative.startswith("res://"):
            return relative
        clean = relative.lstrip("./\\")
        return f"res://{clean}"

    # ------------------------------------------------------------------
    # CRUD
    # ------------------------------------------------------------------

    async def write_script(self, path: str, content: str) -> None:
        """Write a GDScript file to the Godot project.

        Runs basic syntax validation before writing.  Warnings are logged
        but do **not** prevent the write — Godot is the final arbiter.

        Parameters
        ----------
        path:
            ``res://`` or relative path for the script (e.g.
            ``"scripts/player.gd"``).
        content:
            Full GDScript source code.
        """
        warnings = _validate_gdscript_basics(content)
        for w in warnings:
            logger.warning("GDScript validation (%s): %s", path, w)

        res_path = self._res_path(path)
        logger.info("Writing script %s (%d chars)", res_path, len(content))
        await self._bridge.call_tool(
            "write_file",
            {"path": res_path, "content": content},
        )

    async def read_script(self, path: str) -> str:
        """Read an existing GDScript file and return its contents.

        Parameters
        ----------
        path:
            ``res://`` or relative path to the ``.gd`` file.

        Returns
        -------
        str
            The script source code.
        """
        res_path = self._res_path(path)
        result = await self._bridge.call_tool(
            "read_file",
            {"path": res_path},
        )
        return result.get("content", "")

    async def append_to_script(self, path: str, content: str) -> None:
        """Append content to an existing GDScript file.

        Useful for adding new methods or signal handlers to a script that
        was previously generated.

        Parameters
        ----------
        path:
            ``res://`` or relative path to the ``.gd`` file.
        content:
            GDScript code to append (typically one or more ``func`` blocks).
        """
        existing = await self.read_script(path)
        separator = "\n\n" if existing.rstrip() else ""
        merged = existing.rstrip() + separator + content + "\n"
        await self.write_script(path, merged)

    # ------------------------------------------------------------------
    # Code generation
    # ------------------------------------------------------------------

    async def generate_script(
        self,
        class_name: str,
        extends: str,
        signals: list[str] | None = None,
        exports: list[dict[str, Any]] | None = None,
        methods: list[dict[str, Any]] | None = None,
    ) -> str:
        """Generate a GDScript from a structured definition and write it.

        Parameters
        ----------
        class_name:
            Name for the script (also used as the filename under
            ``scripts/``).
        extends:
            Base class to extend (e.g. ``"CharacterBody2D"``).
        signals:
            Signal names to declare (e.g. ``["health_changed", "died"]``).
        exports:
            Export variable definitions.  Each dict should contain ``name``
            (str), ``type`` (str), and optionally ``default``.
        methods:
            Method definitions.  Each dict should contain ``name`` (str),
            ``args`` (list[str], optional), ``body`` (str, optional).

        Returns
        -------
        str
            The generated GDScript source code.
        """
        parts: list[str] = []

        # Header
        parts.append(f"extends {extends}")
        parts.append(f'class_name {class_name}')
        parts.append("")

        # Signals
        if signals:
            for sig in signals:
                parts.append(f"signal {sig}")
            parts.append("")

        # Exports
        if exports:
            for exp in exports:
                parts.append(_build_export_line(exp))
            parts.append("")

        # Methods
        if methods:
            for meth in methods:
                parts.append("")
                parts.append(_build_method(meth))

        # Ensure trailing newline
        source = "\n".join(parts).rstrip() + "\n"

        # Write to project
        script_path = f"scripts/{class_name}.gd"
        await self.write_script(script_path, source)

        logger.info("Generated script %s (%d lines)", script_path, source.count("\n"))
        return source

    # ------------------------------------------------------------------
    # Autoloads
    # ------------------------------------------------------------------

    async def create_autoload(self, name: str, script_content: str) -> None:
        """Create a GDScript autoload (singleton) and register it.

        Writes the script to ``scripts/autoloads/<name>.gd`` and calls the
        MCP server to register the autoload in ``project.godot``.

        Parameters
        ----------
        name:
            Autoload name — this becomes the global singleton accessor in
            GDScript (e.g. ``GameManager``).
        script_content:
            Full GDScript source for the autoload.
        """
        script_path = f"scripts/autoloads/{name}.gd"
        await self.write_script(script_path, script_content)

        res_path = self._res_path(script_path)
        await self._bridge.call_tool(
            "register_autoload",
            {"name": name, "path": res_path},
        )
        logger.info("Registered autoload %s → %s", name, res_path)

    # ------------------------------------------------------------------
    # Queries
    # ------------------------------------------------------------------

    async def list_scripts(self) -> list[str]:
        """List all ``.gd`` files in the Godot project.

        Returns
        -------
        list[str]
            List of ``res://`` script paths.
        """
        result = await self._bridge.call_tool(
            "list_files",
            {"extension": ".gd"},
        )
        scripts: list[str] = result.get("files", [])
        logger.debug("Found %d scripts", len(scripts))
        return scripts
