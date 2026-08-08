#!/usr/bin/env python3
from __future__ import annotations
import ipaddress
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
EXPECTED_PORTS={"lobby":"19132","survival":"19133","pvp":"19134","bedwars":"19135","skywars":"19136"}
def props(path:Path)->dict[str,str]:
    out={}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line=raw.strip()
        if not line or line.startswith("#") or "=" not in line: continue
        k,v=line.split("=",1); out[k.strip()]=v.strip()
    return out
def env(path:Path)->dict[str,str]: return {k:v.strip('"').strip("'") for k,v in props(path).items()}
def validate_instances():
    for instance,port in EXPECTED_PORTS.items():
        d=props(ROOT/"instances"/instance/"server.properties"); assert d.get("server-port")==port; assert d.get("online-mode")=="true"
    s=props(ROOT/"instances"/"survival"/"server.properties")
    for k,v in {"gamemode":"survival","force-gamemode":"false","allow-cheats":"false","online-mode":"true","allow-list":"true","level-name":"SurvivalWorld"}.items(): assert s.get(k)==v
    assert int(props(ROOT/"instances"/"skywars"/"server.properties").get("max-players","0"))>=16
def validate_deployment():
    n=env(ROOT/"config"/"network.env")
    public_ip=n.get("PUBLIC_IP","")
    assert ipaddress.ip_address(public_ip).version==4
    assert n.get("PUBLIC_DOMAIN")=="minecraftnexora.duckdns.org"
    assert n.get("PUBLIC_HOST") in {public_ip,n.get("PUBLIC_DOMAIN")}
def validate_engines():
    e=env(ROOT/"config"/"engines.env"); assert e.get("LOBBY_ENGINE")=="bds"; assert e.get("SURVIVAL_ENGINE")=="bds"
    for k in ("PVP_ENGINE","BEDWARS_ENGINE","SKYWARS_ENGINE"): assert e.get(k)=="pnx"
    assert e.get("PNX_EXPECTED_MINECRAFT")=="26.40"; assert int(e.get("PNX_JAVA_MIN","0"))>=21
def validate_json():
    for p in ROOT.rglob("*.json"):
        if any(part in {"target","build"} for part in p.parts): continue
        json.loads(p.read_text(encoding="utf-8"))
def validate_manifests():
    uuids=set(); manifests=list((ROOT/"addons").glob("*/manifest.json")); assert manifests
    for p in manifests:
        d=json.loads(p.read_text()); h=d["header"]; assert d.get("format_version")==2; assert h["min_engine_version"] >= [1,26,40]
        for u in [h["uuid"],*[m["uuid"] for m in d.get("modules",[])]]: assert u not in uuids; uuids.add(u)
def validate_plugins():
    by_id={p["id"]:p for p in json.loads((ROOT/"config"/"plugins.json").read_text())["plugins"]}
    required={"nexora-practice","nexora-bedwars","silentbedwars","nexora-skywars","powerskywars"}; assert required <= set(by_id)
    for item in by_id.values():
        assert item["instance"] in {"pvp","bedwars","skywars"}; assert item["minecraft"]=="26.40"; assert item["api"]=="2.0.0"
        if item["source_type"]=="git-gradle": assert item["source"].startswith("https://github.com/"); assert len(item["ref"])==40; assert item["redistribute"] is False
        elif item["source_type"]=="local-maven": assert (ROOT/item["source"]/"pom.xml").is_file(); assert (ROOT/item["source"]/"src/main/resources/plugin.yml").is_file()
        else: raise AssertionError(item["source_type"])
    assert by_id["nexora-practice"]["auto_install"] is True and by_id["nexora-practice"]["version"]=="0.2.0"
    assert by_id["nexora-bedwars"]["auto_install"] is True and by_id["nexora-bedwars"]["version"]=="0.1.0"
    assert by_id["nexora-skywars"]["auto_install"] is True and by_id["nexora-skywars"]["version"]=="0.1.0"
    assert by_id["silentbedwars"]["auto_install"] is False; assert by_id["powerskywars"]["auto_install"] is False
    assert "silentbedwars" in by_id["nexora-bedwars"].get("conflicts",[]) and "nexora-bedwars" in by_id["silentbedwars"].get("conflicts",[])
    assert "powerskywars" in by_id["nexora-skywars"].get("conflicts",[]) and "nexora-skywars" in by_id["powerskywars"].get("conflicts",[])
    assert not list(ROOT.glob("instances/*/plugins/*.jar"))
def validate_survival_isolation():
    s=ROOT/"instances"/"survival"
    for p in [s/"behavior_packs",s/"plugins",s/"pnx.yml",s/"world_behavior_packs.json"]: assert not p.exists()
def validate_required_files():
    required=["mcserver","scripts/launch-instance.sh","scripts/update-pnx.sh","scripts/engine-manager.sh","scripts/plugin-manager.sh","scripts/minigame-manager.sh","scripts/network-manager.sh","scripts/normalize-permissions.sh","systemd/bedrock@.service","pnx-plugins/nexora-practice/src/main/resources/plugin.yml","pnx-plugins/nexora-bedwars/src/main/resources/plugin.yml","pnx-plugins/nexora-skywars/src/main/resources/plugin.yml"]
    for rel in required: assert (ROOT/rel).is_file(),rel
def main(): validate_instances(); validate_deployment(); validate_engines(); validate_json(); validate_manifests(); validate_plugins(); validate_survival_isolation(); validate_required_files(); print("All native-minigame BedrockNetwork checks passed.")
if __name__=="__main__": main()
