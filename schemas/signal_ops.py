"""SIGNAL — Intelligence analyst roguelike schemas.

Defines the complete data model for the SIGNAL/BLACKSITE game:
evidence items, employee profiles, network topologies, operations,
campaigns, and analyst progression.
"""

from __future__ import annotations

from enum import Enum

from pydantic import BaseModel, Field


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------


class EvidenceType(str, Enum):
    """Types of intelligence intercepts."""
    PHONE_TRANSCRIPT = "phone_transcript"
    EMAIL = "email"
    FINANCIAL_RECORD = "financial_record"
    SURVEILLANCE_LOG = "surveillance_log"
    CREDENTIAL = "credential"
    DOCUMENT = "document"


class Classification(str, Enum):
    """Security classification levels."""
    UNCLASSIFIED = "unclassified"
    CONFIDENTIAL = "confidential"
    SECRET = "secret"
    TOP_SECRET = "top_secret"


class ConnectionType(str, Enum):
    """Types of connections between evidence items on the board."""
    MENTIONS = "mentions"
    FINANCES = "finances"
    CONTACTS = "contacts"
    LOCATION = "location"
    TIMELINE = "timeline"
    IDENTITY = "identity"


class AnalystSkillType(str, Enum):
    """The five analyst skill trees."""
    SIGINT = "sigint"
    HUMINT = "humint"
    CRYPTOGRAPHY = "cryptography"
    SOCIAL_ENGINEERING = "social_engineering"
    NETWORK_EXPLOITATION = "network_exploitation"


class OpPhase(str, Enum):
    """Current phase of an operation."""
    BRIEFING = "briefing"
    SIGNAL = "signal"
    BLACKSITE = "blacksite"
    DEBRIEF = "debrief"


class DetectionLevel(str, Enum):
    """BLACKSITE detection meter thresholds."""
    GREEN = "green"          # Undetected
    YELLOW = "yellow"        # Anomaly flagged
    RED = "red"              # Active investigation
    BLACK = "black"          # Burned — mission failure


class HostOS(str, Enum):
    """Operating systems for network hosts."""
    LINUX = "linux"
    WINDOWS = "windows"
    EMBEDDED = "embedded"
    CUSTOM = "custom"


class ServiceType(str, Enum):
    """Common services running on hosts."""
    SSH = "ssh"
    HTTP = "http"
    HTTPS = "https"
    FTP = "ftp"
    SMTP = "smtp"
    RDP = "rdp"
    DATABASE = "database"
    SMB = "smb"
    VPN = "vpn"
    CUSTOM = "custom"


class ToolkitItemType(str, Enum):
    """Types of items in the analyst's toolkit."""
    EXPLOIT = "exploit"
    DECRYPT = "decrypt"
    SPOOF = "spoof"
    NETWORK = "network"
    INTEL = "intel"


class ConspiracyNodeType(str, Enum):
    """Types of nodes in a conspiracy graph."""
    PERSON = "person"
    ORGANIZATION = "organization"
    EVENT = "event"
    ASSET = "asset"
    LOCATION = "location"


class OpGrade(str, Enum):
    """Performance grades for completed operations."""
    SHADOW = "shadow"        # Perfect — zero detection
    GHOST = "ghost"          # Minimal detection
    OPERATIVE = "operative"  # Some detection, mission complete
    COMPROMISED = "compromised"  # High detection, mission complete
    BURNED = "burned"        # Mission failure


class CampaignTheme(str, Enum):
    """Themes for procedurally generated campaigns."""
    ARMS_TRAFFICKING = "arms_trafficking"
    CORPORATE_ESPIONAGE = "corporate_espionage"
    STATE_SPONSORED_HACKING = "state_sponsored_hacking"
    TERRORISM_FINANCING = "terrorism_financing"
    MONEY_LAUNDERING = "money_laundering"
    INSIDER_THREAT = "insider_threat"
    CYBER_WARFARE = "cyber_warfare"


