"""Tests for SIGNAL ops schemas.

Covers creation, serialization, validation, enums, nesting, and edge cases
for all intelligence analyst roguelike data models.
"""

from __future__ import annotations

import json

import pytest
from pydantic import ValidationError

from schemas.signal_ops import (
    AnalystDefinition,
    AnalystSkill,
    AnalystSkillType,
    Campaign,
    CampaignTheme,
    Classification,
    ConnectionType,
    ConspiracyEdge,
    ConspiracyGraph,
    ConspiracyNode,
    ConspiracyNodeType,
    Credential,
    DetectionLevel,
    EmployeeProfile,
    EvidenceBoard,
    EvidenceConnection,
    EvidenceItem,
    EvidenceType,
    FacilityLayout,
    FileEntry,
    HostDefinition,
    HostOS,
    InheritancePackage,
    InterceptBatch,
    NetworkTopology,
    OpBriefing,
    OpGrade,
    OpPhase,
    OpResult,
    Operation,
    ServiceDefinition,
    ServiceType,
    SubnetDefinition,
    TargetProfile,
    ToolkitItem,
    ToolkitItemType,
    Vulnerability,
    VulnerabilityChain,
    VulnerabilityStep,
)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def sample_evidence_item() -> EvidenceItem:
    return EvidenceItem(
        id="ev-001",
        evidence_type=EvidenceType.EMAIL,
        title="RE: Server Migration",
        content="Hey Rachel, the new creds for the staging server are in the shared drive.",
        source="NSA SIGINT intercept",
        classification=Classification.SECRET,
        timestamp="2026-03-15T14:32:00Z",
        is_clue=True,
        clue_target_ids=["host-staging", "cred-admin"],
    )


@pytest.fixture
def sample_employee() -> EmployeeProfile:
    return EmployeeProfile(
        id="emp-001",
        name="Rachel Chen",
        role="sysadmin",
        department="IT Infrastructure",
        personality_traits=["meticulous", "overworked", "friendly"],
        speech_pattern="casual",
        knowledge_set=[
            "staging server IP is 10.0.1.12",
            "admin password was changed last Tuesday",
            "backup server is in Building B basement",
        ],
        vulnerabilities=[
            Vulnerability(
                trait="overworked",
                exploit_vector="sympathize with workload, offer to help",
                difficulty=4,
            ),
        ],
        trust_threshold=3,
        secrets=["admin password is 'Tr0ub4dor&3'"],
    )


@pytest.fixture
def sample_host() -> HostDefinition:
    return HostDefinition(
        id="host-001",
        hostname="mailsrv",
        os=HostOS.LINUX,
        ip="10.0.1.5",
        subnet="10.0.1.0/24",
        services=[
            ServiceDefinition(
                service_type=ServiceType.SMTP,
                port=25,
                version="Postfix 3.5.6",
                vulnerable=True,
                cve_id="CVE-2023-51764",
                banner="220 mailsrv.meridian.local ESMTP Postfix",
            ),
            ServiceDefinition(
                service_type=ServiceType.SSH,
                port=22,
                version="OpenSSH 8.2",
            ),
        ],
        files=[
            FileEntry(
                path="/var/mail/r.chen",
                content="From: j.mitchell@meridian.local\nSubject: Creds\nNew staging password: Welcome2026!",
                is_target=False,
            ),
        ],
    )


@pytest.fixture
def sample_network(sample_host: HostDefinition) -> NetworkTopology:
    return NetworkTopology(
        subnets=[
            SubnetDefinition(
                id="subnet-dmz",
                cidr="10.0.1.0/24",
                name="DMZ",
                hosts=["host-001"],
                accessible_from=["subnet-corp"],
            ),
        ],
        hosts=[sample_host],
        entry_points=["host-001"],
        exfil_target_ids=["file-secret-001"],
    )


@pytest.fixture
def sample_operation(sample_evidence_item: EvidenceItem, sample_employee: EmployeeProfile, sample_network: NetworkTopology) -> Operation:
    return Operation(
        id="op-001",
        op_index=0,
        briefing=OpBriefing(
            codename="MERIDIAN SHADOW",
            summary="Infiltrate the Meridian Group's network to exfiltrate evidence of arms trafficking.",
            objectives=["Identify the internal contact", "Exfiltrate the shipping manifest"],
            warnings=["Target has active IDS on the DMZ"],
        ),
        signal_data=InterceptBatch(
            op_id="op-001",
            items=[sample_evidence_item],
            total_clues=1,
            total_noise=0,
        ),
        blacksite_target=TargetProfile(
            id="target-001",
            org_name="Meridian Group",
            sector="defense contractor",
            description="Mid-size defense contractor with government contracts.",
            employees=[sample_employee],
            network=sample_network,
        ),
        difficulty=3,
        required_exfil=["file-secret-001"],
    )


