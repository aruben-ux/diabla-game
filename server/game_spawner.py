"""Game server process spawner — launches and manages Godot headless instances."""

import asyncio
import os
import signal

from config import settings


async def spawn_game_server(
    game_id: int,
    port: int,
    game_seed: int,
    max_players: int,
    difficulty: str,
) -> int:
    """Spawn a Godot headless game server process. Returns the PID."""
    cmd = [
        settings.godot_executable,
        "--headless",
        "--main-pack", settings.godot_project_path,
        "--",
        "--server",
        f"--game-id={game_id}",
        f"--port={port}",
        f"--seed={game_seed}",
        f"--max-players={max_players}",
        f"--difficulty={difficulty}",
        f"--lobby-url=http://127.0.0.1:{settings.port}",
        f"--server-secret={settings.game_server_secret}",
    ]

    log_path = f"/opt/diabla/logs/game_{game_id}.log"
    os.makedirs("/opt/diabla/logs", exist_ok=True)
    # Truncate old log and cap output to prevent filling disk
    log_file = open(log_path, "w")

    process = await asyncio.create_subprocess_exec(
        *cmd,
        stdout=asyncio.subprocess.DEVNULL,
        stderr=log_file,
    )
    print(f"[Spawner] Game server started: game_id={game_id} port={port} pid={process.pid}")
    return process.pid


async def stop_game_server(pid: int) -> None:
    """Stop a game server process by PID."""
    try:
        os.kill(pid, signal.SIGTERM)
        print(f"[Spawner] Sent SIGTERM to game server pid={pid}")
    except ProcessLookupError:
        print(f"[Spawner] Game server pid={pid} already exited")
    except OSError as e:
        print(f"[Spawner] Error stopping game server pid={pid}: {e}")
