#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import secrets
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
SERVER_GUID = 0x1020304050607080
MTU = 1400


def free_port() -> int:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    sock.close()
    return port


def encode_addr(address: tuple[str, int]) -> bytes:
    packed = socket.inet_aton(address[0])
    return b"\x04" + bytes((~octet) & 0xFF for octet in packed) + struct.pack(">H", address[1])


def decode_addr(data: bytes, offset: int) -> tuple[tuple[str, int], int]:
    assert data[offset] == 4, data[offset]
    packed = bytes((~octet) & 0xFF for octet in data[offset + 1 : offset + 5])
    host = socket.inet_ntoa(packed)
    port = struct.unpack(">H", data[offset + 5 : offset + 7])[0]
    return (host, port), offset + 7


def u24le(value: int) -> bytes:
    return value.to_bytes(3, "little")


def connected_datagram(payload: bytes, sequence: int = 0, message_index: int = 0) -> bytes:
    capsule = (
        b"\x60"
        + struct.pack(">H", len(payload) * 8)
        + u24le(message_index)
        + u24le(0)
        + b"\x00"
        + payload
    )
    return b"\x80" + u24le(sequence) + capsule


def first_payload(data: bytes) -> bytes:
    assert len(data) >= 14 and (data[0] & 0xE0) == 0x80, data.hex()
    offset = 4
    flags = data[offset]
    reliability = (flags >> 5) & 0x07
    split = bool(flags & 0x10)
    bit_length = struct.unpack(">H", data[offset + 1 : offset + 3])[0]
    offset += 3
    if reliability in {2, 3, 4, 6, 7}:
        offset += 3
    if reliability in {1, 4}:
        offset += 3
    if reliability in {1, 3, 4, 7}:
        offset += 4
    assert not split
    length = (bit_length + 7) // 8
    return data[offset : offset + length]


class FakeRakNet(threading.Thread):
    def __init__(self, port: int, *, advertisement: bytes | None = None):
        super().__init__(daemon=True)
        self.port = port
        self.advertisement = advertisement
        self.ready = threading.Event()
        self.stop_event = threading.Event()
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.settimeout(0.1)
        self.request2_sources: list[tuple[str, int]] = []
        self.connected_sources: list[tuple[str, int]] = []

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
                pong = b"\x1c" + data[1:9] + struct.pack(">Q", SERVER_GUID) + MAGIC
                if self.advertisement is not None:
                    pong += struct.pack(">H", len(self.advertisement)) + self.advertisement
                self.sock.sendto(pong, address)
            elif data and data[0] == 0x05:
                reply = b"\x06" + MAGIC + struct.pack(">Q", SERVER_GUID) + b"\x00" + struct.pack(">H", MTU)
                self.sock.sendto(reply, address)
            elif data and data[0] == 0x07:
                self.request2_sources.append(address)
                reply = (
                    b"\x08"
                    + MAGIC
                    + struct.pack(">Q", SERVER_GUID)
                    + encode_addr(address)
                    + struct.pack(">H", MTU)
                    + b"\x00"
                )
                self.sock.sendto(reply, address)
            elif data and (data[0] & 0xE0) == 0x80:
                self.connected_sources.append(address)
                accepted = b"\x10" + encode_addr(address) + b"gateway-regression"
                self.sock.sendto(connected_datagram(accepted, sequence=1, message_index=1), address)

    def close(self) -> None:
        self.stop_event.set()
        self.sock.close()
        self.join(timeout=1)


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def ping_packet() -> bytes:
    return b"\x01" + struct.pack(">Q", int(time.time() * 1000)) + MAGIC + struct.pack(">Q", 1234)


def request1_packet() -> bytes:
    packet = b"\x05" + MAGIC + b"\x0b"
    return packet + b"\x00" * (1492 - len(packet))


def request2_packet(host: str, port: int, guid: int) -> bytes:
    return b"\x07" + MAGIC + encode_addr((host, port)) + struct.pack(">H", MTU) + struct.pack(">Q", guid)


def run_client(public_port: int) -> tuple[tuple[str, int], tuple[str, int], tuple[str, int]]:
    client = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    client.bind(("127.0.0.1", 0))
    client.settimeout(2)
    client_address = client.getsockname()
    try:
        client.sendto(request1_packet(), ("127.0.0.1", public_port))
        reply1, _ = client.recvfrom(4096)
        assert reply1[0] == 0x06 and reply1[1:17] == MAGIC, reply1.hex()
        assert struct.unpack(">H", reply1[-2:])[0] == MTU

        guid = secrets.randbits(63)
        client.sendto(request2_packet("127.0.0.1", public_port, guid), ("127.0.0.1", public_port))
        reply2, _ = client.recvfrom(4096)
        assert reply2[0] == 0x08 and reply2[1:17] == MAGIC, reply2.hex()
        reply2_address, _ = decode_addr(reply2, 25)
        assert reply2_address == client_address, (reply2_address, client_address, reply2.hex())

        client.sendto(connected_datagram(b"\x09client-connection-request"), ("127.0.0.1", public_port))
        accepted_datagram, _ = client.recvfrom(4096)
        accepted = first_payload(accepted_datagram)
        assert accepted[0] == 0x10, accepted.hex()
        accepted_address, _ = decode_addr(accepted, 1)
        assert accepted_address == client_address, (accepted_address, client_address, accepted.hex())
        return client_address, reply2_address, accepted_address
    finally:
        client.close()


def main() -> None:
    ports: list[int] = []
    while len(ports) < 5:
        candidate = free_port()
        if candidate not in ports:
            ports.append(candidate)
    lobby_public, survival_public, lobby_backend, survival_backend, pnx_port = ports
    pnx_ad = f"MCPE;PNX source;2168;;0;20;1;PNX;Survival;1;{pnx_port};{pnx_port};".encode()
    lobby_server = FakeRakNet(lobby_backend)
    survival_server = FakeRakNet(survival_backend)
    pnx_server = FakeRakNet(pnx_port, advertisement=pnx_ad)
    servers = [lobby_server, survival_server, pnx_server]
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

            lobby_client, lobby_reply2, lobby_accepted = run_client(lobby_public)
            survival_client, survival_reply2, survival_accepted = run_client(survival_public)
            assert lobby_reply2 == lobby_client == lobby_accepted
            assert survival_reply2 == survival_client == survival_accepted

            assert lobby_server.request2_sources and lobby_server.request2_sources[0] != lobby_client
            assert survival_server.request2_sources and survival_server.request2_sources[0] != survival_client
            assert lobby_server.connected_sources and survival_server.connected_sources
        finally:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=2)
            output = process.stdout.read() if process.stdout else ""
            if process.returncode not in {0, -15}:
                raise AssertionError(f"gateway exited with {process.returncode}: {output}")
            assert "Request2 RakNet recibido" in output, output
            assert "primer datagrama RakNet conectado" in output, output
            assert "ConnectionRequestAccepted normalizado" in output, output
            for server in servers:
                server.close()

    print("RakNet BDS gateway advertisement, Request2, address normalization and connected forwarding passed.")


if __name__ == "__main__":
    main()