@pytest.fixture
def sample_analyst() -> AnalystDefinition:
    return AnalystDefinition(
        id="analyst-001",
        codename="WRAITH",
        name="Alex Morgan",
        skills=[
            AnalystSkill(skill_type=AnalystSkillType.SIGINT, level=2, xp=150),
            AnalystSkill(skill_type=AnalystSkillType.NETWORK_EXPLOITATION, level=1, xp=30),
        ],
        toolkit=[
            ToolkitItem(
                id="tool-001",
                name="Apache Path Traversal",
                item_type=ToolkitItemType.EXPLOIT,
                description="Exploits CVE-2021-41773 on Apache 2.4.49/2.4.50",
                uses=1,
                effect="Gains read access to filesystem via path traversal",
                targets_service=ServiceType.HTTP,
                targets_cve="CVE-2021-41773",
            ),
        ],
    )


# ---------------------------------------------------------------------------
# Evidence system
# ---------------------------------------------------------------------------


class TestEvidenceItem:
    def test_create_valid(self, sample_evidence_item: EvidenceItem) -> None:
        assert sample_evidence_item.id == "ev-001"
        assert sample_evidence_item.evidence_type == EvidenceType.EMAIL
        assert sample_evidence_item.is_clue is True
        assert len(sample_evidence_item.clue_target_ids) == 2

    def test_json_roundtrip(self, sample_evidence_item: EvidenceItem) -> None:
        raw = sample_evidence_item.model_dump_json()
        restored = EvidenceItem.model_validate_json(raw)
        assert restored.id == sample_evidence_item.id
        assert restored.content == sample_evidence_item.content

    def test_dict_serialization(self, sample_evidence_item: EvidenceItem) -> None:
        d = sample_evidence_item.model_dump()
        assert isinstance(d, dict)
        assert d["evidence_type"] == "email"
        assert d["classification"] == "secret"

    def test_default_values(self) -> None:
        item = EvidenceItem(
            id="ev-min",
            evidence_type=EvidenceType.DOCUMENT,
            title="Test",
            content="Test content",
        )
        assert item.discovered is False
        assert item.pinned is False
        assert item.redacted_level == 0
        assert item.is_clue is False

    def test_redacted_level_bounds(self) -> None:
        with pytest.raises(ValidationError):
            EvidenceItem(
                id="ev-bad",
                evidence_type=EvidenceType.DOCUMENT,
                title="Test",
                content="Test",
                redacted_level=4,
            )

    def test_all_evidence_types(self) -> None:
        for etype in EvidenceType:
            item = EvidenceItem(
                id=f"ev-{etype.value}",
                evidence_type=etype,
                title=f"Test {etype.value}",
                content="content",
            )
            assert item.evidence_type == etype


class TestEvidenceConnection:
    def test_create_valid(self) -> None:
        conn = EvidenceConnection(
            id="conn-001",
            from_evidence_id="ev-001",
            to_evidence_id="ev-002",
            connection_type=ConnectionType.FINANCES,
            player_note="Same account number appears in both",
            is_correct=True,
            strength=0.8,
        )
        assert conn.connection_type == ConnectionType.FINANCES
        assert conn.strength == 0.8

    def test_strength_bounds(self) -> None:
        with pytest.raises(ValidationError):
            EvidenceConnection(
                id="conn-bad",
                from_evidence_id="ev-001",
                to_evidence_id="ev-002",
                connection_type=ConnectionType.MENTIONS,
                strength=1.5,
            )

    def test_all_connection_types(self) -> None:
        for ctype in ConnectionType:
            conn = EvidenceConnection(
                id=f"conn-{ctype.value}",
                from_evidence_id="ev-001",
                to_evidence_id="ev-002",
                connection_type=ctype,
            )
            assert conn.connection_type == ctype


