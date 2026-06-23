using System.Collections.Generic;
using System.IO;
using System.Text;
using UnityEngine;
using GameForge.Generated;

namespace GameForge.Runtime
{
    /// <summary>
    /// The single source of truth that builds a playable GameForge slice scene in code.
    ///
    /// It is driven by BOTH:
    ///   * Play mode      -> Start() calls Build()
    ///   * Headless render -> GameForge.Editor.HeadlessRender calls Build() in edit mode
    /// so the PNG you inspect is the exact scene that plays (the same discipline
    /// war-table's TableBuilder + HeadlessRender use).
    ///
    /// It maps a flat SceneModel (emitted by orchestrator/unity_exporter.py from an
    /// engine-neutral GameProject) into a 3D scene built entirely in code -- no
    /// hand-authored .unity/.prefab files:
    ///   * a ground slab,
    ///   * one colour-coded, labelled room cube per play space,
    ///   * a player capsule that stands in front of the current room,
    ///   * a title + subtitle, an info panel (quests / items / NPCs / QA), and a status line.
    /// The one mechanic for the slice: NextRoom() walks the player to the next room.
    /// </summary>
    public class GameForgeRuntime : MonoBehaviour
    {
        public SceneModel Model;
        public Camera Cam { get; private set; }

        const float Spacing = 2.3f;
        const float CubeY = 0.6f;

        readonly List<Vector3> _roomPositions = new List<Vector3>();
        GameObject _player;
        TextMesh _statusText;
        TextMesh _currentRoomLabel;
        int _current;
        bool _built;
        Font _font;

        void Start()
        {
            if (!_built) Build();
        }

        /// <summary>Construct the whole scene in code. Idempotent.</summary>
        public void Build()
        {
            if (_built) return;
            _built = true;

            _font = LoadFont();
            if (Model == null) Model = LoadModel();

            AddLights();
            BuildGround();
            BuildRooms();
            BuildPlayer();
            BuildText();
            Cam = MakeFramedCamera();
            RefreshStatus();
        }

        // -------------------------------------------------------------- data

        static SceneModel LoadModel()
        {
            string path = Path.Combine(Application.streamingAssetsPath, "gameforge_scene.json");
            try
            {
                if (File.Exists(path))
                {
                    var m = JsonUtility.FromJson<SceneModel>(File.ReadAllText(path));
                    if (m != null) return m;
                }
            }
            catch (System.Exception e)
            {
                Debug.LogWarning("GameForge: scene model load failed: " + e.Message);
            }
            return FallbackModel();
        }

        // Compiled fallback from the per-game codegen seam so the slice still stands
        // up if the JSON manifest is missing.
        static SceneModel FallbackModel()
        {
            var spaces = new List<Space>();
            foreach (var n in GeneratedGameInfo.SpaceNames)
                spaces.Add(new Space { name = n, kind = "room" });
            if (spaces.Count == 0) spaces.Add(new Space { name = "Start", kind = "start" });
            return new SceneModel
            {
                title = GeneratedGameInfo.Title,
                genre = GeneratedGameInfo.Genre,
                spaces = spaces.ToArray(),
            };
        }

        Space[] Spaces()
        {
            if (Model != null && Model.spaces != null && Model.spaces.Length > 0) return Model.spaces;
            return new[] { new Space { name = "Start", kind = "start" } };
        }

        // ------------------------------------------------------------- build

        void AddLights()
        {
            var keyGo = new GameObject("KeyLight");
            var key = keyGo.AddComponent<Light>();
            key.type = LightType.Directional;
            key.intensity = 1.25f;
            key.color = new Color(1f, 0.95f, 0.85f);
            key.shadows = LightShadows.Soft;
            keyGo.transform.rotation = Quaternion.Euler(48f, -28f, 0f);

            var fillGo = new GameObject("FillLight");
            var fill = fillGo.AddComponent<Light>();
            fill.type = LightType.Directional;
            fill.intensity = 0.45f;
            fill.color = new Color(0.7f, 0.8f, 1f);
            fillGo.transform.rotation = Quaternion.Euler(20f, 150f, 0f);

            RenderSettings.ambientMode = UnityEngine.Rendering.AmbientMode.Trilight;
            RenderSettings.ambientSkyColor = new Color(0.42f, 0.45f, 0.52f);
            RenderSettings.ambientEquatorColor = new Color(0.30f, 0.31f, 0.34f);
            RenderSettings.ambientGroundColor = new Color(0.13f, 0.13f, 0.15f);
        }

