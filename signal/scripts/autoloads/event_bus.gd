## Global signal bus for loose coupling between SIGNAL systems.
##
## All inter-system communication goes through signals here.
## No direct references between dashboard panels.
extends Node


# ---------------------------------------------------------------------------
# Phase transitions
# ---------------------------------------------------------------------------

## Emitted when transitioning between operation phases.
signal phase_changed(new_phase: String)  # "briefing", "signal", "blacksite", "debrief"

## Emitted when the player clicks "Go Dark" to enter BLACKSITE.
signal go_dark_requested(prep_score: float)

## Emitted when BLACKSITE ends (success or burned).
signal blacksite_ended(success: bool, burned: bool)

## Emitted when debrief is complete and player returns to campaign map.
signal debrief_complete(op_result: Dictionary)


# ---------------------------------------------------------------------------
# Evidence board
# ---------------------------------------------------------------------------

## Emitted when the player selects an evidence item on the board.
signal evidence_selected(evidence_id: String)

## Emitted when the player creates a connection between evidence items.
signal evidence_connected(from_id: String, to_id: String, connection_type: String)

## Emitted when a connection is removed.
signal evidence_disconnected(connection_id: String)

## Emitted when new intercepts arrive (handler drops them).
signal intercepts_received(evidence_ids: Array)

## Emitted when the player pins/unpins an evidence item.
signal evidence_pinned(evidence_id: String, pinned: bool)


# ---------------------------------------------------------------------------
# Document viewer
# ---------------------------------------------------------------------------

## Emitted to display a document in the viewer panel.
signal document_opened(evidence_id: String)

## Emitted when the viewer is closed/cleared.
signal document_closed()


# ---------------------------------------------------------------------------
# Terminal / hacking
# ---------------------------------------------------------------------------

## Emitted when the player executes a terminal command.
signal terminal_command(command: String, args: Array)

## Emitted when a terminal command produces output.
signal terminal_output(text: String, color: String)

## Emitted when the player successfully connects to a host.
signal host_connected(host_id: String)

## Emitted when a file is downloaded (exfiltrated).
signal file_exfiltrated(file_id: String)

## Emitted when a host is scanned/probed.
signal host_discovered(host_id: String)


# ---------------------------------------------------------------------------
# Social engineering
# ---------------------------------------------------------------------------

## Emitted when the player initiates conversation with an employee.
signal se_conversation_started(employee_id: String)

## Emitted when the player sends a message in social engineering.
signal se_message_sent(employee_id: String, message: String)

## Emitted when the NPC responds.
signal se_response_received(employee_id: String, response: String, trust_delta: int, suspicious: bool)

## Emitted when an employee reveals a secret.
signal se_secret_revealed(employee_id: String, secret: String)

## Emitted when the conversation ends.
signal se_conversation_ended(employee_id: String)


# ---------------------------------------------------------------------------
# Detection system
# ---------------------------------------------------------------------------

## Emitted when detection level changes.
signal detection_changed(level: String, value: float)  # level: green/yellow/red/black

## Emitted when the analyst is burned (detection hit BLACK).
signal analyst_burned()


# ---------------------------------------------------------------------------
# Comms / handler
# ---------------------------------------------------------------------------

## Emitted when the handler sends a message.
signal handler_message(text: String, priority: String)  # priority: normal, warning, critical

## Emitted when the handler sends a hint.
signal handler_hint(hint_text: String)


# ---------------------------------------------------------------------------
# RPG / progression
# ---------------------------------------------------------------------------

## Emitted when XP is gained.
signal xp_gained(skill_type: String, amount: int)

## Emitted when a skill levels up.
signal skill_leveled_up(skill_type: String, new_level: int)

## Emitted when a toolkit item is acquired.
signal toolkit_item_acquired(item_id: String)


# ---------------------------------------------------------------------------
# Campaign
# ---------------------------------------------------------------------------

## Emitted when a new operation is selected from the campaign map.
signal operation_selected(op_id: String)

## Emitted when a campaign is loaded.
signal campaign_loaded(campaign_id: String)
