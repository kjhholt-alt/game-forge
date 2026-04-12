"""GameForge CLI -- the ``forge`` command.

Built with Click.  All commands are async-safe via ``asyncio.run()``.
"""

from __future__ import annotations

import asyncio
import logging
import sys
from pathlib import Path

import click
from rich.console import Console
from rich.table import Table

from orchestrator.config import GameConfig
from orchestrator.forge import GameForge
from schemas import GameGenre

console = Console()


def _setup_logging(level: str) -> None:
    """Configure root logger for the CLI session."""
    logging.basicConfig(
        level=getattr(logging, level.upper(), logging.INFO),
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        datefmt="%H:%M:%S",
    )


def _get_forge(ctx: click.Context) -> GameForge:
    """Retrieve or create the GameForge instance from Click context."""
    if "forge" not in ctx.ensure_object(dict):
        config = GameConfig()
        if not config.anthropic_api_key:
            console.print(
                "[red bold]Error:[/red bold] ANTHROPIC_API_KEY is not set.\n"
                "Set it in your environment or in a .env file.",
            )
            sys.exit(1)
        _setup_logging(config.log_level)
        ctx.obj["forge"] = GameForge(config)
    return ctx.obj["forge"]


# ---------------------------------------------------------------------------
# CLI group
# ---------------------------------------------------------------------------

@click.group()
@click.version_option(version="0.1.0", prog_name="GameForge")
@click.pass_context
def main(ctx: click.Context) -> None:
    """GameForge -- AI agents that build games, not just play them."""
    ctx.ensure_object(dict)


# ---------------------------------------------------------------------------
# create
# ---------------------------------------------------------------------------

@main.command()
@click.argument("prompt")
@click.option(
    "--genre", "-g",
    type=click.Choice([g.value for g in GameGenre], case_sensitive=False),
    default="rpg",
    help="Target game genre.",
)
@click.pass_context
def create(ctx: click.Context, prompt: str, genre: str) -> None:
    """Create a new game from a natural-language prompt.

    Example:

        forge create "A roguelike dungeon crawler with AI companions" --genre roguelike
    """
    forge = _get_forge(ctx)
    game_genre = GameGenre(genre.lower())

    console.print(f"\n[bold cyan]GameForge[/bold cyan] -- creating a [bold]{genre}[/bold] game\n")

    project = asyncio.run(forge.create(prompt, game_genre))
    console.print(f"\n[bold green]Done![/bold green] '{project.concept.title}' is ready.")
    console.print("Run [bold]forge status[/bold] to see a summary, or [bold]forge export[/bold] to export.\n")


# ---------------------------------------------------------------------------
# iterate
# ---------------------------------------------------------------------------

@main.command()
@click.argument("feedback")
@click.pass_context
def iterate(ctx: click.Context, feedback: str) -> None:
    """Apply feedback to the current game project.

    Example:

        forge iterate "Make the combat harder and add a boss"
    """
    forge = _get_forge(ctx)

    console.print(f"\n[bold cyan]GameForge[/bold cyan] -- iterating on feedback\n")

    try:
        project = asyncio.run(forge.iterate(feedback))
        console.print(f"\n[bold green]Updated![/bold green] '{project.concept.title}' has been modified.\n")
    except RuntimeError as exc:
        console.print(f"[red bold]Error:[/red bold] {exc}")
        sys.exit(1)


# ---------------------------------------------------------------------------
# export
# ---------------------------------------------------------------------------

@main.command()
@click.option(
    "--output", "-o",
    type=click.Path(),
    default="./my-game",
    help="Output directory for the exported Godot project.",
)
@click.pass_context
def export(ctx: click.Context, output: str) -> None:
    """Export the current project as a Godot project directory.

    Example:

        forge export --output ./my-game
    """
    forge = _get_forge(ctx)

    try:
        out_path = forge.export(Path(output))
        console.print(f"\n[bold green]Exported![/bold green] Godot project at: {out_path}\n")
    except RuntimeError as exc:
        console.print(f"[red bold]Error:[/red bold] {exc}")
        sys.exit(1)


# ---------------------------------------------------------------------------
# status
# ---------------------------------------------------------------------------

@main.command()
@click.pass_context
def status(ctx: click.Context) -> None:
    """Show a summary of the current game project."""
    forge = _get_forge(ctx)
    info = forge.status()

    if info["status"] == "no_project":
        console.print("\n[yellow]No active project.[/yellow] Run [bold]forge create[/bold] first.\n")
        return

    table = Table(title=f"GameForge Project: {info['title']}", border_style="cyan")
    table.add_column("Property", style="bold")
    table.add_column("Value")

    table.add_row("Genre", str(info["genre"]))
    table.add_row("Regions", str(info["regions"]))
    table.add_row("Dungeons", str(info["dungeons"]))
    table.add_row("Quests", str(info["quests"]))
    table.add_row("NPCs", str(info["npcs"]))
    table.add_row("Items", str(info["items"]))
    table.add_row("Encounters", str(info["encounters"]))
    table.add_row("Style Guide", "Yes" if info["has_style_guide"] else "No")
    table.add_row("Scenes Generated", str(info["scenes_generated"]))
    table.add_row("Scripts Generated", str(info["scripts_generated"]))

    qa_status = "Not run"
    if info["qa_playable"] is not None:
        qa_status = (
            f"[green]Playable ({info['qa_score']}/10)[/green]"
            if info["qa_playable"]
            else f"[red]Not Playable ({info['qa_score']}/10)[/red]"
        )
    table.add_row("QA Status", qa_status)

    console.print()
    console.print(table)
    console.print()


if __name__ == "__main__":
    main()