        void BuildGround()
        {
            var ground = GameObject.CreatePrimitive(PrimitiveType.Cube);
            ground.name = "Ground";
            float width = Mathf.Max(8f, Spaces().Length * Spacing + 6f);
            ground.transform.localScale = new Vector3(width, 0.2f, 7f);
            ground.transform.position = new Vector3(0f, -0.1f, 0f);
            ground.GetComponent<Renderer>().material = SolidMat(new Color(0.16f, 0.17f, 0.20f));
        }

        void BuildRooms()
        {
            var spaces = Spaces();
            int n = spaces.Length;
            _roomPositions.Clear();
            for (int i = 0; i < n; i++)
            {
                float x = (i - (n - 1) * 0.5f) * Spacing;
                var pos = new Vector3(x, CubeY, 0f);
                _roomPositions.Add(pos);

                var cube = GameObject.CreatePrimitive(PrimitiveType.Cube);
                cube.name = "Room_" + i;
                cube.transform.position = pos;
                cube.transform.localScale = new Vector3(1.6f, 1.2f, 1.6f);
                cube.GetComponent<Renderer>().material = SolidMat(KindColor(spaces[i].kind));

                // A short index on each cube (full names overlap when packed); the current
                // room's name is shown once, above the player, by RefreshStatus().
                MakeText((i + 1).ToString(), new Vector3(x, 1.45f, 0f), 0.16f,
                    new Color(0.92f, 0.94f, 0.98f), TextAnchor.LowerCenter);
            }
        }

        void BuildPlayer()
        {
            _player = GameObject.CreatePrimitive(PrimitiveType.Capsule);
            _player.name = "Player";
            _player.transform.localScale = new Vector3(0.7f, 0.7f, 0.7f);
            _player.GetComponent<Renderer>().material = EmissiveMat(new Color(1f, 0.82f, 0.22f));
            MovePlayerTo(0);
        }

        void MovePlayerTo(int idx)
        {
            if (_roomPositions.Count == 0) return;
            _current = Mathf.Clamp(idx, 0, _roomPositions.Count - 1);
            var p = _roomPositions[_current];
            _player.transform.position = new Vector3(p.x, 1.45f, -1.7f);
        }

        /// <summary>The one slice mechanic: walk the player to the next room.</summary>
        public void NextRoom()
        {
            if (_roomPositions.Count == 0) return;
            MovePlayerTo((_current + 1) % _roomPositions.Count);
            RefreshStatus();
        }

        void BuildText()
        {
            var m = Model ?? FallbackModel();
            float rowHalf = Spaces().Length * Spacing * 0.5f;

            MakeText(m.title, new Vector3(0f, 4.3f, 0f), 0.34f, Color.white, TextAnchor.MiddleCenter);
            MakeText(Subtitle(m), new Vector3(0f, 3.5f, 0f), 0.12f,
                new Color(0.78f, 0.84f, 0.96f), TextAnchor.MiddleCenter);

            // Single current-room callout, repositioned above the player by RefreshStatus().
            _currentRoomLabel = MakeText("", new Vector3(0f, 2.15f, 0f), 0.19f,
                new Color(1f, 0.86f, 0.32f), TextAnchor.LowerCenter);

            MakeText(InfoPanel(m), new Vector3(rowHalf + 1.2f, 3.7f, 0f), 0.12f,
                new Color(0.88f, 0.90f, 0.95f), TextAnchor.UpperLeft);

            _statusText = MakeText("", new Vector3(0f, -1.6f, 0f), 0.16f,
                new Color(1f, 0.85f, 0.4f), TextAnchor.MiddleCenter);
        }

        void RefreshStatus()
        {
            var spaces = Spaces();
            int idx = Mathf.Clamp(_current, 0, spaces.Length - 1);
            string cur = spaces.Length > 0 ? spaces[idx].name : "-";

            if (_currentRoomLabel != null && idx < _roomPositions.Count)
            {
                var p = _roomPositions[idx];
                _currentRoomLabel.transform.position = new Vector3(p.x, 2.15f, -0.2f);
                _currentRoomLabel.text = Clip(cur, 22);
            }
            if (_statusText != null)
            {
                _statusText.text = string.Format("{0}   |   {1} rooms   |   at room {2}/{3}:  {4}",
                    Model.genre, spaces.Length, idx + 1, spaces.Length, Clip(cur, 28));
            }
        }

        // ------------------------------------------------------------ camera

