#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
GATEWAY = ROOT / "scripts" / "bedrock-gateway.py"
PROBE = ROOT / "scripts" / "bedrock-ping.py"
MAGIC = bytes.fromhex("00ffff00fefefefefdfdfdfd12345678")


def free_port() -> int:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    sock.close()
    return port


class FakeRakNet(threading.Thread):
    def __init__(self, port: int, *, advertisement: bytes | None = None, label: bytes = b"backend"):
        super().__init__(daemon=True)
        self.port = port
        self.advertisement = advertisement
        self.label = label
        self.ready = threading.Event()
        self.stop_event = threading.Event()
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.settimeout(0.1)

    def run(self) -> None:
        self.sock.bind(("127.0.0.1", self.port))
        self.ready.set()
        while not self.stop_event.is_set():
            try:
                data, address = self.sock.recvfrom(65535)
            except socket.timeout:
                continue
            except OSError:
                break
            if len(data) >= 25 and data[0] in {1, 2} and data[9:25] == MAGIC:
                pong = b"\x1c" + data[1:9] + struct.pack(">Q", 0x1020304050607080) + MAGIC
                if self.advertisement is not None:
                    pong += struct.pack(">H", len(self.advertisement)) + self.advertisement
                self.sock.sendto(pong, address)
            elif data and data[0] == 0x05:
                self.sock.sendto(b"\x06" + self.label, address)

    def close(self) -> None:
        self.stop_event.set()
        self.sock.close()
        self.join(timeout=1)


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def ping_packet() -> bytes:
    return b"\x01" + struct.pack(">Q", int(time.time() * 1000)) + MAGIC + struct.pack(">Q", 1234)


def main() -> None:
    ports = []
    while len(ports) < 5:
        candidate = free_port()
        if candidate not in ports:
            ports.append(candidate)
    lobby_public, survival_public, lobby_backend, survival_backend, pnx_port = ports
    # PowerNukkitX 3.0.2 at the pinned source ref advertises protocol 2168 but
    # leaves the display version field empty. The gateway must still learn the
    # protocol and use the installed BDS version for its public advertisement.
    pnx_ad = f"MCPE;PNX source;2168;;0;20;1;PNX;Survival;1;{pnx_port};{pnx_port};".encode()
    servers = [
        FakeRakNet(lobby_backend, label=b"lobby"),
        FakeRakNet(survival_backend, label=b"survival"),
        FakeRakNet(pnx_port, advertisement=pnx_ad, label=b"pnx"),
    ]
    for server in servers:
        server.start()
        assert server.ready.wait(2)

    with tempfile.TemporaryDirectory(prefix="nexora-gateway-") as tmp:
        base = Path(tmp)
        write(
            base / "config" / "network.env",
            f'''SERVER_NAME="Nexora Test"
SERVER_DESCRIPTION="Una red Bedrock de prueba"
LOBBY_PORT={lobby_public}
SURVIVAL_PORT={survival_public}
LOBBY_BACKEND_PORT={lobby_backend}
SURVIVAL_BACKEND_PORT={survival_backend}
PVP_PORT={pnx_port}
BEDWARS_PORT={pnx_port}
SKYWARS_PORT={pnx_port}
GATEWAY_SESSION_TTL=30
GATEWAY_MAX_SESSIONS=64
''',
        )
        write(base / "instances" / "lobby" / "server.properties", "server-name=Nexora Test | Lobby\ngamemode=adventure\nmax-players=20\n")
        write(base / "instances" / "survival" / "server.properties", "server-name=Nexora Test | Survival\ngamemode=survival\nmax-players=20\n")
        write(base / "state" / "bds-version", "1.26.43.1\n")
        environment = os.environ.copy()
        environment["BEDROCK_ROOT"] = str(base)
        process = subprocess.Popen(
            [sys.executable, str(GATEWAY)],
            cwd=ROOT,
            env=environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        try:
            result = None
            for _ in range(40):
                result = subprocess.run(
                    [sys.executable, str(PROBE), str(lobby_public)],
                    cwd=ROOT,
                    text=True,
                    capture_output=True,
                    timeout=3,
                )
                if result.returncode == 0:
                    break
                time.sleep(0.1)
            assert result is not None and result.returncode == 0, result.stderr
            assert result.stdout.startswith("MCPE;Nexora Test | Lobby;2168;1.26.43.1;")
            assert ";Una red Bedrock de prueba;Adventure;2;" in result.stdout
            cached = json.loads((base / "state" / "gateway-compatibility.json").read_text(encoding="utf-8"))
            assert cached == {"protocol": 2168}

            survival = subprocess.run(
                [sys.executable, str(PROBE), str(survival_public)],
                cwd=ROOT,
                text=True,
                capture_output=True,
                timeout=3,
            )
            assert survival.returncode == 0, survival.stderr
            assert "MCPE;Nexora Test | Survival;2168;1.26.43.1;" in survival.stdout

            client = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            client.settimeout(2)
            try:
                client.sendto(ping_packet(), ("127.0.0.1", lobby_public))
                pong, _ = client.recvfrom(4096)
                assert pong[0] == 0x1C and b"MCPE;Nexora Test | Lobby" in pong
                client.sendto(b"\x05open-connection-request", ("127.0.0.1", lobby_public))
                reply, _ = client.recvfrom(4096)
                assert reply == b"\x06lobby", reply
            finally:
                client.close()
        finally:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=2)
            if process.returncode not in {0, -15}:
                output = process.stdout.read() if process.stdout else ""
                raise AssertionError(f"gateway exited with {process.returncode}: {output}")
            for server in servers:
                server.close()

    print("RakNet BDS gateway advertisement and forwarding regression passed.")


if __name__ == "__main__":
    main()
