#!/usr/bin/env python3
from __future__ import annotations

import socket
import struct
import sys
import time

MAGIC = bytes.fromhex("00ffff00fefefefefdfdfdfd12345678")
CLIENT_GUID = 0x4E45584F52414244


def fail(message: str) -> int:
    print(message, file=sys.stderr)
    return 1


def main() -> int:
    args = list(sys.argv[1:])
    allow_bare = False
    if "--allow-bare" in args:
        args.remove("--allow-bare")
        allow_bare = True
    if len(args) not in {1, 2}:
        return fail(f"Uso: {sys.argv[0]} PUERTO [HOST] [--allow-bare]")
    try:
        port = int(args[0])
    except ValueError:
        return fail("Puerto inválido.")
    if not 1 <= port <= 65535:
        return fail("Puerto fuera de rango.")
    host = args[1] if len(args) == 2 else "127.0.0.1"

    sent = int(time.time() * 1000)
    packet = b"\x01" + struct.pack(">Q", sent) + MAGIC + struct.pack(">Q", CLIENT_GUID)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(1.5)
    try:
        sock.sendto(packet, (host, port))
        data, _ = sock.recvfrom(4096)
    except OSError as exc:
        return fail(f"Sin respuesta Bedrock/RakNet en UDP/{port}: {exc}")
    finally:
        sock.close()

    if not data or data[0] != 0x1C:
        return fail(f"UDP/{port} respondió, pero no con Unconnected Pong RakNet (0x1c).")

    # Con enable-lan-visibility=false, BDS puede contestar al ping dirigido con
    # el encabezado RakNet de 33 bytes y omitir deliberadamente la cadena MCPE.
    # Ese estado demuestra que el transporte RakNet está vivo; solo se acepta
    # cuando el llamador lo solicita explícitamente para una instancia BDS.
    if len(data) == 33 and allow_bare:
        print("RAKNET;bare")
        return 0
    if len(data) < 35:
        return fail(
            f"UDP/{port} devolvió un pong RakNet incompleto de {len(data)} bytes; "
            "falta el anuncio Bedrock MCPE."
        )

    advertised_len = struct.unpack(">H", data[33:35])[0]
    if advertised_len <= 0 or len(data) < 35 + advertised_len:
        return fail(
            f"UDP/{port} devolvió un pong RakNet sin anuncio Bedrock completo "
            f"({len(data)} bytes, anuncio declarado={advertised_len})."
        )

    advertisement = data[35 : 35 + advertised_len].decode("utf-8", errors="replace")
    if not advertisement.startswith("MCPE;"):
        return fail(f"UDP/{port} respondió, pero el anuncio no comienza con MCPE;: {advertisement!r}")

    print(advertisement)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
