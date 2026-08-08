#!/usr/bin/env python3
"""Download and validate a Minecraft Bedrock Dedicated Server archive safely.

Python's urllib/http.client uses HTTP/1.1, which avoids the HTTP/2 transport
failure seen with curl on some Oracle/Cloud routes. Downloads are written to a
.part file and are only promoted to the cache after integrity and ZIP checks.
"""
from __future__ import annotations

import argparse
import hashlib
import os
import re
import socket
import sys
import time
import urllib.error
import urllib.request
import zipfile
from http.client import IncompleteRead
from pathlib import Path
from urllib.parse import urlparse

ALLOWED_HOSTS = {"www.minecraft.net", "minecraft.net", "minecraft.azureedge.net"}
SHA1_RE = re.compile(r"^[0-9a-fA-F]{40}$")


def validate_url(url: str) -> None:
    parsed = urlparse(url)
    if parsed.scheme != "https" or parsed.hostname not in ALLOWED_HOSTS:
        raise ValueError(f"URL BDS no oficial o no permitida: {url}")
    if "bin-linux" not in parsed.path or not parsed.path.endswith(".zip"):
        raise ValueError(f"La URL no parece un ZIP Linux de BDS: {url}")


def validate_archive(path: Path, expected_size: int | None, expected_sha1: str | None) -> None:
    size = path.stat().st_size
    if size <= 0:
        raise ValueError("La descarga BDS quedó vacía")
    if expected_size and size != expected_size:
        raise ValueError(f"Tamaño BDS incorrecto: {size} bytes; esperado {expected_size}")

    if expected_sha1:
        digest = hashlib.sha1()
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
        actual = digest.hexdigest()
        if actual.lower() != expected_sha1.lower():
            raise ValueError(f"SHA-1 BDS incorrecto: {actual}; esperado {expected_sha1}")

    try:
        with zipfile.ZipFile(path) as archive:
            bad_member = archive.testzip()
            if bad_member:
                raise ValueError(f"ZIP BDS corrupto en: {bad_member}")
            names = set(archive.namelist())
            if "bedrock_server" not in names:
                raise ValueError("ZIP BDS válido pero no contiene bedrock_server")
    except zipfile.BadZipFile as exc:
        raise ValueError("La descarga no es un ZIP BDS válido") from exc


def download(
    url: str,
    output: Path,
    *,
    expected_size: int | None = None,
    expected_sha1: str | None = None,
    attempts: int = 5,
    timeout: int = 45,
    sleep_seconds: float = 2.0,
) -> Path:
    validate_url(url)
    if expected_size is not None and expected_size <= 0:
        raise ValueError("expected_size debe ser positivo")
    if expected_sha1 and not SHA1_RE.fullmatch(expected_sha1):
        raise ValueError("expected_sha1 no tiene formato SHA-1")
    if attempts < 1:
        raise ValueError("attempts debe ser al menos 1")

    output.parent.mkdir(parents=True, exist_ok=True)
    part = Path(f"{output}.part")
    output.unlink(missing_ok=True)
    part.unlink(missing_ok=True)

    last_error: Exception | None = None
    for attempt in range(1, attempts + 1):
        part.unlink(missing_ok=True)
        request = urllib.request.Request(
            url,
            headers={
                "User-Agent": "Mozilla/5.0 MinecraftServer-manager/1.0",
                "Accept": "application/zip,application/octet-stream;q=0.9,*/*;q=0.5",
                "Connection": "close",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                final_url = response.geturl()
                validate_url(final_url)
                with part.open("wb") as handle:
                    while True:
                        chunk = response.read(1024 * 1024)
                        if not chunk:
                            break
                        handle.write(chunk)
                    handle.flush()
                    os.fsync(handle.fileno())
            validate_archive(part, expected_size, expected_sha1)
            os.replace(part, output)
            return output
        except (
            OSError,
            ValueError,
            urllib.error.URLError,
            urllib.error.HTTPError,
            socket.timeout,
            TimeoutError,
            IncompleteRead,
        ) as exc:
            last_error = exc
            part.unlink(missing_ok=True)
            if attempt < attempts:
                print(
                    f"[WARN] Descarga BDS intento {attempt}/{attempts} falló: {exc}. Reintentando...",
                    file=sys.stderr,
                )
                time.sleep(sleep_seconds * attempt)

    output.unlink(missing_ok=True)
    raise RuntimeError(f"No se pudo descargar un BDS íntegro después de {attempts} intentos: {last_error}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--size", type=int)
    parser.add_argument("--sha1")
    parser.add_argument("--attempts", type=int, default=5)
    parser.add_argument("--timeout", type=int, default=45)
    args = parser.parse_args()
    try:
        result = download(
            args.url,
            Path(args.output),
            expected_size=args.size,
            expected_sha1=args.sha1,
            attempts=args.attempts,
            timeout=args.timeout,
        )
    except (OSError, ValueError, RuntimeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    print(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
