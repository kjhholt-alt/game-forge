"""Tools for generating and managing game assets via AI image/audio generation.

When no image-generation API key is configured the tools fall back to
Pillow-based placeholder sprites so that the rest of the pipeline can
keep running without blocking on external services.
"""

from __future__ import annotations

import logging
import os
from pathlib import Path
from typing import Any

import httpx
from PIL import Image, ImageDraw, ImageFont

from tools.godot_bridge import GodotBridge

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

_ASSET_CATEGORIES = ("sprites", "tilesets", "portraits", "audio", "ui")

_REPLICATE_API_URL = "https://api.replicate.com/v1/predictions"
_REPLICATE_POLL_INTERVAL = 2.0  # seconds
_REPLICATE_TIMEOUT = 120.0  # seconds


# ---------------------------------------------------------------------------
# AssetTools
# ---------------------------------------------------------------------------


class AssetTools:
    """Tools for generating and managing game assets.

    The primary path uses the Replicate API to run FLUX (or similar
    models) for pixel-art generation.  When ``REPLICATE_API_TOKEN`` is
    not set, every ``generate_*`` method transparently falls back to a
    Pillow placeholder so the pipeline keeps moving.

    Parameters
    ----------
    output_dir:
        Root directory for generated assets (typically the Godot
        project's ``assets/`` folder).
    bridge:
        Optional :class:`GodotBridge` for triggering Godot import scans
        after new assets are written to disk.
    """

    def __init__(
        self,
        output_dir: str,
        bridge: GodotBridge | None = None,
    ) -> None:
        self._output_dir = Path(output_dir)
        self._bridge = bridge
        self._replicate_token: str | None = os.environ.get("REPLICATE_API_TOKEN")

        # Ensure category directories exist
        for cat in _ASSET_CATEGORIES:
            (self._output_dir / cat).mkdir(parents=True, exist_ok=True)

    # ------------------------------------------------------------------
    # Internal — Replicate
    # ------------------------------------------------------------------

    async def _replicate_generate(
        self,
        prompt: str,
        width: int,
        height: int,
        style: str,
    ) -> bytes | None:
        """Call the Replicate API.  Returns raw image bytes or *None* on failure."""
        if not self._replicate_token:
            logger.debug("No REPLICATE_API_TOKEN — skipping Replicate call")
            return None

        full_prompt = f"{style} style, game asset, {prompt}"
        payload = {
            "version": "black-forest-labs/flux-schnell",
            "input": {
                "prompt": full_prompt,
                "width": width,
                "height": height,
                "num_outputs": 1,
            },
        }
        headers = {
            "Authorization": f"Token {self._replicate_token}",
            "Content-Type": "application/json",
        }

        try:
            async with httpx.AsyncClient(timeout=_REPLICATE_TIMEOUT) as client:
                # Start the prediction
                resp = await client.post(_REPLICATE_API_URL, json=payload, headers=headers)
                resp.raise_for_status()
                prediction = resp.json()

                # Poll until completed
                poll_url = prediction.get("urls", {}).get("get", "")
                if not poll_url:
                    logger.warning("Replicate response missing poll URL")
                    return None

                import asyncio
                while True:
                    await asyncio.sleep(_REPLICATE_POLL_INTERVAL)
                    poll_resp = await client.get(poll_url, headers=headers)
                    poll_resp.raise_for_status()
                    status_data = poll_resp.json()
                    status = status_data.get("status", "")

                    if status == "succeeded":
                        output = status_data.get("output", [])
                        if output:
                            img_resp = await client.get(output[0])
                            img_resp.raise_for_status()
                            return img_resp.content
                        return None
                    elif status in ("failed", "canceled"):
                        error = status_data.get("error", "unknown")
                        logger.warning("Replicate prediction failed: %s", error)
                        return None
        except (httpx.HTTPError, Exception) as exc:
            logger.warning("Replicate API call failed: %s", exc)
            return None

    # ------------------------------------------------------------------
    # Internal — Pillow placeholders
    # ------------------------------------------------------------------

    def _create_placeholder(
        self,
        label: str,
        size: tuple[int, int],
        color: tuple[int, int, int],
        dest: Path,
    ) -> Path:
        """Create a coloured placeholder PNG with a text label."""
        img = Image.new("RGBA", size, (*color, 255))
        draw = ImageDraw.Draw(img)

        # Draw a border to make it visible
        border_color = (
            min(color[0] + 60, 255),
            min(color[1] + 60, 255),
            min(color[2] + 60, 255),
            255,
        )
        draw.rectangle(
            [0, 0, size[0] - 1, size[1] - 1],
            outline=border_color,
            width=max(1, min(size[0], size[1]) // 16),
        )

        # Draw a diagonal cross so it's clearly a placeholder
        draw.line([(0, 0), (size[0] - 1, size[1] - 1)], fill=border_color, width=1)
        draw.line([(size[0] - 1, 0), (0, size[1] - 1)], fill=border_color, width=1)

        # Draw the label text
        text = label[:20]  # truncate to avoid overflow
        try:
            font = ImageFont.truetype("arial.ttf", max(8, min(size[0], size[1]) // 4))
        except (OSError, IOError):
            font = ImageFont.load_default()

        # Centre the text
        bbox = draw.textbbox((0, 0), text, font=font)
        text_w = bbox[2] - bbox[0]
        text_h = bbox[3] - bbox[1]
        text_x = (size[0] - text_w) // 2
        text_y = (size[1] - text_h) // 2

        # Text shadow for readability
        draw.text((text_x + 1, text_y + 1), text, fill=(0, 0, 0, 180), font=font)
        draw.text((text_x, text_y), text, fill=(255, 255, 255, 255), font=font)

        dest.parent.mkdir(parents=True, exist_ok=True)
        img.save(str(dest), "PNG")
        logger.debug("Created placeholder %s (%dx%d)", dest.name, *size)
        return dest

    # ------------------------------------------------------------------
    # Public API — Generation
    # ------------------------------------------------------------------

    async def generate_sprite(
        self,
        description: str,
        size: tuple[int, int] = (64, 64),
        style: str = "pixel-art",
    ) -> str:
        """Generate a sprite image from a text description.

        Attempts the Replicate FLUX API first.  Falls back to a Pillow
        placeholder if no API key is configured or the call fails.

        Parameters
        ----------
        description:
            Natural-language description of the sprite.
        size:
            Width and height in pixels.
        style:
            Art style hint (e.g. ``"pixel-art"``, ``"hand-drawn"``).

        Returns
        -------
        str
            Absolute path to the generated image file.
        """
        safe_name = _safe_filename(description)
        dest = self._output_dir / "sprites" / f"{safe_name}.png"

        # Try Replicate first
        img_bytes = await self._replicate_generate(description, size[0], size[1], style)
        if img_bytes is not None:
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(img_bytes)
            logger.info("Generated sprite via Replicate: %s", dest)
            await self._trigger_reimport()
            return str(dest)

        # Fallback: placeholder
        self._create_placeholder(description, size, (100, 149, 237), dest)
        logger.info("Created placeholder sprite: %s", dest)
        await self._trigger_reimport()
        return str(dest)

    async def generate_tileset(
        self,
        descriptions: dict[str, str],
        tile_size: int = 16,
        style: str = "pixel-art",
    ) -> str:
        """Generate a tileset atlas from per-tile descriptions.

        Parameters
        ----------
        descriptions:
            Mapping of tile names to visual descriptions (e.g.
            ``{"grass": "lush green grass", "water": "calm blue water"}``).
        tile_size:
            Size of each tile in pixels (square).
        style:
            Art style hint.

        Returns
        -------
        str
            Absolute path to the generated tileset atlas PNG.
        """
        tile_count = len(descriptions)
        if tile_count == 0:
            raise ValueError("descriptions must contain at least one tile")

        # Layout: single row for simplicity
        atlas_w = tile_size * tile_count
        atlas_h = tile_size
        atlas = Image.new("RGBA", (atlas_w, atlas_h), (0, 0, 0, 0))

        colors = [
            (34, 139, 34),    # green
            (65, 105, 225),   # blue
            (139, 69, 19),    # brown
            (169, 169, 169),  # gray
            (218, 165, 32),   # gold
            (220, 20, 60),    # red
            (147, 112, 219),  # purple
            (0, 206, 209),    # teal
        ]

        for i, (tile_name, desc) in enumerate(descriptions.items()):
            color = colors[i % len(colors)]

            # Try AI generation for each tile
            img_bytes = await self._replicate_generate(desc, tile_size, tile_size, style)
            if img_bytes is not None:
                import io
                tile_img = Image.open(io.BytesIO(img_bytes)).resize(
                    (tile_size, tile_size), Image.Resampling.NEAREST
                )
            else:
                # Placeholder tile
                tile_img = Image.new("RGBA", (tile_size, tile_size), (*color, 255))
                draw = ImageDraw.Draw(tile_img)
                draw.rectangle(
                    [0, 0, tile_size - 1, tile_size - 1],
                    outline=(255, 255, 255, 128),
                    width=1,
                )

            atlas.paste(tile_img, (i * tile_size, 0))

        safe_name = _safe_filename("_".join(descriptions.keys())[:40])
        dest = self._output_dir / "tilesets" / f"{safe_name}_tileset.png"
        dest.parent.mkdir(parents=True, exist_ok=True)
        atlas.save(str(dest), "PNG")

        logger.info("Generated tileset atlas: %s (%d tiles)", dest, tile_count)
        await self._trigger_reimport()
        return str(dest)

    async def generate_portrait(
        self,
        character_description: str,
        size: tuple[int, int] = (256, 256),
    ) -> str:
        """Generate a character portrait image.

        Parameters
        ----------
        character_description:
            Natural-language description of the character.
        size:
            Width and height in pixels.

        Returns
        -------
        str
            Absolute path to the generated portrait.
        """
        safe_name = _safe_filename(character_description)
        dest = self._output_dir / "portraits" / f"{safe_name}.png"

        img_bytes = await self._replicate_generate(
            f"character portrait, {character_description}",
            size[0],
            size[1],
            "fantasy illustration",
        )
        if img_bytes is not None:
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(img_bytes)
            logger.info("Generated portrait via Replicate: %s", dest)
            await self._trigger_reimport()
            return str(dest)

        # Placeholder: skin-toned circle on transparent background
        self._create_placeholder(character_description, size, (210, 180, 140), dest)
        logger.info("Created placeholder portrait: %s", dest)
        await self._trigger_reimport()
        return str(dest)

    async def create_placeholder_sprite(
        self,
        label: str,
        size: tuple[int, int],
        color: tuple[int, int, int] = (255, 0, 255),
    ) -> str:
        """Create a coloured placeholder sprite with a text label.

        Always uses Pillow (no API call).  Useful for rapid prototyping
        when you just need *something* visible in the scene.

        Parameters
        ----------
        label:
            Text to render on the sprite.
        size:
            Width and height in pixels.
        color:
            RGB background colour.

        Returns
        -------
        str
            Absolute path to the placeholder PNG.
        """
        safe_name = _safe_filename(label)
        dest = self._output_dir / "sprites" / f"{safe_name}_placeholder.png"
        self._create_placeholder(label, size, color, dest)
        await self._trigger_reimport()
        return str(dest)

    # ------------------------------------------------------------------
    # Public API — Asset management
    # ------------------------------------------------------------------

    async def import_asset(self, source_path: str, dest_category: str) -> str:
        """Copy an asset into the Godot project's asset directory.

        Parameters
        ----------
        source_path:
            Absolute path to the source file.
        dest_category:
            Target sub-directory under the assets root (e.g. ``"sprites"``,
            ``"audio"``).

        Returns
        -------
        str
            Absolute path to the imported asset.

        Raises
        ------
        FileNotFoundError
            If the source file does not exist.
        ValueError
            If the category is not recognised.
        """
        src = Path(source_path)
        if not src.exists():
            raise FileNotFoundError(f"Source asset not found: {source_path}")

        if dest_category not in _ASSET_CATEGORIES:
            raise ValueError(
                f"Unknown asset category '{dest_category}'. "
                f"Must be one of: {', '.join(_ASSET_CATEGORIES)}"
            )

        dest_dir = self._output_dir / dest_category
        dest_dir.mkdir(parents=True, exist_ok=True)
        dest = dest_dir / src.name

        # Copy the file
        import shutil
        shutil.copy2(str(src), str(dest))

        logger.info("Imported asset %s → %s", src.name, dest)
        await self._trigger_reimport()
        return str(dest)

    async def list_assets(self, category: str | None = None) -> list[str]:
        """List generated assets, optionally filtered by category.

        Parameters
        ----------
        category:
            One of ``"sprites"``, ``"tilesets"``, ``"portraits"``,
            ``"audio"``, ``"ui"``.  If *None*, list all categories.

        Returns
        -------
        list[str]
            Absolute paths to asset files.
        """
        categories = [category] if category else list(_ASSET_CATEGORIES)
        assets: list[str] = []

        for cat in categories:
            cat_dir = self._output_dir / cat
            if cat_dir.is_dir():
                for f in sorted(cat_dir.iterdir()):
                    if f.is_file() and not f.name.startswith("."):
                        assets.append(str(f))

        return assets

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    async def _trigger_reimport(self) -> None:
        """Ask Godot to re-scan its asset directory for newly-written files."""
        if self._bridge is None:
            return
        try:
            await self._bridge.call_tool("reimport_assets", {})
        except Exception as exc:
            logger.debug("reimport_assets call failed (non-critical): %s", exc)


# ---------------------------------------------------------------------------
# Module-level helpers
# ---------------------------------------------------------------------------


def _safe_filename(text: str, max_len: int = 48) -> str:
    """Convert arbitrary text into a filesystem-safe filename slug."""
    import re
    # Keep only alphanumeric, spaces, hyphens, underscores
    cleaned = re.sub(r"[^\w\s-]", "", text.lower())
    # Replace whitespace runs with underscores
    cleaned = re.sub(r"\s+", "_", cleaned.strip())
    # Truncate
    return cleaned[:max_len] or "unnamed"
