"""Tail Transport Fever 2's stdout log and forward tagged JSON snapshots over WebSocket."""
from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Optional

try:
    import websockets
except ModuleNotFoundError as exc:  # pragma: no cover - optional dependency guard
    websockets = None
    _IMPORT_ERROR = exc
else:
    _IMPORT_ERROR = None


@dataclass
class RelayOptions:
    log_path: Path
    prefix: str
    host: str
    port: int
    poll_interval: float
    seek_from_start: bool


class RelayServer:
    def __init__(self, options: RelayOptions) -> None:
        self.options = options
        self._queue: asyncio.Queue[Dict[str, Any]] = asyncio.Queue()
        self._clients: set[websockets.WebSocketServerProtocol] = set()
        self._lock = asyncio.Lock()

    def enqueue(self, payload: Dict[str, Any]) -> None:
        self._queue.put_nowait(payload)

    async def _broadcast(self, message: str) -> None:
        if not self._clients:
            return
        stale: list[websockets.WebSocketServerProtocol] = []
        for ws in self._clients.copy():
            try:
                await ws.send(message)
            except Exception:
                stale.append(ws)
        for ws in stale:
            await self._unregister(ws)

    async def _register(self, websocket: websockets.WebSocketServerProtocol) -> None:
        async with self._lock:
            self._clients.add(websocket)

    async def _unregister(self, websocket: websockets.WebSocketServerProtocol) -> None:
        async with self._lock:
            if websocket in self._clients:
                self._clients.remove(websocket)
            try:
                await websocket.close()
            except Exception:
                pass

    async def _consumer(self) -> None:
        while True:
            payload = await self._queue.get()
            message = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
            await self._broadcast(message)

    async def _handler(self, websocket: websockets.WebSocketServerProtocol) -> None:
        await self._register(websocket)
        try:
            await websocket.wait_closed()
        finally:
            await self._unregister(websocket)

    async def run(self) -> None:
        consumer_task = asyncio.create_task(self._consumer())
        async with websockets.serve(self._handler, self.options.host, self.options.port):
            await consumer_task


def _parse_line(prefix: str, raw_line: str) -> Optional[Dict[str, Any]]:
    if prefix:
        if not raw_line.startswith(prefix):
            return None
        payload = raw_line[len(prefix):].lstrip()
    else:
        payload = raw_line

    parsed_json: Optional[Any]
    try:
        parsed_json = json.loads(payload)
    except json.JSONDecodeError:
        parsed_json = None

    return {
        "raw": raw_line,
        "payload": payload,
        "data": parsed_json,
        "received": time.time(),
    }


def _tail_file(loop: asyncio.AbstractEventLoop, server: RelayServer, options: RelayOptions, stop_event: threading.Event) -> None:
    """Background thread that tails the Transport Fever 2 stdout log."""
    path = options.log_path
    prefix = options.prefix
    poll_interval = options.poll_interval

    seek_from_start = options.seek_from_start

    while not stop_event.is_set():
        try:
            with path.open("r", encoding="utf-8", errors="ignore") as handle:
                if not seek_from_start:
                    handle.seek(0, os.SEEK_END)
                seek_from_start = True

                while not stop_event.is_set():
                    position = handle.tell()
                    line = handle.readline()
                    if not line:
                        time.sleep(poll_interval)
                        try:
                            current_size = path.stat().st_size
                        except FileNotFoundError:
                            break
                        if current_size < position:
                            # File was truncated/rotated; reopen from start next loop.
                            break
                        continue

                    clean_line = line.strip()
                    if not clean_line:
                        continue

                    parsed = _parse_line(prefix, clean_line)
                    if parsed is None:
                        continue

                    loop.call_soon_threadsafe(server.enqueue, parsed)
        except FileNotFoundError:
            time.sleep(1.0)
        except Exception as exc:
            print(f"Relay tailer error: {exc}", file=sys.stderr)
            time.sleep(1.0)

        # On restart, continue from the beginning to catch fresh content.
        seek_from_start = True


def _validate_dependencies() -> None:
    if websockets is None:  # pragma: no cover - executed when dependency missing
        raise RuntimeError(
            "The 'websockets' package is required. Install it with 'pip install websockets'."
        ) from _IMPORT_ERROR


def parse_args(argv: list[str]) -> RelayOptions:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "log_path",
        type=Path,
        help="Path to Transport Fever 2 stdout.txt file",
    )
    parser.add_argument(
        "--prefix",
        default="[TF2ANALYTICS]",
        help="Tag prefix that identifies exporter lines",
    )
    parser.add_argument(
        "--host",
        default="127.0.0.1",
        help="Host/IP for the WebSocket server",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=8765,
        help="Port for the WebSocket server",
    )
    parser.add_argument(
        "--poll-interval",
        type=float,
        default=0.25,
        help="Polling interval when waiting for new log data",
    )
    parser.add_argument(
        "--from-start",
        action="store_true",
        help="Begin streaming from the start of the file instead of only new data",
    )

    args = parser.parse_args(argv)

    return RelayOptions(
        log_path=args.log_path.expanduser(),
        prefix=args.prefix,
        host=args.host,
        port=args.port,
        poll_interval=args.poll_interval,
        seek_from_start=args.from_start,
    )


def main(argv: Optional[list[str]] = None) -> int:
    _validate_dependencies()
    options = parse_args(argv or sys.argv[1:])

    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)

    server = RelayServer(options)
    stop_event = threading.Event()
    tail_thread = threading.Thread(
        target=_tail_file,
        args=(loop, server, options, stop_event),
        name="tf2-log-tail",
        daemon=True,
    )
    tail_thread.start()

    try:
        loop.run_until_complete(server.run())
    except KeyboardInterrupt:
        pass
    finally:
        stop_event.set()
        tail_thread.join(timeout=1.0)
        loop.stop()
        loop.close()

    return 0


if __name__ == "__main__":  # pragma: no cover - manual execution entry point
    raise SystemExit(main())
