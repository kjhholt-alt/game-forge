# AgentBridge installed

Source: agentbridge repo (github.com/kjhholt-alt/agentbridge).
Vendored copy of `adapters/godot/addons/agentbridge/` lives at
`addons/agentbridge/`.

To boot with the bridge:

```
AGENTBRIDGE=1 godot --path . --headless res://<your-main-scene>.tscn
```

Token written to `<userdata>/agentbridge.token`.

For game-specific state, subclass the addon's `AgentStateDump` and
override `extra_state()`.

Installed: 2026-05-05 overnight soak.
