namespace GameForge.Generated
{
    /// <summary>
    /// Per-game codegen seam. orchestrator/unity_exporter.py OVERWRITES this file at
    /// export time with the exported game's title/genre/space names baked in as
    /// compile-time constants -- the "structured data -&gt; C# gameplay systems" path,
    /// and a compiled fallback for GameForgeRuntime when the JSON manifest is missing.
    ///
    /// This default ships with the template so it always compiles standalone.
    /// </summary>
    public static class GeneratedGameInfo
    {
        public const string Title = "GameForge Template";
        public const string Genre = "sandbox";
        public const int SpaceCount = 3;
        public static readonly string[] SpaceNames = { "Antechamber", "Hall of Echoes", "The Vault" };
    }
}
