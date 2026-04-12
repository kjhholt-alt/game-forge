"""ArtDirector agent -- generates art direction and asset descriptions.

Uses Claude Sonnet to produce comprehensive style guides, tileset
descriptions, character art specs, UI element descriptions, and scene
compositions.  These descriptions are formatted as prompts suitable for
feeding into image generation models (Stable Diffusion, DALL-E, Midjourney).
"""

from __future__ import annotations

import json
import logging
from typing import Any

import anthropic

from schemas.combat import (
    CharacterArtDescription,
    StyleGuide,
    TilesetDescription,
    UIArtDescription,
)
from schemas.npc import NPCDefinition
from schemas.project import GameConcept

logger = logging.getLogger(__name__)


class ArtDirector:
    """Generates art direction and asset descriptions for AI image generation.

    Every public method makes one or more Claude API calls with an art-direction-focused
    system prompt and returns validated Pydantic models or structured descriptions
    optimized for image generation pipelines.
    """

    SYSTEM_PROMPT: str = """\
You are an expert **art director and concept artist** working inside GameForge,
an AI-powered game development toolkit that outputs 2-D Godot projects.

Your sole job is to create detailed visual specifications that can be fed to
image generation models (Stable Diffusion, DALL-E, Midjourney) or used as
briefs for pixel artists.  You think in color theory, composition, mood
boards, and visual storytelling.

Art direction principles you MUST follow:
1. **Visual consistency** -- every asset must feel like it belongs in the same
   game.  Maintain consistent line weight, color temperature, saturation levels,
   and texture density across all descriptions.  Reference the style guide in
   every prompt.
2. **Color palette discipline** -- define a limited palette (8-12 core colors)
   and stick to it.  Use warm/cool contrast for gameplay readability (warm =
   interactive, cool = background).  Every color should have a defined usage
   role.
3. **Readability at target size** -- sprites will be viewed at 16-64px.
   Designs must have clear silhouettes, high-contrast outlines, and
   distinguishable poses even at small sizes.  Avoid fine detail that becomes
   mud at low resolution.
4. **Mood through lighting** -- lighting direction, shadow depth, and ambient
   glow communicate mood more effectively than subject matter.  Define
   lighting style per biome/scene type.
5. **Character distinctiveness** -- every character should be identifiable by
   silhouette alone.  Use distinctive shapes (tall/short, wide/narrow),
   signature colors, and unique accessories.  Avoid "same face syndrome."
6. **Tileset completeness** -- tilesets must cover: base terrain, edges (all 4
   sides + corners), transitions to adjacent biomes, animated elements
   (water, lava, grass sway), and decorative variants to break repetition.
7. **UI clarity** -- game UI should be instantly readable.  Health bars need
   clear empty/full states.  Buttons need hover/pressed/disabled states.
   Icons should communicate function without text labels.
8. **Prompt engineering** -- write descriptions optimized for AI image generators:
   start with the most important visual elements, include style keywords,
   specify camera angle/framing, mention art medium (pixel art, watercolor,
   etc.), and list negative attributes to avoid.
9. **Cultural sensitivity** -- avoid stereotypes, culturally insensitive imagery,
   or designs that appropriate sacred symbols.  Fantasy races and cultures
   should be original, not thinly-veiled real-world caricatures.
10. **Animation readiness** -- for animated assets, describe key frames and
    motion arcs.  Sprite sheets need consistent anchor points and frame counts.

Output rules:
- Respond ONLY with the requested JSON object -- no commentary, no markdown fences.
- Every ``id`` field must be a unique, URL-safe slug (lowercase, hyphens).
- Art descriptions should be 2-5 sentences of vivid, specific visual language.
- Use the schemas provided in each prompt exactly; do not invent extra fields.
"""

    # ------------------------------------------------------------------
    # Construction
    # ------------------------------------------------------------------

    def __init__(self, client: anthropic.AsyncAnthropic, model: str = "claude-sonnet-4-6") -> None:
        self._client = client
        self._model = model

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    async def create_style_guide(self, concept: GameConcept) -> StyleGuide:
        """Create a comprehensive art style guide for the game.

        Produces a StyleGuide with color palette, line weight, texture style,
        lighting, mood, and reference material that all other art generation
        methods should reference for consistency.
        """
        schema = StyleGuide.model_json_schema()

        user_msg = (
            f"Create a comprehensive art style guide for this game:\n\n"
            f"{concept.model_dump_json(indent=2)}\n\n"
            f"Requirements:\n"
            f"- Define the primary art style (pixel art bit-depth, hand-drawn medium, etc.)\n"
            f"- Color palette with 8-12 hex codes and usage notes for each\n"
            f"- Line weight guidance (thin for pixel, bold for cartoon, etc.)\n"
            f"- Texture style (clean/noisy/hand-drawn/dithered)\n"
            f"- Lighting direction and shadow style per mood category\n"
            f"- Mood description that matches the game's target_mood\n"
            f"- 3-5 reference games with similar visual aesthetics\n"
            f"- Palette should support: UI elements, friendly NPCs, hostile enemies,\n"
            f"  environmental features, and interactive objects\n\n"
            f"Respond with a JSON object matching this schema:\n"
            f"{json.dumps(schema, indent=2)}"
        )

        raw = await self._call(user_msg)
        return StyleGuide.model_validate(raw)

    async def describe_tileset(
        self,
        biome: str,
        style_guide: StyleGuide,
    ) -> TilesetDescription:
        """Generate detailed descriptions for each tile in a tileset.

        Parameters
        ----------
        biome:
            The biome/environment type (e.g. "forest", "cave", "desert").
        style_guide:
            The game's art style guide for consistency.
        """
        schema = TilesetDescription.model_json_schema()

        user_msg = (
            f"Generate a tileset description for the '{biome}' biome:\n\n"
            f"Style guide:\n{style_guide.model_dump_json(indent=2)}\n\n"
            f"Requirements:\n"
            f"- Include these tile categories:\n"
            f"  - Base ground tiles (2-3 variants to avoid repetition)\n"
            f"  - Wall/boundary tiles (top, bottom, left, right, corners)\n"
            f"  - Transition tiles (to adjacent biome types)\n"
            f"  - Decorative elements (rocks, bushes, cracks, debris)\n"
            f"  - Interactive elements (doors, chests, switches, signs)\n"
            f"  - Animated elements (water, torches, flags, grass sway)\n"
            f"  - Hazard tiles (spikes, lava, poison pools)\n"
            f"- Each tile description should be an image-generation-ready prompt\n"
            f"- Reference the style guide's color palette and art_style\n"
            f"- Include tile_size appropriate for the style\n"
            f"- Tile names should be descriptive slugs (e.g., 'grass-base-01')\n\n"
            f"Respond with a JSON object matching this schema:\n"
            f"{json.dumps(schema, indent=2)}"
        )

        raw = await self._call(user_msg)
        return TilesetDescription.model_validate(raw)

    async def describe_character(
        self,
        npc: NPCDefinition,
        style_guide: StyleGuide,
    ) -> CharacterArtDescription:
        """Generate detailed character art description (portrait, sprite sheet, expressions).

        Parameters
        ----------
        npc:
            The NPC to create art descriptions for.
        style_guide:
            The game's art style guide for consistency.
        """
        schema = CharacterArtDescription.model_json_schema()

        user_msg = (
            f"Generate character art descriptions for this NPC:\n\n"
            f"NPC:\n{npc.model_dump_json(indent=2)}\n\n"
            f"Style guide:\n{style_guide.model_dump_json(indent=2)}\n\n"
            f"Requirements:\n"
            f"- Portrait description: full-detail bust portrait prompt (face, expression,\n"
            f"  clothing, accessories, background, lighting)\n"
            f"- Sprite description: in-game sprite sheet prompt (idle pose, clear\n"
            f"  silhouette, signature colors, readable at small size)\n"
            f"- Expression descriptions for: neutral, happy, angry, sad, surprised,\n"
            f"  and any expressions specific to their personality\n"
            f"- All descriptions must reference the style guide's art_style and palette\n"
            f"- Character should be instantly recognizable by silhouette\n"
            f"- Include distinctive visual hooks (scars, unique hat, glowing eyes, etc.)\n"
            f"- Clothing should reflect their role and social status\n\n"
            f"Respond with a JSON object matching this schema:\n"
            f"{json.dumps(schema, indent=2)}"
        )

        raw = await self._call(user_msg)
        return CharacterArtDescription.model_validate(raw)

    async def describe_ui_elements(
        self,
        concept: GameConcept,
        style_guide: StyleGuide,
    ) -> UIArtDescription:
        """Generate descriptions for UI elements (health bars, menus, icons).

        Produces a complete UI art specification covering all interactive
        and informational elements the game needs.
        """
        schema = UIArtDescription.model_json_schema()

        user_msg = (
            f"Generate UI art descriptions for this game:\n\n"
            f"Concept:\n{concept.model_dump_json(indent=2)}\n\n"
            f"Style guide:\n{style_guide.model_dump_json(indent=2)}\n\n"
            f"Requirements:\n"
            f"- Cover these essential UI elements:\n"
            f"  - Health bar (with empty, low, medium, full states)\n"
            f"  - Mana/resource bar\n"
            f"  - Experience bar\n"
            f"  - Inventory grid slots (empty, occupied, selected, locked)\n"
            f"  - Dialogue box (background, name plate, next-arrow)\n"
            f"  - Button states (default, hover, pressed, disabled)\n"
            f"  - Menu backgrounds (main menu, pause, settings)\n"
            f"  - Minimap frame\n"
            f"  - Tooltip background\n"
            f"  - Quest tracker panel\n"
            f"  - Notification/toast\n"
            f"- Include overall theme description\n"
            f"- Reference style guide colors and mood\n"
            f"- UI should be readable on both light and dark backgrounds\n"
            f"- Include icon_style guidance for item/skill icons\n"
            f"- Mention recommended font characteristics (serif, pixel, clean)\n\n"
            f"Respond with a JSON object matching this schema:\n"
            f"{json.dumps(schema, indent=2)}"
        )

        raw = await self._call(user_msg)
        return UIArtDescription.model_validate(raw)

    async def generate_scene_description(
        self,
        location: str,
        mood: str,
        style_guide: StyleGuide,
    ) -> str:
        """Generate a detailed scene/background description for image generation.

        Parameters
        ----------
        location:
            The location name or ID (e.g. "moonlit-forest-clearing", "abandoned-mine-entrance").
        mood:
            The emotional tone for the scene (e.g. "eerie", "peaceful", "tense").
        style_guide:
            The game's art style guide for consistency.

        Returns
        -------
        str
            A detailed image-generation-ready prompt for the scene background.
        """
        user_msg = (
            f"Generate a detailed scene description for image generation:\n\n"
            f"- Location: {location}\n"
            f"- Mood: {mood}\n"
            f"- Style guide:\n{style_guide.model_dump_json(indent=2)}\n\n"
            f"Requirements:\n"
            f"- Write a single detailed image generation prompt (3-6 sentences)\n"
            f"- Include: environment, lighting, color temperature, atmospheric effects\n"
            f"- Reference the style guide's art_style and color_palette\n"
            f"- Mention camera angle/perspective (side-scrolling, top-down, etc.)\n"
            f"- Include foreground, midground, and background layers\n"
            f"- Mention the art medium (pixel art, digital painting, etc.)\n"
            f"- Include what to AVOID (negative prompt elements)\n\n"
            f"Respond with a JSON object: {{\"scene_prompt\": \"...\", \"negative_prompt\": \"...\"}}"
        )

        raw = await self._call(user_msg)

        if isinstance(raw, dict):
            prompt = raw.get("scene_prompt", "")
            negative = raw.get("negative_prompt", "")
            if negative:
                return f"{prompt}\n\nNegative: {negative}"
            return str(prompt)

        return str(raw)

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    async def _call(self, user_message: str, max_retries: int = 3) -> dict[str, Any]:
        """Make a Claude API call and parse the JSON response.

        Retries on transient API errors and JSON parse failures.
        """
        last_error: Exception | None = None

        for attempt in range(1, max_retries + 1):
            try:
                logger.debug(
                    "ArtDirector API call attempt %d/%d (model=%s)",
                    attempt, max_retries, self._model,
                )

                response = await self._client.messages.create(
                    model=self._model,
                    max_tokens=8192,
                    system=self.SYSTEM_PROMPT,
                    messages=[{"role": "user", "content": user_message}],
                )

                text = self._extract_text(response)
                parsed = json.loads(text)
                logger.info("ArtDirector call succeeded on attempt %d", attempt)
                return parsed  # type: ignore[no-any-return]

            except json.JSONDecodeError as exc:
                logger.warning(
                    "ArtDirector attempt %d/%d: invalid JSON -- %s",
                    attempt, max_retries, exc,
                )
                last_error = exc

            except anthropic.APIStatusError as exc:
                logger.warning(
                    "ArtDirector attempt %d/%d: API status error %d -- %s",
                    attempt, max_retries, exc.status_code, exc.message,
                )
                last_error = exc
                if exc.status_code == 401:
                    raise

            except anthropic.APIConnectionError as exc:
                logger.warning(
                    "ArtDirector attempt %d/%d: connection error -- %s",
                    attempt, max_retries, exc,
                )
                last_error = exc

        raise RuntimeError(
            f"ArtDirector failed after {max_retries} attempts. Last error: {last_error}"
        )

    @staticmethod
    def _extract_text(response: anthropic.types.Message) -> str:
        """Pull the text content from a Claude response and strip code fences."""
        text = ""
        for block in response.content:
            if hasattr(block, "text"):
                text += block.text

        text = text.strip()

        if text.startswith("```"):
            first_newline = text.index("\n")
            text = text[first_newline + 1:]
        if text.endswith("```"):
            text = text[:-3]

        return text.strip()