class TestEvidenceBoard:
    def test_create_with_items_and_connections(self, sample_evidence_item: EvidenceItem) -> None:
        board = EvidenceBoard(
            op_id="op-001",
            items=[sample_evidence_item],
            connections=[
                EvidenceConnection(
                    id="conn-001",
                    from_evidence_id="ev-001",
                    to_evidence_id="ev-002",
                    connection_type=ConnectionType.CONTACTS,
                ),
            ],
            prep_score=0.65,
        )
        assert len(board.items) == 1
        assert len(board.connections) == 1
        assert board.prep_score == 0.65

    def test_prep_score_bounds(self) -> None:
        with pytest.raises(ValidationError):
            EvidenceBoard(op_id="op-bad", prep_score=1.5)

    def test_empty_board(self) -> None:
        board = EvidenceBoard(op_id="op-empty")
        assert len(board.items) == 0
        assert len(board.connections) == 0
        assert board.prep_score == 0.0


# ---------------------------------------------------------------------------
# Employee / Social engineering
# ---------------------------------------------------------------------------


class TestEmployeeProfile:
    def test_create_valid(self, sample_employee: EmployeeProfile) -> None:
        assert sample_employee.name == "Rachel Chen"
        assert sample_employee.role == "sysadmin"
        assert len(sample_employee.knowledge_set) == 3
        assert len(sample_employee.vulnerabilities) == 1

    def test_json_roundtrip(self, sample_employee: EmployeeProfile) -> None:
        raw = sample_employee.model_dump_json()
        restored = EmployeeProfile.model_validate_json(raw)
        assert restored.name == sample_employee.name
        assert restored.vulnerabilities[0].trait == "overworked"

    def test_trust_bounds(self) -> None:
        with pytest.raises(ValidationError):
            EmployeeProfile(
                id="emp-bad",
                name="Bad",
                role="test",
                trust=11,
            )

    def test_suspicion_bounds(self) -> None:
        with pytest.raises(ValidationError):
            EmployeeProfile(
                id="emp-bad",
                name="Bad",
                role="test",
                suspicion=11,
            )

    def test_default_runtime_state(self) -> None:
        emp = EmployeeProfile(id="emp-min", name="Test", role="intern")
        assert emp.trust == 0
        assert emp.suspicion == 0
        assert emp.secrets_revealed == []


class TestVulnerability:
    def test_create_valid(self) -> None:
        vuln = Vulnerability(
            trait="gambling debt",
            exploit_vector="offer money",
            difficulty=7,
        )
        assert vuln.difficulty == 7

    def test_difficulty_bounds(self) -> None:
        with pytest.raises(ValidationError):
            Vulnerability(trait="test", exploit_vector="test", difficulty=0)
        with pytest.raises(ValidationError):
            Vulnerability(trait="test", exploit_vector="test", difficulty=11)


# ---------------------------------------------------------------------------
# Network topology
# ---------------------------------------------------------------------------


class TestHostDefinition:
    def test_create_valid(self, sample_host: HostDefinition) -> None:
        assert sample_host.hostname == "mailsrv"
        assert sample_host.os == HostOS.LINUX
        assert len(sample_host.services) == 2
        assert sample_host.services[0].vulnerable is True

    def test_json_roundtrip(self, sample_host: HostDefinition) -> None:
        raw = sample_host.model_dump_json()
        restored = HostDefinition.model_validate_json(raw)
        assert restored.hostname == sample_host.hostname
        assert restored.services[0].cve_id == "CVE-2023-51764"


class TestNetworkTopology:
    def test_create_valid(self, sample_network: NetworkTopology) -> None:
        assert len(sample_network.subnets) == 1
        assert len(sample_network.hosts) == 1
        assert len(sample_network.entry_points) == 1

    def test_empty_network(self) -> None:
        net = NetworkTopology()
        assert len(net.subnets) == 0
        assert len(net.hosts) == 0


class TestVulnerabilityChain:
    def test_create_valid(self) -> None:
        chain = VulnerabilityChain(
            id="chain-001",
            name="Primary exploit chain",
            steps=[
                VulnerabilityStep(
                    step_number=1,
                    action="Exploit CVE-2023-51764 on mailsrv",
                    requires=["tool-smtp-exploit"],
                    reveals=["cred-admin"],
                ),
                VulnerabilityStep(
                    step_number=2,
                    action="Login to fileserv with admin creds",
                    requires=["cred-admin"],
                    reveals=["file-secret-001"],
                ),
            ],
            alternative_paths=1,
        )
        assert len(chain.steps) == 2
        assert chain.steps[0].reveals == ["cred-admin"]


# ---------------------------------------------------------------------------
# Operation
# ---------------------------------------------------------------------------


