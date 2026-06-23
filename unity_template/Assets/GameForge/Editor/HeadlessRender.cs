using System;
using System.IO;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using GameForge.Runtime;

namespace GameForge.Editor
{
    /// <summary>
    /// Headless render gate. Builds the slice scene in code (via the runtime
    /// GameForgeRuntime, the single source of truth) and writes a PNG you can
    /// eyeball -- the same verify-by-looking loop war-table uses. No standalone
    /// build required.
    ///
    ///   Unity.exe -batchmode -projectPath &lt;proj&gt; \
    ///     -executeMethod GameForge.Editor.HeadlessRender.RenderSlice -quit -logFile &lt;log&gt;
    ///
    /// Output PNG: the GF_RENDER_OUT env var, else &lt;proj&gt;/_renders/slice.png.
    /// </summary>
    public static class HeadlessRender
    {
        public static void RenderSlice()
        {
            try
            {
                EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);

                var go = new GameObject("GameForge");
                var rt = go.AddComponent<GameForgeRuntime>();
                rt.Build();
                rt.NextRoom(); // prove the one mechanic mutates state before the capture

                string outPath = Environment.GetEnvironmentVariable("GF_RENDER_OUT");
                if (string.IsNullOrEmpty(outPath))
                    outPath = Path.Combine(Path.GetDirectoryName(Application.dataPath), "_renders", "slice.png");

                RenderCameraToPng(rt.Cam, 1280, 720, outPath);
                Debug.Log("GF_RENDER_OK " + outPath);
                EditorApplication.Exit(0);
            }
            catch (Exception e)
            {
                Debug.LogError("GF_RENDER_FAIL " + e);
                EditorApplication.Exit(1);
            }
        }

        // Renders a camera to an offscreen RenderTexture and writes a PNG. Lifted from
        // war-table's HeadlessRender so the capture path is identical/proven.
        public static void RenderCameraToPng(Camera cam, int w, int h, string path)
        {
            var rt = new RenderTexture(w, h, 24, RenderTextureFormat.ARGB32) { antiAliasing = 4 };
            var prev = cam.targetTexture;
            cam.targetTexture = rt;
            cam.Render();
            RenderTexture.active = rt;
            var tex = new Texture2D(w, h, TextureFormat.RGB24, false);
            tex.ReadPixels(new Rect(0, 0, w, h), 0, 0);
            tex.Apply();
            RenderTexture.active = null;
            cam.targetTexture = prev;
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            File.WriteAllBytes(path, tex.EncodeToPNG());
            UnityEngine.Object.DestroyImmediate(rt);
            Debug.Log("HEADLESS_RENDER_WROTE: " + path);
        }
    }
}
