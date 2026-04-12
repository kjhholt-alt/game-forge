"""WebSocket MCP client that connects to a running Godot MCP server.

The bridge sends JSON-RPC 2.0 messages over a WebSocket and correlates
responses using incrementing message IDs.  It is the single communication
channel between the Python agent layer and the Godot editor.
"""

from __future__ import annotations

import asyncio
import json
import logging
from typing import Any

import websockets
from websockets.asyncio.client import ClientConnection

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------

_DEFAULT_URL = "ws://localhost:6100"
_DEFAULT_TIMEOUT = 30.0  # seconds
_RECONNECT_DELAY = 2.0  # seconds between reconnect attempts
_MAX_RECONNECT_ATTEMPTS = 5


# ---------------------------------------------------------------------------
# Bridge
# ---------------------------------------------------------------------------


class GodotBridgeError(Exception):
    """Raised when the bridge encounters a non-recoverable error."""


class GodotBridge:
    """WebSocket MCP client that connects to a running Godot MCP server.

    Provides low-level methods for sending MCP tool calls and receiving
    results.  All public methods are async and safe to call concurrently.

    Usage::

        async with GodotBridge("ws://localhost:6100") as bridge:
            tools = await bridge.list_tools()
            result = await bridge.call_tool("create_scene", {"name": "Main"})
    """

    def __init__(
        self,
        url: str = _DEFAULT_URL,
        timeout: float = _DEFAULT_TIMEOUT,
    ) -> None:
        self._url = url
        self._timeout = timeout
        self._ws: ClientConnection | None = None
        self._msg_id: int = 0
        self._pending: dict[int, asyncio.Future[dict[str, Any]]] = {}
        self._listen_task: asyncio.Task[None] | None = None
        self._lock = asyncio.Lock()

    # ------------------------------------------------------------------
    # Connection lifecycle
    # ------------------------------------------------------------------

    async def connect(self) -> None:
        """Open the WebSocket connection to the Godot MCP server.

        Retries up to ``_MAX_RECONNECT_ATTEMPTS`` times with exponential
        back-off before raising :class:`GodotBridgeError`.
        """
        for attempt in range(1, _MAX_RECONNECT_ATTEMPTS + 1):
            try:
                self._ws = await websockets.connect(self._url)
                self._listen_task = asyncio.create_task(self._listen_loop())
                logger.info("Connected to Godot MCP at %s", self._url)
                return
            except (OSError, websockets.exceptions.WebSocketException) as exc:
                delay = _RECONNECT_DELAY * attempt
                logger.warning(
                    "Connection attempt %d/%d failed (%s) — retrying in %.1fs",
                    attempt,
                    _MAX_RECONNECT_ATTEMPTS,
                    exc,
                    delay,
                )
                if attempt == _MAX_RECONNECT_ATTEMPTS:
                    raise GodotBridgeError(
                        f"Failed to connect to Godot MCP at {self._url} "
                        f"after {_MAX_RECONNECT_ATTEMPTS} attempts"
                    ) from exc
                await asyncio.sleep(delay)

    async def disconnect(self) -> None:
        """Gracefully close the WebSocket and cancel the listener."""
        if self._listen_task is not None:
            self._listen_task.cancel()
            try:
                await self._listen_task
            except asyncio.CancelledError:
                pass
            self._listen_task = None

        if self._ws is not None:
            await self._ws.close()
            self._ws = None
            logger.info("Disconnected from Godot MCP")

        # Cancel any still-pending futures
        for fut in self._pending.values():
            if not fut.done():
                fut.cancel()
        self._pending.clear()

    async def is_connected(self) -> bool:
        """Return *True* if the WebSocket is open and responsive."""
        if self._ws is None:
            return False
        try:
            # websockets >=12 uses .state on the protocol
            return self._ws.state.name == "OPEN"  # type: ignore[union-attr]
        except AttributeError:
            # Fallback: try a lightweight check
            return self._ws is not None

    # ------------------------------------------------------------------
    # Context manager
    # ------------------------------------------------------------------

    async def __aenter__(self) -> GodotBridge:
        await self.connect()
        return self

    async def __aexit__(self, *args: Any) -> None:
        await self.disconnect()

    # ------------------------------------------------------------------
    # JSON-RPC helpers
    # ------------------------------------------------------------------

    def _next_id(self) -> int:
        self._msg_id += 1
        return self._msg_id

    async def _send(self, method: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        """Send a JSON-RPC 2.0 request and await the correlated response."""
        if self._ws is None:
            raise GodotBridgeError("Not connected — call connect() first")

        msg_id = self._next_id()
        payload: dict[str, Any] = {
            "jsonrpc": "2.0",
            "method": method,
            "id": msg_id,
        }
        if params is not None:
            payload["params"] = params

        loop = asyncio.get_running_loop()
        future: asyncio.Future[dict[str, Any]] = loop.create_future()
        self._pending[msg_id] = future

        raw = json.dumps(payload)
        logger.debug("TX → %s", raw)

        try:
            await self._ws.send(raw)
        except websockets.exceptions.WebSocketException as exc:
            self._pending.pop(msg_id, None)
            raise GodotBridgeError(f"Failed to send message: {exc}") from exc

        try:
            result = await asyncio.wait_for(future, timeout=self._timeout)
        except asyncio.TimeoutError:
            self._pending.pop(msg_id, None)
            raise GodotBridgeError(
                f"Timeout waiting for response to {method} (id={msg_id})"
            )

        return result

    async def _listen_loop(self) -> None:
        """Background task that reads from the WebSocket and resolves pending futures."""
        assert self._ws is not None
        try:
            async for raw in self._ws:
                logger.debug("RX ← %s", raw)
                try:
                    msg = json.loads(raw)
                except json.JSONDecodeError:
                    logger.warning("Received non-JSON message: %s", raw[:200])
                    continue

                msg_id = msg.get("id")
                if msg_id is None:
                    # Server-initiated notification — log and skip
                    logger.debug("Notification (no id): %s", msg.get("method", "?"))
                    continue

                future = self._pending.pop(msg_id, None)
                if future is None:
                    logger.warning("Received response for unknown id=%s", msg_id)
                    continue

                if "error" in msg:
                    future.set_exception(
                        GodotBridgeError(
                            f"MCP error {msg['error'].get('code', '?')}: "
                            f"{msg['error'].get('message', 'unknown')}"
                        )
                    )
                else:
                    future.set_result(msg.get("result", {}))

        except websockets.exceptions.ConnectionClosed as exc:
            logger.warning("WebSocket closed: %s", exc)
        except asyncio.CancelledError:
            return
        finally:
            # Cancel anything still waiting
            for fut in self._pending.values():
                if not fut.done():
                    fut.set_exception(GodotBridgeError("Connection lost"))
            self._pending.clear()

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    async def call_tool(self, tool_name: str, arguments: dict[str, Any] | None = None) -> dict[str, Any]:
        """Send an MCP ``tools/call`` request and return the result dict.

        Parameters
        ----------
        tool_name:
            The MCP tool name registered on the Godot server (e.g.
            ``"create_scene"``, ``"add_node"``).
        arguments:
            Key/value arguments forwarded to the tool.

        Returns
        -------
        dict
            The ``result`` field from the JSON-RPC response.
        """
        logger.debug("call_tool(%s, %s)", tool_name, arguments)
        params: dict[str, Any] = {"name": tool_name}
        if arguments:
            params["arguments"] = arguments
        return await self._send("tools/call", params)

    async def list_tools(self) -> list[dict[str, Any]]:
        """Return the list of tools advertised by the Godot MCP server."""
        result = await self._send("tools/list")
        return result.get("tools", [])

    async def ping(self) -> bool:
        """Check if the Godot MCP server is responsive.

        Sends a JSON-RPC ``ping`` and returns *True* if a valid response
        arrives within the timeout window.
        """
        try:
            await self._send("ping")
            return True
        except (GodotBridgeError, asyncio.TimeoutError):
            return False
