#!/usr/bin/env python3
"""Resolve current Minecraft Bedrock Dedicated Server Linux builds.

The resolver tries minecraft.net first. If the redesigned page does not expose a
machine-readable archive URL, it falls back to Bedrock-OSS/BDS-Versions only as
version metadata. The returned ZIP URL is always required to use an approved
official Minecraft host.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path
from urllib.parse import urlparse

VERSIONS_URL = os.environ.get(
    "BDS_VERSIONS_URL",
    "https://raw.githubusercontent.com/Bedrock-OSS/BDS-Versions/main/versions.json",
)
OFFICIAL_PAGE = os.environ.get(
    "BDS_OFFICIAL_PAGE", "https://www.minecraft.net/en-us/download/server/bedrock"
)
DETAIL_BASE = os.environ.get(
    "BDS_DETAIL_BASE",
    "https://raw.githubusercontent.com/Bedrock-OSS/BDS-Versions/main/linux",
)
ALLOWED_HOSTS = {"www.minecraft.net", "minecraft.net", "minecraft.azureedge.net"}
VERSION_RE = re.compile(r"^\d+\.\d+\.\d+\.\d+$")


def load_json_url(url: str, timeout: int = 20) -> dict:
    request = urllib.request.Request(url, headers={"User-Agent": "MinecraftServer-manager/1.0"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.load(response)


def load_json(path: str | None, url: str) -> dict:
    if path:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    return load_json_url(url)


def validate_version(version: str) -> str:
    if not VERSION_RE.fullmatch(version):
        raise ValueError(f"Versión BDS no válida: {version!r}")
    return version


def validate_official_url(url: str) -> str:
    parsed = urlparse(url)
    if parsed.scheme != "https" or parsed.hostname not in ALLOWED_HOSTS:
        raise ValueError(f"URL BDS no oficial o no permitida: {url}")
    if "bin-linux" not in parsed.path or not parsed.path.endswith(".zip"):
        raise ValueError(f"La URL no parece un ZIP Linux de BDS: {url}")
    return url


def discover_official_page(url: str = OFFICIAL_PAGE) -> dict | None:
    request = urllib.request.Request(
        url, headers={"User-Agent": "Mozilla/5.0 MinecraftServer-manager/1.0"}
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        html = response.read().decode("utf-8", errors="replace")
    html = html.replace("\\/", "/")
    matches = re.findall(
        r"https://(?:www\.)?minecraft\.net/[^\"'<> ]*bin-linux/bedrock-server-(\d+\.\d+\.\d+\.\d+)\.zip",
        html,
    )
    if not matches:
        matches = re.findall(
            r"https://minecraft\.azureedge\.net/bin-linux/bedrock-server-(\d+\.\d+\.\d+\.\d+)\.zip",
            html,
        )
    if not matches:
        return None

    def key(value: str) -> tuple[int, ...]:
        return tuple(int(part) for part in value.split("."))

    version = max(matches, key=key)
    download_url = (
        "https://www.minecraft.net/bedrockdedicatedserver/bin-linux/"
        f"bedrock-server-{version}.zip"
    )
    return {
        "version": version,
        "url": validate_official_url(download_url),
        "metadata_source": "minecraft.net",
        "archive_source": "www.minecraft.net",
    }


def resolve(args: argparse.Namespace) -> dict:
    version = args.version
    if (not version or version == "latest") and not args.versions_file and not args.detail_file:
        try:
            official = discover_official_page()
            if official:
                return official
        except (OSError, urllib.error.URLError):
            pass

    versions = load_json(args.versions_file, args.versions_url)
    if not version or version == "latest":
        version = versions.get("linux", {}).get("stable")
    if not version:
        raise ValueError("No se pudo determinar la versión estable de Linux")
    validate_version(version)

    detail_url = f"{args.detail_base.rstrip('/')}/{version}.json"
    detail = load_json(args.detail_file, detail_url)
    download_url = detail.get("download_url") or detail.get("url") or detail.get("downloadUrl")
    if not download_url:
        raise ValueError("El metadata de la versión no contiene download_url")
    validate_official_url(download_url)

    return {
        "version": version,
        "url": download_url,
        "metadata_source": "Bedrock-OSS/BDS-Versions",
        "archive_source": urlparse(download_url).hostname,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", default="latest")
    parser.add_argument("--versions-url", default=VERSIONS_URL)
    parser.add_argument("--detail-base", default=DETAIL_BASE)
    parser.add_argument("--versions-file")
    parser.add_argument("--detail-file")
    parser.add_argument("--field", choices=["version", "url"])
    args = parser.parse_args()
    try:
        result = resolve(args)
    except (OSError, ValueError, KeyError, json.JSONDecodeError, urllib.error.URLError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    if args.field:
        print(result[args.field])
    else:
        print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
