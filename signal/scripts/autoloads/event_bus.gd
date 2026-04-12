## Event bus — war room signals for loose coupling between systems.
extends Node

# --- Map interactions ---
signal blip_clicked(blip_id: String)
signal blip_classified(blip_id: String, classification: String)
signal blip_spawned(blip_id: String)

# --- Decisions ---
signal coa_requested(blip_id: String)         # Player right-clicked a target
signal coa_selected(blip_id: String, coa_id: String)  # Player picked an option

# --- Assets ---
signal asset_assigned(asset_id: String, blip_id: String)
signal asset_arrived(asset_id: String, blip_id: String)
signal asset_returned(asset_id: String)

# --- Mission flow ---
signal mission_started(blip_id: String, coa_id: String, asset_id: String)
signal mission_complication(blip_id: String, complication: Dictionary)
signal mission_resolved(blip_id: String, result: Dictionary)

# --- Detection ---
signal detection_changed(level: String, value: float)
signal analyst_burned()

# --- Handler voice ---
signal handler_speak(text: String, priority: String)
signal handler_subtitle(text: String)  # For optional subtitle display

# --- Progression ---
signal budget_changed(new_budget: int)
signal asset_unlocked(asset_id: String)
signal campaign_phase_changed(phase: String)  # briefing, active, debrief, upgrade

# --- Game state ---
signal game_loaded()
signal mission_complete(grade: String)
