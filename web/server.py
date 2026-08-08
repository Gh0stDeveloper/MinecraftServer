#!/usr/bin/env python3
from __future__ import annotations

import json
import mimetypes
import os
import socket
import struct
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlparse

BASE = Path(os.environ.get("BEDROCK_BASE", "/opt/bedrock-network"))
STATIC = Path(__file__).resolve().parent / "static"
HOST = os.environ.get("WEB_HOST", "0.0.0.0")
PORT = int(os.environ.get("WEB_PORT", "8080"))
INSTANCES = ("lobby", "survival", "pvp", "bedwars", "skywars")
MAGIC = bytes.fromhex("00ffff00fefefefefdfdfdfd12345678")


def parse_env(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    if not path.exists():
        return result
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        result[key.strip()] = value.strip().strip('"').strip("'")
    return result


def parse_properties(path: Path) -> dict[str, str]:
    return parse_env(path)


def ping_bedrock(port: int, timeout: float = 0.35) -> dict:
    sent = int(time.time() * 1000)
    packet = b"\x01" + struct.pack(">Q", sent) + MAGIC + struct.pack(">Q", 0x4E45584F52414244)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(timeout)
    try:
        sock.sendto(packet, ("127.0.0.1", port))
        data, _ = sock.recvfrom(4096)
    except OSError:
        return {"online": False, "players": 0, "max_players": None, "version": None, "motd": None}
    finally:
        sock.close()

    if len(data) < 35 or data[0] != 0x1C:
        return {"online": True, "players": None, "max_players": None, "version": None, "motd": None}
    try:
        text_len = struct.unpack(">H", data[33:35])[0]
        text = data[35:35 + text_len].decode("utf-8", errors="replace")
        parts = text.split(";")
        return {
            "online": True,
            "motd": parts[1] if len(parts) > 1 else None,
            "version": parts[3] if len(parts) > 3 else None,
            "players": int(parts[4]) if len(parts) > 4 and parts[4].isdigit() else None,
            "max_players": int(parts[5]) if len(parts) > 5 and parts[5].isdigit() else None,
        }
    except (ValueError, struct.error):
        return {"online": True, "players": None, "max_players": None, "version": None, "motd": None}


def status_payload() -> dict:
    env = parse_env(BASE / "config" / "network.env")
    state_version = BASE / "state" / "bds-version"
    bds_version = state_version.read_text(encoding="utf-8").strip() if state_version.exists() else None
    servers = []
    total_players = 0
    for instance in INSTANCES:
        props = parse_properties(BASE / "instances" / instance / "server.properties")
        port = int(props.get("server-port", env.get(f"{instance.upper()}_PORT", "19132")))
        ping = ping_bedrock(port)
        if isinstance(ping.get("players"), int):
            total_players += ping["players"]
        servers.append({
            "id": instance,
            "name": props.get("server-name", instance.title()),
            "port": port,
            **ping,
        })
    return {
        "network": env.get("SERVER_NAME", "Bedrock Network"),
        "host": env.get("PUBLIC_HOST", "127.0.0.1"),
        "lobby_port": int(env.get("LOBBY_PORT", "19132")),
        "bds_version": bds_version,
        "players": total_players,
        "servers": servers,
        "generated_at": int(time.time()),
    }


class Handler(BaseHTTPRequestHandler):
    server_version = "BedrockNetworkWeb/1.0"

    def log_message(self, fmt: str, *args) -> None:
        print(f"[web] {self.address_string()} {fmt % args}")

    def common_headers(self) -> None:
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Permissions-Policy", "camera=(), microphone=(), geolocation=()")
        self.send_header("Cache-Control", "no-store")

    def json_response(self, payload: dict, status: int = 200) -> None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.common_headers()
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/api/status":
            self.json_response(status_payload())
            return
        if parsed.path == "/healthz":
            self.json_response({"ok": True})
            return

        rel = unquote(parsed.path.lstrip("/")) or "index.html"
        target = (STATIC / rel).resolve()
        try:
            target.relative_to(STATIC.resolve())
        except ValueError:
            self.send_error(403)
            return
        if not target.is_file():
            target = STATIC / "index.html"
        data = target.read_bytes()
        content_type = mimetypes.guess_type(target.name)[0] or "application/octet-stream"
        self.send_response(200)
        self.common_headers()
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def main() -> None:
    httpd = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"Bedrock Network web escuchando en http://{HOST}:{PORT}")
    httpd.serve_forever()


if __name__ == "__main__":
    main()
