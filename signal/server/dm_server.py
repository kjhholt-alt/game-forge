"""SIGNAL War Room — Claude DM runtime server.

FastAPI server that Godot calls via HTTP. Routes game state to Claude
for contextual handler commentary, intel assessments, debriefs, advisory,
interrogation, and dynamic mission generation.

Run: uvicorn server.dm_server:app --port 8090
"""

from __future__ import annotations

import json
import logging
import os
from typing import Any

import claudex_anthropic_shim as anthropic  # Max-sub via claudex; no API key
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="SIGNAL DM Server")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

_client = anthropic.AsyncAnthropic()  # Max-sub via claudex shim; api_key is a no-op

# ---------------------------------------------------------------------------
# System prompts for each Claude role
# ---------------------------------------------------------------------------

HANDLER_SYSTEM = """\
You are HANDLER — a tactical intelligence officer speaking to an analyst \
running a war room operation. You see the full game state and provide \
contextual commentary.

Rules:
- Speak in 1-2 SHORT sentences. Never more than 25 words.
- Sound like a calm, experienced intelligence officer. Think Zero Dark Thirty.
- Reference specific details from the game state (asset names, target labels, detection level).
- If detection is high, sound more urgent.
- If the player is doing well, be approving but brief.
- If an asset is busy and they're trying to assign another, note the risk.
- Never break character. Never mention "game" or "player."
- No text formatting, no markdown, no lists. Just spoken words.
"""

INTEL_ANALYST_SYSTEM = """\
You are an intelligence analyst providing target assessments. You receive \
raw intelligence data about a detected contact and produce a brief, \
professional classification.

Rules:
- Speak in 2-3 SHORT sentences max.
- Include a confidence percentage (50-95%).
- Recommend an approach (surveillance, cyber, kinetic, capture).
- Reference specific details (movement patterns, signal type, thermal signature).
- Sound clinical and professional, like a real intelligence briefing.
- No formatting. Just spoken words.
"""

DEBRIEF_SYSTEM = """\
You are writing a 2-3 sentence after-action summary. You see exactly \
what the analyst did during the operation — which targets they hit, \
what approaches they used, what complications arose, final detection level.

Rules:
- 2-3 sentences ONLY. This will be spoken aloud.
- Reference specific actions the player took (not generic praise).
- Note their dominant strategy (aggressive, cautious, balanced).
- If they had failures, acknowledge them without being harsh.
- Sound like a professional military debrief, not a game summary.
"""

ADVISOR_SYSTEM = """\
You are a strategic advisor. The analyst has asked for your recommendation \
on what to do next. You see the full game state — active targets, available \
assets, detection level, budget.

Rules:
- Give ONE specific recommendation in 1-2 sentences.
- Name the specific target and asset you'd recommend.
- Briefly explain why (risk, reward, timing).
- Sometimes be slightly wrong — you're experienced but not omniscient.
- Sound confident but not commanding. It's advice, not orders.
"""

INTERROGATION_SYSTEM = """\
You are a captured operative being interrogated. You have specific knowledge \
(provided in the game state) that you're trying to protect. You may lie, \
deflect, bargain, or eventually reveal information based on pressure.

Rules:
- Respond to the player's chosen approach (friendly, aggressive, analytical).
- Start evasive. Reveal more as trust/pressure builds.
- Your knowledge_set defines what you actually know. Never reveal what's not in it.
- If trust is high (>6), start cooperating. If pressure is high but trust low, clam up.
- Keep responses to 1-2 sentences. Spoken aloud.
- Show personality — scared, defiant, calculating, or resigned.
"""

MISSION_GEN_SYSTEM = """\
You are a campaign architect generating the next intelligence operation. \
You see what happened in previous missions and generate a new one that \
continues the story.

Rules:
- Generate valid JSON matching the mission schema.
- 3-5 targets per mission, escalating difficulty.
- Targets that escaped previous missions can reappear.
- If the player was aggressive, add targets with anti-air or countermeasures.
- If the player was stealthy, add targets that require kinetic force.
- Generate SHORT handler lines (under 20 words each).
- Include 1-2 complications with spawn_blips.
- Reference previous mission events in the handler_open line.
"""


# ---------------------------------------------------------------------------
# Request/Response models
# ---------------------------------------------------------------------------

class HandlerRequest(BaseModel):
    action: str  # "assign", "classify", "complication", "idle", etc.
    game_state: dict[str, Any]

class IntelRequest(BaseModel):
    blip_data: dict[str, Any]
    game_state: dict[str, Any]

class DebriefRequest(BaseModel):
    mission_summary: dict[str, Any]

class AdvisorRequest(BaseModel):
    game_state: dict[str, Any]

class InterrogationRequest(BaseModel):
    npc_data: dict[str, Any]
    approach: str  # "friendly", "aggressive", "analytical"
    trust: int
    turn: int

