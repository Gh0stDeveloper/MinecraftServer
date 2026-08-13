#!/usr/bin/env python3
"""RakNet-aware UDP gateway for the public BDS entry points.

Bedrock Dedicated Server intentionally omits the MCPE advertisement from its
Unconnected Pong when ``enable-lan-visibility=false``. That setting is required
when several BDS processes share one host, but Android clients stop before the
RakNet handshake if the directed ping only contains the 33-byte header.

This gateway owns the public Lobby/Survival ports, asks the corresponding BDS
backend for its real RakNet GUID, adds a complete MCPE advertisement, and
proxies every connected RakNet datagram through an isolated backend socket.
No third-party Python packages are required.
"""

from __future__ import annotations

import json
import os
import secrets
import selectors
import signal
import socket
import struct
import threading
import time
from dataclasses import dataclass
from pathlib import Path


MAGIC = bytes.fromhex("00ffff00fefefefefdfdfdfd12345678")
PING_IDS = {0x01, 0x02}
OPEN_CONNECTION_REQUEST_1 = 0x05
CLIENT_GUID = 0x4E45584F52414244
BASE = Path(os.environ.get("BEDROCK_ROOT", "/opt/bedrock-network"))


def log(message: str) -> None:
    print(f"[gateway] {message}", flush=True)


