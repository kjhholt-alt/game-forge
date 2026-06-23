using System;
using System.IO;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEditor.SceneManagement;
using UnityEngine;
using GameForge.Runtime;

namespace GameForge.Editor
{
    /// <summary>
    /// Headless standalone Windows player build, so an exported GameForge game can be
    /// handed over as a double-click .exe. The startup scene is constructed IN CODE
    /// (a single GameForgeRuntime that builds everything at Start) and saved at build
    /// time -- there are no hand-authored .unity/.prefab files in the template.
    ///
    ///   Unity.exe -batchmode -projectPath &lt;proj&gt; \
    ///     -executeMethod GameForge.Editor.BuildPlayer.BuildStandaloneWindows -quit -logFile &lt;log&gt;
    ///
    /// Output dir: the GF_BUILD_OUT env var, else &lt;proj&gt;/_build.
    /// </summary>
    public static class BuildPlayer
    {
        public static void BuildStandaloneWindows()
        {
            var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            new GameObject("GameForge").AddComponent<GameForgeRuntime>();

            string scenesDir = Path.Combine(Application.dataPath, "GameForge", "Scenes");
            Directory.CreateDirectory(scenesDir);
            const string scenePath = "Assets/GameForge/Scenes/Generated.unity";
            EditorSceneManager.SaveScene(scene, scenePath);

            string outDir = Environment.GetEnvironmentVariable("GF_BUILD_OUT");
            if (string.IsNullOrEmpty(outDir))
                outDir = Path.Combine(Path.GetDirectoryName(Application.dataPath), "_build");
            Directory.CreateDirectory(outDir);
            string exePath = Path.Combine(outDir, "GameForge.exe");

            var opts = new BuildPlayerOptions
            {
                scenes = new[] { scenePath },
                locationPathName = exePath,
                target = BuildTarget.StandaloneWindows64,
                options = BuildOptions.None,
            };

            BuildReport report = BuildPipeline.BuildPlayer(opts);
            BuildSummary summary = report.summary;
            Debug.Log($"GF_BUILD_RESULT result={summary.result} errors={summary.totalErrors} " +
                      $"sizeBytes={summary.totalSize} out={exePath}");
            EditorApplication.Exit(summary.result == BuildResult.Succeeded ? 0 : 1);
        }
    }
}
