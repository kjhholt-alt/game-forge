using System;

namespace GameForge.Runtime
{
    /// <summary>
    /// Flat, Unity-friendly projection of a GameForge GameProject.
    ///
    /// Unity's built-in JsonUtility is rigid (no dictionaries, no polymorphism,
    /// field names must match the JSON keys exactly), so the heavy schema mapping
    /// happens in Python (orchestrator/unity_exporter.py) and only this minimal,
    /// already-denormalised shape is written to
    /// StreamingAssets/gameforge_scene.json. The C# side just renders it.
    /// </summary>
    [Serializable]
    public class SceneModel
    {
        public string title = "Generated Game";
        public string genre = "game";
        public string setting = "";
        public string target_mood = "";
        public string[] core_mechanics;
        public Space[] spaces;
        public NamedThing[] quests;
        public NamedThing[] items;
        public NamedThing[] npcs;
        public QaInfo qa;
    }

    /// <summary>A single play space (region, room, dungeon, quest, or start).</summary>
    [Serializable]
    public class Space
    {
        public string name = "Room";
        public string kind = "room";
        public string description = "";
    }

    /// <summary>A quest / item / NPC reduced to a name plus one detail line.</summary>
    [Serializable]
    public class NamedThing
    {
        public string name = "";
        public string detail = "";
    }

    [Serializable]
    public class QaInfo
    {
        public bool playable;
        public float score;
        public string summary = "";
        public QaIssue[] issues;
    }

    [Serializable]
    public class QaIssue
    {
        public string severity = "";
        public string description = "";
    }
}
