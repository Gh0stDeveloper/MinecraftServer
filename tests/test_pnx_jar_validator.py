#!/usr/bin/env python3
from __future__ import annotations

import subprocess
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VALIDATOR = ROOT / "scripts" / "pnx-jar-validator.py"
MAIN_CLASS = "org.powernukkitx.JarStart"
CLASS_ENTRY = "org/powernukkitx/JarStart.class"


def run(path: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["python3", str(VALIDATOR), str(path)],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def make_jar(path: Path, *, main_class: str = MAIN_CLASS, include_class: bool = True) -> None:
    manifest = f"Manifest-Version: 1.0\r\nMain-Class: {main_class}\r\n\r\n"
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED, allowZip64=True) as jar:
        jar.writestr("META-INF/MANIFEST.MF", manifest)
        if include_class:
            jar.writestr(CLASS_ENTRY, b"placeholder-bytecode")
        for index in range(3000):
            jar.writestr(f"deps/example/{index:04d}.class", b"x")


def main() -> None:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        good = root / "good.jar"
        make_jar(good)
        assert run(good).returncode == 0

        missing = root / "missing-class.jar"
        make_jar(missing, include_class=False)
        assert run(missing).returncode != 0

        wrong_main = root / "wrong-main.jar"
        make_jar(wrong_main, main_class="example.Main")
        assert run(wrong_main).returncode != 0

        broken = root / "broken.jar"
        broken.write_bytes(b"not-a-zip")
        assert run(broken).returncode != 0

    print("PowerNukkitX JAR validator regression passed.")


if __name__ == "__main__":
    main()