class TestOperation:
    def test_create_valid(self, sample_operation: Operation) -> None:
        assert sample_operation.id == "op-001"
        assert sample_operation.briefing.codename == "MERIDIAN SHADOW"
        assert sample_operation.difficulty == 3
        assert len(sample_operation.signal_data.items) == 1

    def test_json_roundtrip(self, sample_operation: Operation) -> None:
        raw = sample_operation.model_dump_json()
        restored = Operation.model_validate_json(raw)
        assert restored.briefing.codename == sample_operation.briefing.codename
        assert restored.blacksite_target.org_name == "Meridian Group"

    def test_difficulty_bounds(self) -> None:
        with pytest.raises(ValidationError):
            Operation(
                id="op-bad",
                op_index=0,
                briefing=OpBriefing(codename="TEST", summary="test", objectives=[]),
                signal_data=InterceptBatch(op_id="op-bad"),
                blacksite_target=TargetProfile(
                    id="t", org_name="t", sector="t", description="t",
                ),
                difficulty=11,
            )

    def test_detection_threshold_bounds(self) -> None:
        with pytest.raises(ValidationError):
            Operation(
                id="op-bad",
                op_index=0,
                briefing=OpBriefing(codename="TEST", summary="test", objectives=[]),
                signal_data=InterceptBatch(op_id="op-bad"),
                blacksite_target=TargetProfile(
                    id="t", org_name="t", sector="t", description="t",
                ),
                max_detection_threshold=1.5,
            )


# ---------------------------------------------------------------------------
# Campaign
# ---------------------------------------------------------------------------


class TestConspiracyGraph:
    def test_create_valid(self) -> None:
        graph = ConspiracyGraph(
            theme=CampaignTheme.ARMS_TRAFFICKING,
            title="The Meridian Group",
            synopsis="A mid-size defense contractor is secretly trafficking arms to hostile nations.",
            nodes=[
                ConspiracyNode(
                    id="cn-001",
                    label="Viktor Petrov",
                    node_type=ConspiracyNodeType.PERSON,
                    description="Arms broker operating out of Cyprus",
                ),
                ConspiracyNode(
                    id="cn-002",
                    label="Meridian Group",
                    node_type=ConspiracyNodeType.ORGANIZATION,
                ),
            ],
            edges=[
                ConspiracyEdge(
                    from_id="cn-001",
                    to_id="cn-002",
                    relationship="supplies weapons to",
                ),
            ],
        )
        assert len(graph.nodes) == 2
        assert len(graph.edges) == 1
        assert graph.theme == CampaignTheme.ARMS_TRAFFICKING

    def test_all_themes(self) -> None:
        for theme in CampaignTheme:
            graph = ConspiracyGraph(
                theme=theme,
                title=f"Test {theme.value}",
                synopsis="Test",
            )
            assert graph.theme == theme


class TestCampaign:
    def test_create_valid(self, sample_operation: Operation, sample_analyst: AnalystDefinition) -> None:
        campaign = Campaign(
            id="campaign-001",
            name="Operation Meridian",
            conspiracy=ConspiracyGraph(
                theme=CampaignTheme.ARMS_TRAFFICKING,
                title="The Meridian Group",
                synopsis="Arms trafficking ring.",
            ),
            operations=[sample_operation],
            analyst=sample_analyst,
        )
        assert campaign.name == "Operation Meridian"
        assert len(campaign.operations) == 1
        assert campaign.analyst.codename == "WRAITH"

    def test_json_roundtrip(self, sample_operation: Operation, sample_analyst: AnalystDefinition) -> None:
        campaign = Campaign(
            id="campaign-001",
            name="Test Campaign",
            conspiracy=ConspiracyGraph(
                theme=CampaignTheme.CORPORATE_ESPIONAGE,
                title="Test",
                synopsis="Test",
            ),
            operations=[sample_operation],
            analyst=sample_analyst,
        )
        raw = campaign.model_dump_json()
        restored = Campaign.model_validate_json(raw)
        assert restored.name == campaign.name
        assert len(restored.operations) == 1
        assert restored.analyst.codename == "WRAITH"


# ---------------------------------------------------------------------------
# Analyst / RPG
# ---------------------------------------------------------------------------


