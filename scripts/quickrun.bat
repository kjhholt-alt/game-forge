@echo off
REM Game-Forge quickrun — full pipeline + gallery + open the export folder.
REM
REM Run once: `scripts\quickrun.bat`
REM
REM Steps:
REM   1. Full 5-stage pipeline (concept -> world -> mechanics -> narrative ->
REM      art -> QA) via claudex.ask_structured. ~4.5 min, ~$1.50 on Max sub.
REM   2. Generate human-readable Markdown gallery (docs/GAME_GALLERY.md).
REM   3. Open the export folder in Explorer so you can see the Godot
REM      project the agents just built.

setlocal
cd /d "%~dp0\.."

echo === Game-Forge quickrun ===
echo.

echo [1/3] Running full 5-stage pipeline...
py scripts\smoke_full_pipeline.py
if errorlevel 1 (
  echo.
  echo Pipeline failed. See scripts\smoke_full_pipeline.report.json
  exit /b 1
)

echo.
echo [2/3] Generating gallery markdown...
py scripts\dump_game_gallery.py
if errorlevel 1 (
  echo Gallery generation failed.
  exit /b 1
)

echo.
echo [3/3] Opening export folder...
explorer scripts\smoke_full_pipeline.export

echo.
echo === Done. Next steps ===
echo   - open docs\GAME_GALLERY.md to read the design
echo   - open scripts\smoke_full_pipeline.export\project.godot in Godot 4.6
echo.

endlocal