# ---------------------------------------------------------------------------
# Evidence system
# ---------------------------------------------------------------------------


class EvidenceItem(BaseModel):
    """A single piece of intelligence — an intercepted document, call, etc.

    The ``is_clue`` and ``clue_target_ids`` fields are hidden from the player
    and used by the prep score calculator to grade evidence board quality.
    """
    id: str
    evidence_type: EvidenceType
    title: str
    content: str  # The full text the player reads
    source: str = ""  # e.g., "NSA SIGINT intercept", "FINCEN report"
    classification: Classification = Classification.CONFIDENTIAL
    timestamp: str = ""  # In-world timestamp (ISO format)
    # Hidden from player — used for scoring
    is_clue: bool = False
    clue_target_ids: list[str] = Field(
        default_factory=list,
        description="IDs of evidence/targets this clue points to (hidden from player)",
    )
    # Visual tags — the key facts displayed prominently on the card
    tags: list[str] = Field(
        default_factory=list,
        description="Key terms shown as visual pins: names, amounts, locations, dates. These are the puzzle pieces.",
    )
    tag_color: str = ""  # Optional override color for tags
    # Player state
    discovered: bool = False
    pinned: bool = False
    redacted_level: int = Field(
        default=0,
        ge=0,
        le=3,
        description="How redacted this intercept is (0=clean, 3=heavily redacted). Affected by SIGINT skill.",
    )


class EvidenceConnection(BaseModel):
    """A player-drawn connection between two evidence items on the board."""
    id: str
    from_evidence_id: str
    to_evidence_id: str
    connection_type: ConnectionType
    player_note: str = ""
    # Hidden from player — used for scoring
    is_correct: bool = False
    strength: float = Field(
        default=0.0,
        ge=0.0,
        le=1.0,
        description="How much this connection contributes to prep score (hidden)",
    )


class EvidenceBoard(BaseModel):
    """The analyst's evidence board for a single operation."""
    op_id: str
    items: list[EvidenceItem] = Field(default_factory=list)
    connections: list[EvidenceConnection] = Field(default_factory=list)
    prep_score: float = Field(
        default=0.0,
        ge=0.0,
        le=1.0,
        description="Computed from correct connections / total possible (0.0-1.0)",
    )


# ---------------------------------------------------------------------------
# Target system — employees
# ---------------------------------------------------------------------------


class Vulnerability(BaseModel):
    """An exploitable trait of an employee."""
    trait: str  # e.g., "gambling debt", "disgruntled", "vain"
    exploit_vector: str  # e.g., "offer money", "sympathize with frustrations"
    difficulty: int = Field(default=5, ge=1, le=10)


class EmployeeProfile(BaseModel):
    """A target employee for social engineering during BLACKSITE.

    The knowledge_set defines what this NPC knows and can reveal.
    The NPC literally cannot leak information not in this set.
    """
    id: str
    name: str
    role: str  # e.g., "sysadmin", "receptionist", "CFO"
    department: str = ""
    personality_traits: list[str] = Field(default_factory=list)
    speech_pattern: str = "professional"  # e.g., "nervous", "terse", "friendly"
    knowledge_set: list[str] = Field(
        default_factory=list,
        description="Facts this NPC knows — the ONLY things they can reveal",
    )
    vulnerabilities: list[Vulnerability] = Field(default_factory=list)
    trust_threshold: int = Field(
        default=5,
        ge=1,
        le=10,
        description="How many successful approaches before they reveal secrets",
    )
    secrets: list[str] = Field(
        default_factory=list,
        description="High-value intel revealed once trust threshold is met",
    )
    schedule: str = ""  # e.g., "arrives 8am, lunch at noon, leaves 5pm"
    photo_description: str = ""
    # Runtime state (not generated, updated during play)
    trust: int = Field(default=0, ge=0, le=10)
    suspicion: int = Field(default=0, ge=0, le=10)
    secrets_revealed: list[str] = Field(default_factory=list)


