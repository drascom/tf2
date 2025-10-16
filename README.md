# Transport Fever 2 realtime analytics exporter

This repository contains a Transport Fever 2 script mod and a lightweight relay that turns the game log into a realtime data stream for dashboards and other tooling.

## Repository layout

```
mods/
  tf2-realtime-export/
    mod.lua                      # Mod metadata and settings exposed in-game
    res/scripts/
      game_script.lua            # Entry point registered as a game script
      tf2_realtime_export/
        exporter.lua             # Collects data and prints JSON snapshots
        json.lua                 # Minimal JSON encoder used in the sandbox

tools/
  relay/
    relay.py                     # Python tailer that forwards snapshots via WebSocket
```

## Installing the mod

1. Copy `mods/tf2-realtime-export` into your Transport Fever 2 `mods` directory (usually located next to the `userdata` folder).
2. Enable the mod from the in-game mod manager. The script exposes two settings:
   - **Snapshot interval** – choose how often the exporter emits a snapshot (default 2 seconds of simulation time).
   - **Include cargo wait breakdown** – when enabled, the waiting cargo per type is included for every station.
3. Load a savegame or start a new map. The mod registers itself as a `game_script` so it runs without additional setup.

## What the mod prints

Every `exportInterval` seconds of simulation time, the exporter gathers a compact snapshot containing:

- Current simulation time and in-game date/finances.
- All towns (population, growth, target population, cargo fulfilment).
- All industries (production, shipment and transport metrics).
- All stations (town ownership and waiting passengers/cargo, optionally broken down by cargo type).
- All lines (basic metadata, vehicle list, line statistics when available).

Each snapshot is written as a single log line in the form:

```
[TF2ANALYTICS] {"simTime":1234.5,"date":{"year":1920,...}, ...}
```

The prefix makes it easy for external tools to filter the relevant lines inside `stdout.txt`.

## Running the relay

The mod itself does not open sockets from Lua (not supported by the sandbox). Instead, we tail the game log and push snapshots to the outside world. A small Python helper is included:

1. Install Python 3.9+ and the `websockets` dependency:

   ```bash
   pip install websockets
   ```

2. Locate Transport Fever 2's live log file. On Windows it is typically under `%USERPROFILE%\AppData\Roaming\Transport Fever 2\crash_dump\stdout.txt` while the game is running.

3. Run the relay, pointing it at the log file:

   ```bash
   python tools/relay/relay.py "C:/Users/<you>/AppData/Roaming/Transport Fever 2/crash_dump/stdout.txt"
   ```

   Additional flags are available:

   - `--port 9000` – change the WebSocket port.
   - `--host 0.0.0.0` – listen on all interfaces.
   - `--from-start` – replay the entire file instead of only new lines.
   - `--prefix "[MYTAG]"` – if you recompile the Lua prefix.

4. Connect your web application to `ws://localhost:8765/`. Every message contains the original raw line, the trimmed payload and the parsed JSON object (when decoding succeeds).

The relay watches for file truncation/rotation and automatically keeps streaming when the game restarts.

## Extending the pipeline

- Throttle the exporter further if you only need minute-level updates.
- Append custom metrics in `exporter.lua` (vehicle utilization, cargo fulfillment, etc.).
- Store snapshots in a database or send them to a real-time dashboard service from the relay process.

## Development notes

The Lua code is defensive: every Transport Fever API call is wrapped in `pcall` so the exporter keeps running even if a particular API is unavailable in a given context. The JSON encoder is sandbox-friendly (no `ffi` or filesystem usage) and avoids circular references.
