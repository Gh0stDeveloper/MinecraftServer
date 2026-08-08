#!/usr/bin/env python3
from __future__ import annotations

import sys
import zipfile
from pathlib import Path

EXPECTED_MAIN_CLASS = "org.powernukkitx.JarStart"
EXPECTED_CLASS_ENTRY = "org/powernukkitx/JarStart.class"


def validate(path: Path) -> tuple[bool, str]:
    if not path.is_file() or path.stat().st_size <= 0:
        return False, "archivo inexistente o vacío"

    try:
        with zipfile.ZipFile(path) as jar:
            names = set(jar.namelist())
            if EXPECTED_CLASS_ENTRY not in names:
                return False, f"falta {EXPECTED_CLASS_ENTRY}"
            if "META-INF/MANIFEST.MF" not in names:
                return False, "falta META-INF/MANIFEST.MF"

            manifest = jar.read("META-INF/MANIFEST.MF").decode("utf-8", errors="replace")
            normalized = manifest.replace("\r\n", "\n").replace("\r", "\n")
            attrs: dict[str, str] = {}
            current_key: str | None = None
            for raw in normalized.splitlines():
                if raw.startswith(" ") and current_key:
                    attrs[current_key] = attrs.get(current_key, "") + raw[1:]
                    continue
                if ":" not in raw:
                    current_key = None
                    continue
                key, value = raw.split(":", 1)
                current_key = key.strip()
                attrs[current_key] = value.strip()

            main_class = attrs.get("Main-Class", "")
            if main_class != EXPECTED_MAIN_CLASS:
                return False, f"Main-Class={main_class or 'ausente'}; esperado {EXPECTED_MAIN_CLASS}"
    except (OSError, zipfile.BadZipFile, RuntimeError) as exc:
        return False, f"JAR/ZIP inválido: {exc}"

    return True, "ok"


def main() -> int:
    if len(sys.argv) != 2:
        print(f"Uso: {Path(sys.argv[0]).name} ARCHIVO.jar", file=sys.stderr)
        return 2
    ok, detail = validate(Path(sys.argv[1]))
    if not ok:
        print(detail, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
