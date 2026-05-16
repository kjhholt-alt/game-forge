extends Node
## Global event bus. Systems emit events here, other systems listen.
## Decouples game systems so they don't need direct references to each other.

# -----------------------------------------------------------------------
# Dialogue
# -----------------------------------------------------------------------

signal dialogue_started(npc_id: String)
signal dialogue_ended(npc_id: String)

# -----------------------------------------------------------------------
# Combat
# -----------------------------------------------------------------------

signal combat_started(encounter_data: Dictionary)
signal combat_ended(result: String)  # "victory", "defeat", "fled"

# -----------------------------------------------------------------------
# World / Navigation
# -----------------------------------------------------------------------

signal room_entered(room_id: String)
signal room_exited(room_id: String)

# -----------------------------------------------------------------------
# Items
# -----------------------------------------------------------------------

signal item_obtained(item_data: Dictionary)
signal item_used(item_data: Dictionary)

# -----------------------------------------------------------------------
# Enemies / NPCs
# -----------------------------------------------------------------------

signal enemy_defeated(enemy_id: String)
signal npc_interacted(npc_id: String)

# -----------------------------------------------------------------------
# Quests
# -----------------------------------------------------------------------

signal quest_started(quest_id: String)
signal quest_completed(quest_id: String)
signal quest_failed(quest_id: String)

# -----------------------------------------------------------------------
# Player
# -----------------------------------------------------------------------

signal player_died()
signal player_respawned()

# -----------------------------------------------------------------------
# System
# -----------------------------------------------------------------------

signal game_saved(slot: int)
signal game_loaded(slot: int)
signal notification(message: String, type: String)  # "info", "warning", "error"

# -----------------------------------------------------------------------
# MCP / Agent commands
# -----------------------------------------------------------------------

signal mcp_command_received(command: Dictionary)
signal mcp_state_requested()