# ---------------------------------------------------------------------------
# Target system — network
# ---------------------------------------------------------------------------


class ServiceDefinition(BaseModel):
    """A service running on a network host."""
    service_type: ServiceType
    port: int
    version: str = ""  # e.g., "Apache 2.4.41", "OpenSSH 8.2"
    vulnerable: bool = False
    cve_id: str = ""  # e.g., "CVE-2021-41773" — what exploit works
    banner: str = ""  # What `probe` shows the player


class FileEntry(BaseModel):
    """A file on a host's filesystem."""
    path: str  # e.g., "/home/admin/credentials.txt"
    content: str = ""  # What `cat` shows
    encrypted: bool = False
    cipher: str = ""  # e.g., "aes-256", "rsa" — what decrypt method works
    is_target: bool = False  # Is this the exfiltration target?
    size_kb: int = 1


class Credential(BaseModel):
    """Login credentials for a network host."""
    username: str
    password: str
    host_id: str  # Which host these creds work on
    source: str = ""  # How the player can discover these (evidence item ID or NPC ID)


class HostDefinition(BaseModel):
    """A single host on the target network."""
    id: str
    hostname: str  # e.g., "mailsrv", "fileserv-01"
    os: HostOS = HostOS.LINUX
    ip: str  # e.g., "10.0.1.5"
    subnet: str  # e.g., "10.0.1.0/24"
    services: list[ServiceDefinition] = Field(default_factory=list)
    files: list[FileEntry] = Field(default_factory=list)
    credentials: list[Credential] = Field(default_factory=list)
    requires_credentials: bool = True
    description: str = ""  # Flavor text shown on scan


class SubnetDefinition(BaseModel):
    """A network subnet containing hosts."""
    id: str
    cidr: str  # e.g., "10.0.1.0/24"
    name: str  # e.g., "DMZ", "Corporate LAN", "Server Room"
    hosts: list[str] = Field(
        default_factory=list,
        description="Host IDs in this subnet",
    )
    gateway_host_id: str = ""
    accessible_from: list[str] = Field(
        default_factory=list,
        description="Other subnet IDs you can reach from here",
    )


class NetworkTopology(BaseModel):
    """Complete network topology for a BLACKSITE target."""
    subnets: list[SubnetDefinition] = Field(default_factory=list)
    hosts: list[HostDefinition] = Field(default_factory=list)
    entry_points: list[str] = Field(
        default_factory=list,
        description="Host IDs the player can access initially",
    )
    exfil_target_ids: list[str] = Field(
        default_factory=list,
        description="File IDs that must be downloaded to complete the op",
    )


class VulnerabilityStep(BaseModel):
    """A single step in a vulnerability chain from entry to exfil."""
    step_number: int
    action: str  # e.g., "exploit CVE-2021-41773 on mailsrv"
    requires: list[str] = Field(
        default_factory=list,
        description="What the player needs (credential ID, exploit name, etc.)",
    )
    reveals: list[str] = Field(
        default_factory=list,
        description="What completing this step gives the player",
    )


class VulnerabilityChain(BaseModel):
    """The intended path from network entry to data exfiltration.

    There may be multiple valid chains — this is the 'golden path'
    the QA validator checks for solvability.
    """
    id: str
    name: str  # e.g., "Primary exploit chain"
    steps: list[VulnerabilityStep] = Field(default_factory=list)
    alternative_paths: int = Field(
        default=0,
        description="Number of alternative valid paths (for QA)",
    )


# ---------------------------------------------------------------------------
# Target system — facility
# ---------------------------------------------------------------------------


class FacilityLayout(BaseModel):
    """Physical layout of the target — used for flavor text and context."""
    name: str  # e.g., "Meridian Group HQ"
    location: str  # e.g., "downtown Chicago"
    description: str
    floors: int = 1
    security_features: list[str] = Field(
        default_factory=list,
        description='E.g., ["keycard access", "CCTV", "armed guards"]',
    )
    notable_areas: list[dict[str, str]] = Field(
        default_factory=list,
        description='E.g., [{"name": "server room", "floor": "B1", "access": "biometric"}]',
    )