class MissionGenRequest(BaseModel):
    previous_missions: list[dict[str, Any]]
    player_style: dict[str, int]
    budget: int
    owned_assets: list[str]


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@app.post("/handler")
async def handler_commentary(req: HandlerRequest) -> dict:
    """Get contextual handler commentary for a player action."""
    user_msg = f"Action: {req.action}\nGame state:\n{json.dumps(req.game_state, indent=2)}"
    text = await _call_claude(HANDLER_SYSTEM, user_msg, model="claude-haiku-4-5", max_tokens=80)
    return {"text": text}


@app.post("/intel")
async def intel_assessment(req: IntelRequest) -> dict:
    """Get an intel assessment for a detected blip."""
    user_msg = f"Detected contact:\n{json.dumps(req.blip_data, indent=2)}\n\nOverall situation:\n{json.dumps(req.game_state, indent=2)}"
    text = await _call_claude(INTEL_ANALYST_SYSTEM, user_msg, model="claude-haiku-4-5", max_tokens=100)
    return {"text": text}


@app.post("/debrief")
async def after_action(req: DebriefRequest) -> dict:
    """Generate personalized after-action narrative."""
    user_msg = f"Mission results:\n{json.dumps(req.mission_summary, indent=2)}"
    text = await _call_claude(DEBRIEF_SYSTEM, user_msg, model="claude-sonnet-4-6", max_tokens=120)
    return {"text": text}


@app.post("/advise")
async def strategic_advisory(req: AdvisorRequest) -> dict:
    """Get strategic advice from the handler."""
    user_msg = f"Current situation:\n{json.dumps(req.game_state, indent=2)}\n\nThe analyst is asking for your recommendation."
    text = await _call_claude(ADVISOR_SYSTEM, user_msg, model="claude-haiku-4-5", max_tokens=80)
    return {"text": text}


@app.post("/interrogate")
async def interrogation(req: InterrogationRequest) -> dict:
    """Interrogate a captured NPC."""
    user_msg = (
        f"Your knowledge: {json.dumps(req.npc_data.get('knowledge', []))}\n"
        f"Approach: {req.approach}\n"
        f"Current trust level: {req.trust}/10\n"
        f"Turn: {req.turn}\n"
        f"Your personality: {req.npc_data.get('personality', 'evasive')}"
    )
    text = await _call_claude(INTERROGATION_SYSTEM, user_msg, model="claude-haiku-4-5", max_tokens=80)

    # Determine if they reveal info based on trust
    revealed = ""
    if req.trust >= 6:
        knowledge = req.npc_data.get("knowledge", [])
        reveal_index = min(req.turn, len(knowledge) - 1)
        if reveal_index >= 0 and reveal_index < len(knowledge):
            revealed = knowledge[reveal_index]

    return {"text": text, "revealed": revealed}


@app.post("/generate_mission")
async def generate_mission(req: MissionGenRequest) -> dict:
    """Generate the next mission dynamically."""
    user_msg = (
        f"Previous missions:\n{json.dumps(req.previous_missions, indent=2)}\n\n"
        f"Player style: {json.dumps(req.player_style)}\n"
        f"Budget: ${req.budget}\n"
        f"Owned assets: {req.owned_assets}\n\n"
        f"Generate the next mission as JSON with these fields:\n"
        f"codename, budget (0 = carries over), base_x, base_y, handler_open, "
        f"targets (array with id, x, y, type, label, threat_radius, handler_detect, "
        f"handler_classify, handler_coa, handler_resolve, coas), assets (empty array = use existing)"
    )
    text = await _call_claude(MISSION_GEN_SYSTEM, user_msg, model="claude-sonnet-4-6", max_tokens=2000)

    # Parse JSON from response
    try:
        # Strip markdown fences if present
        clean = text.strip()
        if clean.startswith("```"):
            clean = clean[clean.index("\n") + 1:]
        if clean.endswith("```"):
            clean = clean[:-3]
        mission = json.loads(clean.strip())
        return {"mission": mission}
    except (json.JSONDecodeError, ValueError) as e:
        logger.error("Failed to parse mission JSON: %s", e)
        return {"mission": None, "error": str(e)}


@app.get("/health")
async def health():
    return {"status": "ok", "service": "signal-dm"}


# ---------------------------------------------------------------------------
# Claude API helper
# ---------------------------------------------------------------------------

async def _call_claude(system: str, user_msg: str, model: str = "claude-haiku-4-5", max_tokens: int = 100) -> str:
    """Call Claude API and return text response."""
    try:
        response = _client.messages.create(
            model=model,
            max_tokens=max_tokens,
            system=system,
            messages=[{"role": "user", "content": user_msg}],
        )
        text = ""
        for block in response.content:
            if hasattr(block, "text"):
                text += block.text
        return text.strip()
    except Exception as e:
        logger.error("Claude API error: %s", e)
        return "Handler offline. Proceed with caution."
