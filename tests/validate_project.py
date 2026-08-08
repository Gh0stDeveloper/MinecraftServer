#!/usr/bin/env python3
from __future__ import annotations
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
EXPECTED_PORTS={"lobby":"19132","survival":"19133","pvp":"19134","bedwars":"19135","skywars":"19136"}
NATIVE={"nexora-practice":("0.2.1","3.0.2"),"nexora-bedwars":("0.1.1","3.0.2"),"nexora-skywars":("0.1.1","3.0.2")}
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
    assert n.get("PUBLIC_IP","")==""; assert n.get("PUBLIC_DOMAIN","")==""; assert n.get("PUBLIC_HOST","")==""
    assert n.get("LOBBY_PORT")=="19132" and n.get("WEB_PORT")=="8080"
def validate_public_docs():
    forbidden=("minecraftnexora.duckdns.org","163.192.204.78")
    paths=[ROOT/"README.md",ROOT/"docs"/"README.md",ROOT/"docs"/"WEB_ADMIN.md",ROOT/"docs"/"ORACLE_RECOVERY.md",ROOT/"docs"/"PNX_RUNTIME.md",ROOT/"config"/"network.env"]
    for path in paths:
        text=path.read_text(encoding="utf-8")
        for value in forbidden: assert value not in text,(path,value)
def validate_engines():
    e=env(ROOT/"config"/"engines.env"); assert e.get("LOBBY_ENGINE")=="bds"; assert e.get("SURVIVAL_ENGINE")=="bds"
    for k in ("PVP_ENGINE","BEDWARS_ENGINE","SKYWARS_ENGINE"): assert e.get(k)=="pnx"
    assert e.get("PNX_EXPECTED_VERSION")=="3.0.2"; assert e.get("PNX_EXPECTED_MINECRAFT")=="26.40"; assert int(e.get("PNX_JAVA_MIN","0"))>=21
    assert e.get("PNX_SOURCE_REPO")=="https://github.com/PowerNukkitX/PowerNukkitX.git"; assert re.fullmatch(r"[0-9a-f]{40}",e.get("PNX_SOURCE_REF",""))
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
        assert item["instance"] in {"pvp","bedwars","skywars"}; assert item["minecraft"]=="26.40"
        if item["source_type"]=="git-gradle":
            assert item["source"].startswith("https://github.com/"); assert len(item["ref"])==40; assert item["redistribute"] is False
        elif item["source_type"]=="local-maven":
            assert (ROOT/item["source"]/"pom.xml").is_file(); assert (ROOT/item["source"]/"src/main/resources/plugin.yml").is_file()
            version,api=NATIVE[item["id"]]; assert item["version"]==version; assert item["api"]==api
            plugin=(ROOT/item["source"]/"src/main/resources/plugin.yml").read_text(encoding="utf-8")
            pom=(ROOT/item["source"]/"pom.xml").read_text(encoding="utf-8")
            assert f'version: "{version}"' in plugin; assert f'api: "{api}"' in plugin; assert "<version>3.0.2</version>" in pom
            assert item["artifact"].endswith(f"-{version}.jar")
        else: raise AssertionError(item["source_type"])
    assert by_id["nexora-practice"]["auto_install"] is True; assert by_id["nexora-bedwars"]["auto_install"] is True; assert by_id["nexora-skywars"]["auto_install"] is True
    assert by_id["silentbedwars"]["auto_install"] is False; assert by_id["powerskywars"]["auto_install"] is False
    assert "silentbedwars" in by_id["nexora-bedwars"].get("conflicts",[]) and "nexora-bedwars" in by_id["silentbedwars"].get("conflicts",[])
    assert "powerskywars" in by_id["nexora-skywars"].get("conflicts",[]) and "nexora-skywars" in by_id["powerskywars"].get("conflicts",[])
    assert not list(ROOT.glob("instances/*/plugins/*.jar"))
def validate_survival_isolation():
    s=ROOT/"instances"/"survival"
    for p in [s/"behavior_packs",s/"plugins",s/"pnx.yml",s/"world_behavior_packs.json"]: assert not p.exists()
def validate_required_files():
    required=["mcserver","scripts/ui.sh","scripts/socket-check.sh","scripts/launch-instance.sh","scripts/update-pnx.sh","scripts/pnx-jar-validator.py","scripts/bds-downloader.py","scripts/engine-manager.sh","scripts/plugin-manager.sh","scripts/minigame-manager.sh","scripts/network-manager.sh","scripts/install-addon.sh","scripts/normalize-permissions.sh","scripts/bootstrap-runtime.sh","scripts/firewall-manager.sh","tests/test_pnx_source_pin.py","tests/test_pnx_jar_validator.py","tests/test_socket_check.sh","tests/test_lobby_addon_permissions.sh","docs/README.md","systemd/bedrock@.service","pnx-plugins/nexora-practice/src/main/resources/plugin.yml","pnx-plugins/nexora-bedwars/src/main/resources/plugin.yml","pnx-plugins/nexora-skywars/src/main/resources/plugin.yml"]
    for rel in required: assert (ROOT/rel).is_file(),rel
def validate_empty_service_state():
    with tempfile.TemporaryDirectory() as td:
        bindir=Path(td); systemctl=bindir/"systemctl"
        systemctl.write_text("#!/usr/bin/env bash\nif [[ ${1:-} == is-active ]]; then exit 3; fi\nexit 0\n",encoding="utf-8"); systemctl.chmod(0o755)
        envp=os.environ.copy(); envp["PATH"]=f"{bindir}:{envp['PATH']}"; envp["NO_COLOR"]="1"
        command=f'''set -euo pipefail\nsource "{ROOT}/scripts/lib.sh"\nout="$(active_instances)"\n[[ -z "$out" ]]\nstart_instance_list "$out"\nnone="$(instances_by_engine impossible)"\n[[ -z "$none" ]]\nstart_engine impossible\nstop_engine impossible\n'''
        subprocess.run(["bash","-c",command],check=True,env=envp,cwd=ROOT)
def validate_bds_downloader(): subprocess.run([os.environ.get("PYTHON","python3"),str(ROOT/"tests"/"test_bds_downloader.py")],check=True,cwd=ROOT)
def validate_pnx_source_pin(): subprocess.run([os.environ.get("PYTHON","python3"),str(ROOT/"tests"/"test_pnx_source_pin.py")],check=True,cwd=ROOT)
def validate_pnx_jar_validator(): subprocess.run([os.environ.get("PYTHON","python3"),str(ROOT/"tests"/"test_pnx_jar_validator.py")],check=True,cwd=ROOT)
def validate_runtime_regressions():
    subprocess.run(["bash",str(ROOT/"tests"/"test_socket_check.sh")],check=True,cwd=ROOT)
    subprocess.run(["sudo","bash",str(ROOT/"tests"/"test_lobby_addon_permissions.sh")],check=True,cwd=ROOT)
def main():
    validate_instances(); validate_deployment(); validate_public_docs(); validate_engines(); validate_json(); validate_manifests(); validate_plugins(); validate_survival_isolation(); validate_required_files(); validate_empty_service_state(); validate_bds_downloader(); validate_pnx_source_pin(); validate_pnx_jar_validator(); validate_runtime_regressions(); print("All native-minigame BedrockNetwork checks passed.")
if __name__=="__main__": main()
