#!/usr/bin/env python3
from __future__ import annotations

import socket
import struct
import subprocess
import sys
import threading
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROBE = ROOT / "scripts" / "bedrock-ping.py"
MAGIC = bytes.fromhex("00ffff00fefefefefdfdfdfd12345678")


def run_probe(response_factory, *extra_args: str):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]

    def server():
        try:
            data, addr = sock.recvfrom(4096)
            sock.sendto(response_factory(data), addr)
        finally:
            sock.close()

    thread = threading.Thread(target=server, daemon=True)
    thread.start()
    result = subprocess.run(
        [sys.executable, str(PROBE), str(port), *extra_args],
        cwd=ROOT,
        text=True,
        capture_output=True,
        timeout=5,
    )
    thread.join(timeout=2)
    return result


def pong_prefix(request: bytes) -> bytes:
    timestamp = request[1:9]
    guid = struct.pack(">Q", 123456789)
    return b"\x1c" + timestamp + guid + MAGIC


def main() -> None:
    advertisement = b"MCPE;Test Lobby;2168;1.26.40;0;20;123;Test;Adventure;2;19132;19133;"
    good = run_probe(lambda req: pong_prefix(req) + struct.pack(">H", len(advertisement)) + advertisement)
    assert good.returncode == 0, good.stderr
    assert good.stdout.startswith("MCPE;Test Lobby;")

    pnx_without_version = b"MCPE;Nexora Network | PvP;2168;;0;20;123;Nexora;Survival;1;19134;19134;"
    pnx = run_probe(
        lambda req: pong_prefix(req)
        + struct.pack(">H", len(pnx_without_version))
        + pnx_without_version
    )
    assert pnx.returncode == 0, pnx.stderr
    assert pnx.stdout.startswith("MCPE;Nexora Network | PvP;2168;;")

    bare = run_probe(pong_prefix)
    assert bare.returncode != 0
    assert "33 bytes" in bare.stderr
    assert "falta el anuncio Bedrock MCPE" in bare.stderr

    invalid_protocol = b"MCPE;Test Lobby;0;1.26.40;0;20;123;Test;Adventure;2;19132;19133;"
    invalid = run_probe(lambda req: pong_prefix(req) + struct.pack(">H", len(invalid_protocol)) + invalid_protocol)
    assert invalid.returncode != 0
    assert "metadatos no utilizables" in invalid.stderr

    print("Bedrock RakNet advertisement probe regression passed.")


if __name__ == "__main__":
    main()
