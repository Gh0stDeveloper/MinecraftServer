#!/usr/bin/env python3
from __future__ import annotations
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESOLVER = ROOT / "scripts" / "bds-resolver.py"
FIXTURES = ROOT / "tests" / "fixtures"


def run(*extra: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(RESOLVER), "--versions-file", str(FIXTURES / "versions.json"), "--detail-file", str(FIXTURES / "detail.json"), *extra],
        check=False,
        text=True,
        capture_output=True,
    )


def main() -> None:
    result = run()
    assert result.returncode == 0, result.stderr
    data = json.loads(result.stdout)
    assert data["version"] == "1.26.40.1"
    assert data["url"].startswith("https://www.minecraft.net/")

    version = run("--field", "version")
    assert version.returncode == 0
    assert version.stdout.strip() == "1.26.40.1"

    with tempfile.TemporaryDirectory() as tmp:
        bad = Path(tmp) / "bad.json"
        bad.write_text('{"download_url":"https://example.com/bin-linux/bedrock-server-1.26.40.1.zip"}', encoding="utf-8")
        rejected = subprocess.run(
            [sys.executable, str(RESOLVER), "--versions-file", str(FIXTURES / "versions.json"), "--detail-file", str(bad)],
            check=False,
            text=True,
            capture_output=True,
        )
        assert rejected.returncode != 0
        assert "no oficial" in rejected.stderr

    print("BDS resolver tests passed.")


if __name__ == "__main__":
    main()