# ---------------------------------------------------------------------------
# Target aggregate
# ---------------------------------------------------------------------------


class TargetProfile(BaseModel):
    """Complete profile of a BLACKSITE target organization."""
    id: str
    org_name: str
    sector: str  # e.g., "defense contractor", "financial services"
    description: str
    employees: list[EmployeeProfile] = Field(default_factory=list)
    network: NetworkTopology = Field(default_factory=NetworkTopology)
    facility: FacilityLayout | None = None
    vulnerability_chains: list[VulnerabilityChain] = Field(default_factory=list)
    secrets: list[str] = Field(
        default_factory=list,
        description="High-level secrets the organization is hiding",
    )


# ---------------------------------------------------------------------------
# Operation system
# ---------------------------------------------------------------------------


class InterceptBatch(BaseModel):
    """A batch of evidence items for one operation — clues mixed with noise."""
    op_id: str
    items: list[EvidenceItem] = Field(default_factory=list)
    total_clues: int = Field(
        default=0,
        description="How many items are actual clues (for QA validation)",
    )
    total_noise: int = Field(
        default=0,
        description="How many items are noise/filler",
    )


class OpBriefing(BaseModel):
    """Handler's briefing before an operation begins."""
    codename: str  # e.g., "MERIDIAN SHADOW"
    summary: str  # 2-3 sentence overview
    objectives: list[str]  # What the player must accomplish
    warnings: list[str] = Field(default_factory=list)  # Known risks
    handler_notes: str = ""  # Personal touch from the handler


class Operation(BaseModel):
    """A single intelligence operation — one SIGNAL + BLACKSITE cycle."""
    id: str
    op_index: int  # Position in the campaign (0-based)
    briefing: OpBriefing
    signal_data: InterceptBatch
    blacksite_target: TargetProfile
    difficulty: int = Field(default=3, ge=1, le=10)
    required_exfil: list[str] = Field(
        default_factory=list,
        description="File IDs that must be exfiltrated for mission success",
    )
    max_detection_threshold: float = Field(
        default=1.0,
        ge=0.0,
        le=1.0,
        description="Detection level that triggers 'burned' (lower = harder)",
    )
    time_limit_minutes: int = Field(
        default=0,
        description="0 = no time limit, >0 = real-time countdown in BLACKSITE",
    )
    unlocks_ops: list[str] = Field(
        default_factory=list,
        description="Operation IDs unlocked by completing this op",
    )


# ---------------------------------------------------------------------------
# Campaign system
# ---------------------------------------------------------------------------


class ConspiracyNode(BaseModel):
    """A node in the overarching conspiracy graph."""
    id: str
    label: str
    node_type: ConspiracyNodeType
    description: str = ""
    discovered: bool = False  # Revealed through gameplay
    connected_op_ids: list[str] = Field(
        default_factory=list,
        description="Which operations reveal information about this node",
    )


class ConspiracyEdge(BaseModel):
    """A connection between two conspiracy nodes."""
    from_id: str
    to_id: str
    relationship: str  # e.g., "funds", "controls", "employed by"
    discovered: bool = False


class ConspiracyGraph(BaseModel):
    """The overarching conspiracy the player is unraveling."""
    theme: CampaignTheme
    title: str  # e.g., "The Meridian Group"
    synopsis: str  # 3-5 sentence overview (revealed gradually)
    nodes: list[ConspiracyNode] = Field(default_factory=list)
    edges: list[ConspiracyEdge] = Field(default_factory=list)


class Campaign(BaseModel):
    """A full campaign — 4-6 operations connected by a conspiracy.

    This is the top-level output of the CampaignDirector pipeline.
    """
    id: str
    name: str
    conspiracy: ConspiracyGraph
    operations: list[Operation] = Field(default_factory=list)
    analyst: AnalystDefinition | None = None
    current_op_index: int = 0
    created_at: str = ""  # ISO timestamp
    updated_at: str = ""