def parse_env(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.is_file():
        return values
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def int_value(values: dict[str, str], key: str, default: int) -> int:
    try:
        value = int(values.get(key, str(default)))
    except ValueError:
        return default
    return value if 1 <= value <= 65535 else default


def clean_field(value: str, fallback: str) -> str:
    cleaned = " ".join((value or fallback).replace(";", ",").split())
    return cleaned[:120] or fallback


def read_bds_version() -> str | None:
    path = BASE / "state" / "bds-version"
    if not path.is_file():
        return None
    value = path.read_text(encoding="utf-8", errors="replace").strip()
    return value if value and value.lower() != "none" else None


def query_mcpe(port: int, timeout: float = 0.25) -> tuple[int, str | None] | None:
    sent = int(time.time() * 1000)
    packet = b"\x01" + struct.pack(">Q", sent) + MAGIC + struct.pack(">Q", CLIENT_GUID)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(timeout)
    try:
        sock.sendto(packet, ("127.0.0.1", port))
        data, _ = sock.recvfrom(4096)
    except OSError:
        return None
    finally:
        sock.close()
    if len(data) < 35 or data[0] != 0x1C or data[17:33] != MAGIC:
        return None
    try:
        length = struct.unpack(">H", data[33:35])[0]
        fields = data[35 : 35 + length].decode("utf-8", errors="replace").split(";")
        protocol = int(fields[2])
        version = fields[3].strip() or None
    except (IndexError, ValueError, struct.error):
        return None
    # PowerNukkitX 3.0.2 can emit an otherwise valid MCPE advertisement with
    # an empty display-version field. RakNet compatibility is determined by
    # the numeric protocol, so keep that source usable and let the gateway
    # publish the installed BDS version from state/bds-version.
    if not fields or fields[0] != "MCPE" or protocol <= 0:
        return None
    return protocol, version


class CompatibilityCache:
    """Learns the live Bedrock protocol from a healthy PNX instance."""

    def __init__(self, config: dict[str, str]):
        self._lock = threading.Lock()
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None
        self._protocol: int | None = None
        self._manual = False
        self._cache_path = BASE / "state" / "gateway-compatibility.json"
        self._persisted_protocol: int | None = None
        self._version: str | None = clean_field(
            config.get("BEDROCK_VERSION", "") or read_bds_version() or "", ""
        ) or None
        try:
            configured = int(config.get("BEDROCK_PROTOCOL", "0") or "0")
        except ValueError:
            configured = 0
        if configured > 0:
            self._protocol = configured
            self._manual = True
        elif self._cache_path.is_file():
            try:
                cached = json.loads(self._cache_path.read_text(encoding="utf-8"))
                cached_protocol = int(cached.get("protocol", 0))
                if cached_protocol > 0:
                    self._protocol = cached_protocol
                    self._persisted_protocol = cached_protocol
                    log(f"protocolo Bedrock recuperado de caché: {cached_protocol}")
            except (OSError, ValueError, TypeError, json.JSONDecodeError):
                pass
        self._ports = tuple(
            int_value(config, key, default)
            for key, default in (
                ("PVP_PORT", 19134),
                ("BEDWARS_PORT", 19135),
                ("SKYWARS_PORT", 19136),
            )
        )

    def start(self) -> None:
        if self._manual:
            log(f"protocolo Bedrock configurado manualmente: {self._protocol}")
            return
        self._thread = threading.Thread(target=self._discover, name="protocol-discovery", daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        if self._thread is not None:
            self._thread.join(timeout=1)

    def snapshot(self) -> tuple[int, str] | None:
        with self._lock:
            if self._protocol is None:
                return None
            return self._protocol, self._version or "Bedrock"

    def _discover(self) -> None:
        announced: tuple[int, str | None] | None = None
        while not self._stop.is_set():
            found = None
            for port in self._ports:
                found = query_mcpe(port)
                if found is not None:
                    break
            if found is not None:
                protocol, advertised_version = found
                with self._lock:
                    self._protocol = protocol
                    if self._version is None and advertised_version:
                        self._version = advertised_version
                self._persist(protocol)
                if announced != found:
                    log(f"compatibilidad aprendida desde UDP/{port}: protocolo={protocol}, versión={self._version}")
                    announced = found
                delay = 30
            else:
                delay = 2
            self._stop.wait(delay)

    def _persist(self, protocol: int) -> None:
        if protocol == self._persisted_protocol:
            return
        try:
            self._cache_path.parent.mkdir(parents=True, exist_ok=True)
            temporary = self._cache_path.with_suffix(".json.tmp")
            temporary.write_text(
                json.dumps({"protocol": protocol}, separators=(",", ":")),
                encoding="utf-8",
            )
            os.replace(temporary, self._cache_path)
            self._persisted_protocol = protocol
        except OSError as exc:
            log(f"no se pudo guardar la compatibilidad aprendida: {exc}")


@dataclass
class PendingPing:
    client: tuple[str, int]
    timestamp: bytes
    expires_at: float


@dataclass
class Session:
    sock: socket.socket
    client: tuple[str, int]
    last_seen: float


class Endpoint:
    def __init__(
        self,
        selector: selectors.BaseSelector,
        ident: str,
        public_port: int,
        backend_port: int,
        motd: str,
        description: str,
        max_players: int,
        game_mode: str,
        game_mode_id: int,
        compatibility: CompatibilityCache,
        session_ttl: int,
        max_sessions: int,
    ):
        self.selector = selector
        self.ident = ident
        self.public_port = public_port
        self.backend_port = backend_port
        self.motd = clean_field(motd, f"Nexora | {ident.title()}")
        self.description = clean_field(description, "Nexora Bedrock Network")
        self.max_players = max(1, max_players)
        self.game_mode = game_mode
        self.game_mode_id = game_mode_id
        self.compatibility = compatibility
        self.session_ttl = max(30, session_ttl)
        self.max_sessions = max(32, max_sessions)
        self.pending: dict[int, PendingPing] = {}
        self.sessions: dict[tuple[str, int], Session] = {}
        self._last_missing_protocol_log = 0.0

        self.public = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.public.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.public.bind(("0.0.0.0", public_port))
        self.public.setblocking(False)
        selector.register(self.public, selectors.EVENT_READ, ("public", self))

        self.probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.probe.bind(("127.0.0.1", 0))
        self.probe.connect(("127.0.0.1", backend_port))
        self.probe.setblocking(False)
        selector.register(self.probe, selectors.EVENT_READ, ("probe", self))
        log(f"{ident}: 0.0.0.0:{public_port} -> 127.0.0.1:{backend_port}")

    def on_public(self) -> None:
        while True:
            try:
                data, client = self.public.recvfrom(65535)
            except BlockingIOError:
                return
            except OSError as exc:
                log(f"{self.ident}: error leyendo puerto público: {exc}")
                return
            if self._is_unconnected_ping(data):
                self._request_advertisement(data, client)
            else:
                self._forward_client(data, client)

    def on_probe(self) -> None:
        while True:
            try:
                data = self.probe.recv(4096)
            except BlockingIOError:
                return
            except OSError:
                return
            if len(data) < 33 or data[0] != 0x1C or data[17:33] != MAGIC:
                continue
            nonce = struct.unpack(">Q", data[1:9])[0]
            pending = self.pending.pop(nonce, None)
            if pending is None:
                continue
            compatibility = self.compatibility.snapshot()
            if compatibility is None:
                now = time.monotonic()
                if now - self._last_missing_protocol_log >= 10:
                    log(
                        f"{self.ident}: BDS responde, pero todavía no hay protocolo MCPE; "
                        "esperando una instancia PNX saludable o BEDROCK_PROTOCOL"
                    )
                    self._last_missing_protocol_log = now
                continue
            protocol, version = compatibility
            server_guid = struct.unpack(">Q", data[9:17])[0]
            players = min(self.max_players, self.active_session_count())
            advertisement = (
                f"MCPE;{self.motd};{protocol};{version};{players};{self.max_players};"
                f"{server_guid};{self.description};{self.game_mode};{self.game_mode_id};"
                f"{self.public_port};{self.public_port};"
            ).encode("utf-8")
            pong = bytearray(data[:33])
            pong[1:9] = pending.timestamp
            pong.extend(struct.pack(">H", len(advertisement)))
            pong.extend(advertisement)
            try:
                self.public.sendto(pong, pending.client)
            except OSError:
                pass

    def on_session(self, session: Session) -> None:
        try:
            while True:
                data = session.sock.recv(65535)
                if not data:
                    break
                session.last_seen = time.monotonic()
                self.public.sendto(data, session.client)
        except BlockingIOError:
            return
        except OSError:
            self._drop_session(session.client)

    def cleanup(self, now: float) -> None:
        for nonce, pending in list(self.pending.items()):
            if pending.expires_at <= now:
                self.pending.pop(nonce, None)
        for client, session in list(self.sessions.items()):
            if session.last_seen + self.session_ttl <= now:
                self._drop_session(client)

    def close(self) -> None:
        for client in list(self.sessions):
            self._drop_session(client)
        for sock in (self.public, self.probe):
            try:
                self.selector.unregister(sock)
            except (KeyError, ValueError):
                pass
            sock.close()

    def active_session_count(self) -> int:
        threshold = time.monotonic() - 30
        return sum(session.last_seen >= threshold for session in self.sessions.values())

    @staticmethod
    def _is_unconnected_ping(data: bytes) -> bool:
        return len(data) >= 25 and data[0] in PING_IDS and data[9:25] == MAGIC

    def _request_advertisement(self, data: bytes, client: tuple[str, int]) -> None:
        if len(self.pending) >= 1024:
            oldest = min(self.pending, key=lambda key: self.pending[key].expires_at)
            self.pending.pop(oldest, None)
        nonce = secrets.randbits(63)
        while nonce in self.pending:
            nonce = secrets.randbits(63)
        packet = bytearray(data[:33])
        if len(packet) < 33:
            packet.extend(b"\x00" * (33 - len(packet)))
        packet[1:9] = struct.pack(">Q", nonce)
        self.pending[nonce] = PendingPing(client, data[1:9], time.monotonic() + 2)
        try:
            self.probe.send(packet)
        except OSError:
            self.pending.pop(nonce, None)

    def _forward_client(self, data: bytes, client: tuple[str, int]) -> None:
        if not data:
            return
        session = self.sessions.get(client)
        if session is None:
            if data[0] != OPEN_CONNECTION_REQUEST_1:
                return
            if len(self.sessions) >= self.max_sessions:
                oldest = min(self.sessions, key=lambda key: self.sessions[key].last_seen)
                self._drop_session(oldest)
            backend = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            backend.bind(("127.0.0.1", 0))
            backend.connect(("127.0.0.1", self.backend_port))
            backend.setblocking(False)
            session = Session(backend, client, time.monotonic())
            self.sessions[client] = session
            self.selector.register(backend, selectors.EVENT_READ, ("session", self, session))
        session.last_seen = time.monotonic()
        try:
            session.sock.send(data)
        except OSError:
            self._drop_session(client)

    def _drop_session(self, client: tuple[str, int]) -> None:
        session = self.sessions.pop(client, None)
        if session is None:
            return
        try:
            self.selector.unregister(session.sock)
        except (KeyError, ValueError):
            pass
        session.sock.close()


def endpoint_config(config: dict[str, str], ident: str) -> dict:
    upper = ident.upper()
    defaults = {
        "lobby": (19132, 20132, "Adventure", 2),
        "survival": (19133, 20133, "Survival", 0),
    }
    public_default, backend_default, mode_default, mode_id = defaults[ident]
    properties = parse_env(BASE / "instances" / ident / "server.properties")
    try:
        max_players = int(properties.get("max-players", config.get("MAX_PLAYERS", "20")))
    except ValueError:
        max_players = 20
    game_mode = properties.get("gamemode", mode_default).strip().title() or mode_default
    return {
        "ident": ident,
        "public_port": int_value(config, f"{upper}_PORT", public_default),
        "backend_port": int_value(config, f"{upper}_BACKEND_PORT", backend_default),
        "motd": properties.get("server-name", f"Nexora Network | {ident.title()}"),
        "description": config.get(
            "SERVER_DESCRIPTION", "Survival, PvP, BedWars y SkyWars en una sola aventura"
        ),
        "max_players": max_players,
        "game_mode": game_mode,
        "game_mode_id": mode_id,
    }


def main() -> int:
    config = parse_env(BASE / "config" / "network.env")
    selector = selectors.DefaultSelector()
    compatibility = CompatibilityCache(config)
    session_ttl = int_value(config, "GATEWAY_SESSION_TTL", 120)
    max_sessions = int_value(config, "GATEWAY_MAX_SESSIONS", 2048)
    endpoints: list[Endpoint] = []
    running = True

    def stop(_signum=None, _frame=None) -> None:
        nonlocal running
        running = False

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        for ident in ("lobby", "survival"):
            endpoints.append(
                Endpoint(
                    selector,
                    compatibility=compatibility,
                    session_ttl=session_ttl,
                    max_sessions=max_sessions,
                    **endpoint_config(config, ident),
                )
            )
        compatibility.start()
        while running:
            for key, _mask in selector.select(timeout=1):
                kind, endpoint, *rest = key.data
                if kind == "public":
                    endpoint.on_public()
                elif kind == "probe":
                    endpoint.on_probe()
                elif kind == "session":
                    endpoint.on_session(rest[0])
            now = time.monotonic()
            for endpoint in endpoints:
                endpoint.cleanup(now)
    finally:
        compatibility.stop()
        for endpoint in endpoints:
            endpoint.close()
        selector.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
