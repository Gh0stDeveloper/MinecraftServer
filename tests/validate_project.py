#!/usr/bin/env python3
"""CI checks for the BedrockNetwork repository. Standard library only."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

EXPECTED_PORTS = {
    "lobby": "19132",
    "survival": "19133",
    "pvp": "19134",
    "bedwars": "19135",
    "skywars": "19136",
}


def read_properties(path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        data[key.strip()] = value.strip()
    return data


def validate_instances() -> None:
    for instance, port in EXPECTED_PORTS.items():
        props_path = ROOT / "instances" / instance / "server.properties"
        assert props_path.is_file(), f"Missing {props_path}"
        props = read_properties(props_path)
        assert props.get("server-port") == port, (instance, props.get("server-port"), port)
        assert props.get("online-mode") == "true", f"{instance}: online-mode must be true"

    survival = read_properties(ROOT / "instances" / "survival" / "server.properties")
    required = {
        "gamemode": "survival",
        "force-gamemode": "false",
        "allow-cheats": "false",
        "online-mode": "true",
        "allow-list": "true",
        "level-name": "SurvivalWorld",
    }
    for key, expected in required.items():
        assert survival.get(key) == expected, f"survival: {key}={survival.get(key)!r}; expected {expected!r}"


def validate_json_files() -> None:
    for path in ROOT.rglob("*.json"):
        with path.open(encoding="utf-8") as handle:
            json.load(handle)


def validate_manifests() -> None:
    uuids: set[str] = set()
    manifests = list((ROOT / "addons").glob("*/manifest.json"))
    assert manifests, "No addon manifests found"

    for path in manifests:
        data = json.loads(path.read_text(encoding="utf-8"))
        assert data.get("format_version") == 2, f"{path}: unsupported format_version"
        header = data["header"]
        assert header["min_engine_version"] >= [1, 26, 40], f"{path}: min engine below 1.26.40"
        for value in [header["uuid"], *[m["uuid"] for m in data.get("modules", [])]]:
            assert value not in uuids, f"Duplicate UUID {value}"
            uuids.add(value)


def validate_survival_isolation() -> None:
    survival_dir = ROOT / "instances" / "survival"
    forbidden = [survival_dir / "behavior_packs", survival_dir / "world_behavior_packs.json"]
    for path in forbidden:
        assert not path.exists(), f"Survival must not ship network addons: {path}"


def main() -> None:
    validate_instances()
    validate_json_files()
    validate_manifests()
    validate_survival_isolation()
    print("All BedrockNetwork repository checks passed.")


if __name__ == "__main__":
    main()