# ---------------------------------------------------------------------------
# Analyst / RPG system
# ---------------------------------------------------------------------------


class AnalystSkill(BaseModel):
    """A single skill with level and XP tracking."""
    skill_type: AnalystSkillType
    level: int = Field(default=1, ge=1, le=5)
    xp: int = Field(default=0, ge=0)
    xp_to_next: int = 100  # XP needed to level up


class ToolkitItem(BaseModel):
    """An item in the analyst's toolkit — exploits, tools, etc."""
    id: str
    name: str
    item_type: ToolkitItemType
    description: str
    uses: int = Field(
        default=1,
        ge=-1,
        description="-1 = unlimited, >0 = consumable",
    )
    effect: str  # What it does in gameplay terms
    skill_requirement: AnalystSkillType | None = None
    skill_level_required: int = 0
    # For exploits: which service/CVE it targets
    targets_service: ServiceType | None = None
    targets_cve: str = ""


class AnalystDefinition(BaseModel):
    """The player's analyst character — skills, toolkit, identity."""
    id: str
    codename: str  # e.g., "WRAITH", "CIPHER"
    name: str = ""  # Real name (for flavor)
    skills: list[AnalystSkill] = Field(default_factory=list)
    toolkit: list[ToolkitItem] = Field(default_factory=list)
    alive: bool = True
    ops_completed: int = 0
    total_xp: int = 0
    # Inheritance tracking
    predecessor_codenames: list[str] = Field(
        default_factory=list,
        description="Codenames of previous analysts in this campaign (permadeath history)",
    )


# ---------------------------------------------------------------------------
# Operation results
# ---------------------------------------------------------------------------


class OpResult(BaseModel):
    """Results of a completed operation."""
    op_id: str
    grade: OpGrade
    exfiltrated: list[str] = Field(
        default_factory=list,
        description="File IDs successfully exfiltrated",
    )
    detection_peak: DetectionLevel = DetectionLevel.GREEN
    detection_value: float = Field(
        default=0.0,
        ge=0.0,
        le=1.0,
    )
    prep_score: float = Field(
        default=0.0,
        ge=0.0,
        le=1.0,
        description="Evidence board quality when entering BLACKSITE",
    )
    xp_gained: dict[str, int] = Field(
        default_factory=dict,
        description="Skill type -> XP earned",
    )
    toolkit_acquired: list[str] = Field(
        default_factory=list,
        description="ToolkitItem IDs found during the op",
    )
    conspiracy_nodes_revealed: list[str] = Field(
        default_factory=list,
        description="ConspiracyNode IDs discovered",
    )
    secrets_uncovered: list[str] = Field(default_factory=list)
    mission_success: bool = True
    analyst_burned: bool = False  # Triggers permadeath
    time_elapsed_seconds: int = 0
    summary: str = ""  # Brief narrative summary of the op


# ---------------------------------------------------------------------------
# Inheritance (permadeath)
# ---------------------------------------------------------------------------


class InheritancePackage(BaseModel):
    """What a new analyst inherits from a burned predecessor."""
    predecessor_codename: str
    inherited_evidence: list[str] = Field(
        default_factory=list,
        description="EvidenceItem IDs that carry over (some may be redacted)",
    )
    inherited_connections: list[str] = Field(
        default_factory=list,
        description="EvidenceConnection IDs that carry over",
    )
    inherited_toolkit: list[str] = Field(
        default_factory=list,
        description="1-2 random ToolkitItem IDs from predecessor",
    )
    redacted_item_ids: list[str] = Field(
        default_factory=list,
        description="Evidence items that were sanitized (content replaced with [REDACTED])",
    )
    handler_message: str = ""  # e.g., "Your predecessor got close. Don't make the same mistakes."
    completed_op_ids: list[str] = Field(
        default_factory=list,
        description="Operations that stay completed",
    )