class TestAnalystDefinition:
    def test_create_valid(self, sample_analyst: AnalystDefinition) -> None:
        assert sample_analyst.codename == "WRAITH"
        assert len(sample_analyst.skills) == 2
        assert len(sample_analyst.toolkit) == 1
        assert sample_analyst.alive is True

    def test_skill_level_bounds(self) -> None:
        with pytest.raises(ValidationError):
            AnalystSkill(skill_type=AnalystSkillType.SIGINT, level=0)
        with pytest.raises(ValidationError):
            AnalystSkill(skill_type=AnalystSkillType.SIGINT, level=6)

    def test_all_skill_types(self) -> None:
        for stype in AnalystSkillType:
            skill = AnalystSkill(skill_type=stype)
            assert skill.level == 1
            assert skill.xp == 0

    def test_toolkit_item_json(self) -> None:
        item = ToolkitItem(
            id="tool-test",
            name="Test Tool",
            item_type=ToolkitItemType.DECRYPT,
            description="Decrypts AES-256",
            uses=3,
            effect="Unlocks AES-256 encrypted files",
        )
        raw = item.model_dump_json()
        restored = ToolkitItem.model_validate_json(raw)
        assert restored.uses == 3
        assert restored.item_type == ToolkitItemType.DECRYPT

    def test_unlimited_uses(self) -> None:
        item = ToolkitItem(
            id="tool-inf",
            name="Scanner",
            item_type=ToolkitItemType.NETWORK,
            description="Passive network scanner",
            uses=-1,
            effect="Reduces detection on scan commands",
        )
        assert item.uses == -1


# ---------------------------------------------------------------------------
# Op results
# ---------------------------------------------------------------------------


class TestOpResult:
    def test_create_success(self) -> None:
        result = OpResult(
            op_id="op-001",
            grade=OpGrade.GHOST,
            exfiltrated=["file-secret-001"],
            detection_peak=DetectionLevel.YELLOW,
            detection_value=0.3,
            prep_score=0.85,
            xp_gained={"sigint": 50, "network_exploitation": 30},
            mission_success=True,
        )
        assert result.grade == OpGrade.GHOST
        assert result.mission_success is True
        assert result.detection_value == 0.3

    def test_create_burned(self) -> None:
        result = OpResult(
            op_id="op-001",
            grade=OpGrade.BURNED,
            detection_peak=DetectionLevel.BLACK,
            detection_value=1.0,
            mission_success=False,
            analyst_burned=True,
            summary="Analyst was identified during social engineering phase.",
        )
        assert result.analyst_burned is True
        assert result.mission_success is False

    def test_all_grades(self) -> None:
        for grade in OpGrade:
            result = OpResult(op_id="op-test", grade=grade)
            assert result.grade == grade

    def test_detection_value_bounds(self) -> None:
        with pytest.raises(ValidationError):
            OpResult(op_id="op-bad", grade=OpGrade.SHADOW, detection_value=1.5)


# ---------------------------------------------------------------------------
# Inheritance
# ---------------------------------------------------------------------------


class TestInheritancePackage:
    def test_create_valid(self) -> None:
        pkg = InheritancePackage(
            predecessor_codename="WRAITH",
            inherited_evidence=["ev-001", "ev-003"],
            inherited_connections=["conn-001"],
            inherited_toolkit=["tool-001"],
            redacted_item_ids=["ev-002"],
            handler_message="Your predecessor got close on the Meridian Group. Don't get burned the same way.",
            completed_op_ids=["op-001"],
        )
        assert pkg.predecessor_codename == "WRAITH"
        assert len(pkg.inherited_evidence) == 2
        assert len(pkg.redacted_item_ids) == 1

    def test_json_roundtrip(self) -> None:
        pkg = InheritancePackage(
            predecessor_codename="CIPHER",
            handler_message="Good luck.",
        )
        raw = pkg.model_dump_json()
        restored = InheritancePackage.model_validate_json(raw)
        assert restored.predecessor_codename == "CIPHER"


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------


class TestEnums:
    def test_detection_levels(self) -> None:
        assert DetectionLevel.GREEN.value == "green"
        assert DetectionLevel.BLACK.value == "black"
        assert len(DetectionLevel) == 4

    def test_op_phases(self) -> None:
        assert OpPhase.SIGNAL.value == "signal"
        assert OpPhase.BLACKSITE.value == "blacksite"
        assert len(OpPhase) == 4

    def test_classification_levels(self) -> None:
        assert Classification.TOP_SECRET.value == "top_secret"
        assert len(Classification) == 4

    def test_host_os(self) -> None:
        for os in HostOS:
            assert isinstance(os.value, str)

    def test_service_types(self) -> None:
        for stype in ServiceType:
            assert isinstance(stype.value, str)

    def test_conspiracy_node_types(self) -> None:
        for ntype in ConspiracyNodeType:
            assert isinstance(ntype.value, str)
        assert len(ConspiracyNodeType) == 5