        /// <summary>Frame the whole spread (rooms + title + info panel) for a clean capture.</summary>
        public Camera MakeFramedCamera()
        {
            var camGo = new GameObject("Main Camera");
            camGo.tag = "MainCamera";
            var cam = camGo.AddComponent<Camera>();
            cam.clearFlags = CameraClearFlags.SolidColor;
            cam.backgroundColor = new Color(0.06f, 0.07f, 0.09f);
            cam.fieldOfView = 40f;

            int n = Spaces().Length;
            float rowHalf = n * Spacing * 0.5f;
            // content spans roughly from -rowHalf (left rooms) to rowHalf + panelWidth (right info panel)
            float panelWidth = 8.5f;
            float minX = -rowHalf - 1.0f;
            float maxX = rowHalf + panelWidth;
            float centerX = (minX + maxX) * 0.5f;
            float spanX = maxX - minX;

            float dist = Mathf.Clamp(spanX * 0.92f, 12f, 50f);
            camGo.transform.position = new Vector3(centerX, 3.6f, -dist);
            camGo.transform.LookAt(new Vector3(centerX, 0.5f, 0.6f));
            return cam;
        }

        // ----------------------------------------------------------- helpers

        static Material SolidMat(Color c)
        {
            var m = new Material(Shader.Find("Standard"));
            m.color = c;
            m.SetFloat("_Glossiness", 0.12f);
            return m;
        }

        static Material EmissiveMat(Color c)
        {
            var m = new Material(Shader.Find("Standard"));
            m.color = c;
            m.EnableKeyword("_EMISSION");
            m.SetColor("_EmissionColor", c * 0.65f);
            return m;
        }

        static Color KindColor(string kind)
        {
            switch ((kind ?? "").ToLowerInvariant())
            {
                case "region": return new Color(0.30f, 0.50f, 0.78f);
                case "dungeon": return new Color(0.64f, 0.27f, 0.31f);
                case "quest": return new Color(0.53f, 0.40f, 0.75f);
                case "start": return new Color(0.36f, 0.62f, 0.42f);
                default: return new Color(0.44f, 0.47f, 0.54f); // room
            }
        }

        TextMesh MakeText(string text, Vector3 pos, float charSize, Color color, TextAnchor anchor)
        {
            var go = new GameObject("Text");
            go.transform.position = pos;
            var tm = go.AddComponent<TextMesh>();
            tm.text = text;
            tm.font = _font;
            tm.fontSize = 72;
            tm.characterSize = charSize;
            tm.color = color;
            tm.anchor = anchor;
            tm.alignment = IsLeft(anchor) ? TextAlignment.Left : TextAlignment.Center;
            go.GetComponent<MeshRenderer>().material = _font.material;
            return tm;
        }

        static bool IsLeft(TextAnchor a)
        {
            return a == TextAnchor.UpperLeft || a == TextAnchor.MiddleLeft || a == TextAnchor.LowerLeft;
        }

        static Font LoadFont()
        {
            Font f = null;
            // Unity 6 dropped "Arial.ttf" in favour of "LegacyRuntime.ttf" for code-built text.
            try { f = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf"); } catch { }
            if (f == null) { try { f = Resources.GetBuiltinResource<Font>("Arial.ttf"); } catch { } }
            if (f == null) f = Font.CreateDynamicFontFromOSFont("Arial", 16);
            return f;
        }

        static string Subtitle(SceneModel m)
        {
            // Kept short so the centred subtitle never reaches the room numbers or the
            // right-hand info panel.
            return string.IsNullOrEmpty(m.setting) ? m.genre : Clip(m.setting, 52);
        }

        string InfoPanel(SceneModel m)
        {
            var sb = new StringBuilder();
            sb.AppendLine("QUESTS");
            AppendNames(sb, m.quests, 3);
            sb.AppendLine("ITEMS");
            AppendNames(sb, m.items, 3);
            sb.AppendLine("NPCS");
            AppendNames(sb, m.npcs, 3);
            if (m.qa != null)
            {
                sb.Append("QA:  " + (m.qa.playable ? "PLAYABLE" : "needs work")
                    + "   (" + m.qa.score.ToString("0.0") + "/10)");
            }
            return sb.ToString();
        }

        static void AppendNames(StringBuilder sb, NamedThing[] items, int limit)
        {
            if (items == null || items.Length == 0)
            {
                sb.AppendLine("  --");
                return;
            }
            int shown = Mathf.Min(limit, items.Length);
            for (int i = 0; i < shown; i++)
                sb.AppendLine("  - " + Clip(items[i].name, 30));
            if (items.Length > shown)
                sb.AppendLine("  +" + (items.Length - shown) + " more");
        }

        static string Clip(string value, int limit)
        {
            if (string.IsNullOrEmpty(value)) return "";
            value = value.Replace("\r", " ").Replace("\n", " ").Trim();
            return value.Length <= limit ? value : value.Substring(0, limit - 1).TrimEnd() + "…";
        }
    }
}
