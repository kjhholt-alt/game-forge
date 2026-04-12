"""High-level tools for creating and managing Godot scenes.

All operations go through the :class:`~tools.godot_bridge.GodotBridge`,
which forwards them as MCP tool calls to the running Godot editor.
"""

from __future__ import annotations

import logging
from pathlib import PurePosixPath
from typing import Any

from tools.godot_bridge import GodotBridge

logger = logging.getLogger(__name__)


class SceneTools:
    """High-level tools for creating and managing Godot scenes.

    Parameters
    ----------
    bridge:
        An active :class:`GodotBridge` connected to the Godot MCP server.
    project_path:
        Absolute path to the Godot project directory on disk (the folder
        that contains ``project.godot``).
    """

    def __init__(self, bridge: GodotBridge, project_path: str) -> None:
        self._bridge = bridge
        self._project_path = project_path

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def _res_path(self, relative: str) -> str:
        """Ensure *relative* starts with ``res://`` for Godot resource paths."""
        if relative.startswith("res://"):
            return relative
        # Strip leading slashes/dots for safety
        clean = relative.lstrip("./\\")
        return f"res://{clean}"

    # ------------------------------------------------------------------
    # Scene CRUD
    # ------------------------------------------------------------------

    async def create_scene(
        self,
        name: str,
        root_type: str = "Node2D",
    ) -> str:
        """Create a new ``.tscn`` scene file in the project.

        Parameters
        ----------
        name:
            Scene name (without extension).  Stored under ``scenes/<name>.tscn``.
        root_type:
            Godot node type for the scene root (e.g. ``Node2D``,
            ``Control``, ``CharacterBody2D``).

        Returns
        -------
        str
            The ``res://`` path to the created scene.
        """
        scene_path = self._res_path(f"scenes/{name}.tscn")
        logger.info("Creating scene %s (root=%s)", scene_path, root_type)
        await self._bridge.call_tool(
            "create_scene",
            {"path": scene_path, "root_type": root_type},
        )
        return scene_path

    async def add_node(
        self,
        scene_path: str,
        node_name: str,
        node_type: str,
        parent: str = ".",
        properties: dict[str, Any] | None = None,
    ) -> None:
        """Add a node to an existing scene.

        Parameters
        ----------
        scene_path:
            ``res://`` path to the target scene.
        node_name:
            Name for the new node.
        node_type:
            Godot node class (e.g. ``Sprite2D``, ``CollisionShape2D``).
        parent:
            Node-path of the parent within the scene tree.  ``"."`` is the
            scene root.
        properties:
            Optional dict of property names to values to set on the node
            after creation.
        """
        scene_path = self._res_path(scene_path)
        args: dict[str, Any] = {
            "scene_path": scene_path,
            "node_name": node_name,
            "node_type": node_type,
            "parent": parent,
        }
        if properties:
            args["properties"] = properties

        logger.debug("add_node %s → %s (%s)", node_name, scene_path, node_type)
        await self._bridge.call_tool("add_node", args)

    async def set_node_property(
        self,
        scene_path: str,
        node_path: str,
        property_name: str,
        value: Any,
    ) -> None:
        """Set a single property on a node inside a scene.

        Parameters
        ----------
        scene_path:
            ``res://`` path to the scene.
        node_path:
            Path to the node within the scene tree.
        property_name:
            Godot property name (e.g. ``"position"``, ``"texture"``).
        value:
            The value to assign.  Scalars, arrays, and dicts are forwarded
            as-is and the Godot MCP server handles type conversion.
        """
        scene_path = self._res_path(scene_path)
        logger.debug(
            "set_node_property %s:%s.%s = %r",
            scene_path,
            node_path,
            property_name,
            value,
        )
        await self._bridge.call_tool(
            "set_node_property",
            {
                "scene_path": scene_path,
                "node_path": node_path,
                "property": property_name,
                "value": value,
            },
        )

    # ------------------------------------------------------------------
    # Composite scene builders
    # ------------------------------------------------------------------

    async def create_tilemap_scene(
        self,
        name: str,
        tileset_path: str,
        tile_data: list[dict[str, Any]],
    ) -> str:
        """Create a TileMap scene with pre-placed tiles.

        Parameters
        ----------
        name:
            Scene name (without extension).
        tileset_path:
            ``res://`` path to the ``.tres`` TileSet resource.
        tile_data:
            List of dicts, each containing ``x``, ``y``, ``source_id``,
            ``atlas_coords`` (list of two ints) for each placed tile.

        Returns
        -------
        str
            ``res://`` scene path.
        """
        scene_path = await self.create_scene(name, root_type="Node2D")

        # Add TileMapLayer (Godot 4.x uses TileMapLayer)
        await self.add_node(
            scene_path,
            node_name="TileMapLayer",
            node_type="TileMapLayer",
            properties={"tile_set": tileset_path},
        )

        # Place tiles via a dedicated MCP tool (batch)
        if tile_data:
            await self._bridge.call_tool(
                "set_tilemap_cells",
                {
                    "scene_path": scene_path,
                    "layer_node": "TileMapLayer",
                    "cells": tile_data,
                },
            )

        logger.info("Created TileMap scene %s (%d tiles)", scene_path, len(tile_data))
        return scene_path

    async def create_character_scene(
        self,
        name: str,
        sprite_path: str,
        collision_shape: dict[str, Any],
        scripts: list[str] | None = None,
    ) -> str:
        """Create a character scene (``CharacterBody2D``) with sprite and collision.

        Parameters
        ----------
        name:
            Scene name.
        sprite_path:
            ``res://`` path to the character sprite image.
        collision_shape:
            Dict describing the collision shape. Must include ``"type"``
            (e.g. ``"rectangle"``, ``"circle"``) and dimensions such as
            ``"width"``/``"height"`` or ``"radius"``.
        scripts:
            Optional list of ``res://`` paths to GDScript files to attach.
            The first script is attached to the root node.

        Returns
        -------
        str
            ``res://`` scene path.
        """
        scene_path = await self.create_scene(name, root_type="CharacterBody2D")

        # Sprite
        await self.add_node(
            scene_path,
            node_name="Sprite2D",
            node_type="Sprite2D",
            properties={"texture": sprite_path},
        )

        # Collision shape
        shape_props: dict[str, Any] = {"shape_type": collision_shape.get("type", "rectangle")}
        shape_type = collision_shape.get("type", "rectangle")
        if shape_type == "rectangle":
            shape_props["extents"] = [
                collision_shape.get("width", 16) / 2,
                collision_shape.get("height", 16) / 2,
            ]
        elif shape_type == "circle":
            shape_props["radius"] = collision_shape.get("radius", 8)
        elif shape_type == "capsule":
            shape_props["radius"] = collision_shape.get("radius", 8)
            shape_props["height"] = collision_shape.get("height", 32)

        await self.add_node(
            scene_path,
            node_name="CollisionShape2D",
            node_type="CollisionShape2D",
            properties=shape_props,
        )

        # Attach scripts
        if scripts:
            await self.set_node_property(
                scene_path,
                node_path=".",
                property_name="script",
                value=self._res_path(scripts[0]),
            )
            for i, script in enumerate(scripts[1:], start=1):
                logger.debug("Extra script %d not auto-attached (Godot limitation): %s", i, script)

        logger.info("Created character scene %s", scene_path)
        return scene_path

    async def create_ui_scene(
        self,
        name: str,
        layout: dict[str, Any],
    ) -> str:
        """Create a UI scene from a declarative layout description.

        Parameters
        ----------
        name:
            Scene name.
        layout:
            Nested dict describing the UI tree.  Each node has::

                {
                    "type": "VBoxContainer",   # Godot Control node type
                    "name": "Root",            # optional, defaults to type name
                    "properties": {},          # optional property overrides
                    "children": [...]          # nested nodes
                }

        Returns
        -------
        str
            ``res://`` scene path.
        """
        root_type = layout.get("type", "Control")
        scene_path = await self.create_scene(name, root_type=root_type)

        # Set root properties
        root_props = layout.get("properties")
        if root_props:
            for prop, val in root_props.items():
                await self.set_node_property(scene_path, ".", prop, val)

        # Recursively add children
        children = layout.get("children", [])
        await self._add_ui_children(scene_path, ".", children)

        logger.info("Created UI scene %s", scene_path)
        return scene_path

    async def _add_ui_children(
        self,
        scene_path: str,
        parent_path: str,
        children: list[dict[str, Any]],
    ) -> None:
        """Recursively add child nodes from the UI layout tree."""
        for child in children:
            node_type = child.get("type", "Control")
            node_name = child.get("name", node_type)
            properties = child.get("properties")

            await self.add_node(
                scene_path,
                node_name=node_name,
                node_type=node_type,
                parent=parent_path,
                properties=properties,
            )

            # Build the node path for this child
            if parent_path == ".":
                child_path = node_name
            else:
                child_path = f"{parent_path}/{node_name}"

            # Recurse
            nested = child.get("children", [])
            if nested:
                await self._add_ui_children(scene_path, child_path, nested)

    # ------------------------------------------------------------------
    # Queries
    # ------------------------------------------------------------------

    async def list_scenes(self) -> list[str]:
        """List all ``.tscn`` files in the Godot project.

        Returns
        -------
        list[str]
            List of ``res://`` scene paths.
        """
        result = await self._bridge.call_tool(
            "list_files",
            {"extension": ".tscn"},
        )
        scenes: list[str] = result.get("files", [])
        logger.debug("Found %d scenes", len(scenes))
        return scenes
