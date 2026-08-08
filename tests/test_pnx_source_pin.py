#!/usr/bin/env python3
from __future__ import annotations

import re
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def parse_env(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        out[key.strip()] = value.strip().strip('"').strip("'")
    return out


def fetch(url: str) -> str:
    last: Exception | None = None
    for attempt in range(3):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "MinecraftServer-CI/1.0"})
            with urllib.request.urlopen(req, timeout=20) as response:
                return response.read().decode("utf-8", errors="replace")
        except Exception as exc:  # network diagnostics are re-raised after retries
            last = exc
            time.sleep(attempt + 1)
    assert last is not None
    raise last


def main() -> None:
    cfg = parse_env(ROOT / "config" / "engines.env")
    repo = cfg["PNX_SOURCE_REPO"]
    ref = cfg["PNX_SOURCE_REF"]
    expected_version = cfg["PNX_EXPECTED_VERSION"]
    expected_mc = cfg["PNX_EXPECTED_MINECRAFT"]

    assert repo == "https://github.com/PowerNukkitX/PowerNukkitX.git"
    assert re.fullmatch(r"[0-9a-f]{40}", ref)

    base = f"https://raw.githubusercontent.com/PowerNukkitX/PowerNukkitX/{ref}"
    readme = fetch(f"{base}/README.md")
    build = fetch(f"{base}/build.gradle.kts")

    version = re.search(r"badge/version-([0-9.]+)-blue", readme)
    minecraft = re.search(r"minecraft-v([^% ]+)%20\(Bedrock\)", readme)
    assert version and version.group(1) == expected_version
    assert minecraft and minecraft.group(1) == expected_mc
    assert 'tasks.named<ShadowJar>("shadowJar")' in build
    assert 'archiveFileName.set("${project.description}.jar")' in build
    assert 'description = "powernukkitx"' in build
    assert "JavaVersion.VERSION_21" in build

    print(f"Pinned PowerNukkitX source verified: {expected_version} / Bedrock {expected_mc} / {ref[:12]}")


if __name__ == "__main__":
    main()
