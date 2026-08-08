#!/usr/bin/env python3
from __future__ import annotations
import hashlib, hmac, json, mimetypes, os, socket, struct, time, uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlparse

BASE = Path(os.environ.get("BEDROCK_BASE", "/opt/bedrock-network"))
STATIC = Path(__file__).resolve().parent / "static"
HOST = os.environ.get("WEB_HOST", "0.0.0.0")
PORT = int(os.environ.get("WEB_PORT", "8080"))
MAX_UPLOAD_MB = max(1, int(os.environ.get("WEB_MAX_UPLOAD_MB", "4096")))
MAX_UPLOAD_BYTES = MAX_UPLOAD_MB * 1024 * 1024
UPLOAD_DIR = BASE / "uploads"
REQUEST_DIR = UPLOAD_DIR / "requests"
RESULT_DIR = BASE / "state" / "web-imports"
TOKEN_HASH_FILE = BASE / "config" / "web-admin.token.sha256"
INSTANCES = ("lobby", "survival", "pvp", "bedwars", "skywars")
MAGIC = bytes.fromhex("00ffff00fefefefefdfdfdfd12345678")


def parse_env(path: Path) -> dict[str, str]:
    out = {}
    if not path.exists():
        return out
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def ping_bedrock(port: int, timeout: float = .35) -> dict:
    sent = int(time.time() * 1000)
    packet = b"\x01" + struct.pack(">Q", sent) + MAGIC + struct.pack(">Q", 0x4E45584F52414244)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(timeout)
    try:
        sock.sendto(packet, ("127.0.0.1", port))
        data, _ = sock.recvfrom(4096)
    except OSError:
        return {"online": False, "players": 0, "max_players": None, "version": None, "motd": None}
    finally:
        sock.close()
    if len(data) < 35 or data[0] != 0x1C:
        return {"online": True, "players": None, "max_players": None, "version": None, "motd": None}
    try:
        n = struct.unpack(">H", data[33:35])[0]
        parts = data[35:35+n].decode("utf-8", errors="replace").split(";")
        return {"online": True, "motd": parts[1] if len(parts)>1 else None, "version": parts[3] if len(parts)>3 else None, "players": int(parts[4]) if len(parts)>4 and parts[4].isdigit() else None, "max_players": int(parts[5]) if len(parts)>5 and parts[5].isdigit() else None}
    except (ValueError, struct.error):
        return {"online": True, "players": None, "max_players": None, "version": None, "motd": None}


def read_state(name: str):
    path = BASE / "state" / name
    return path.read_text(encoding="utf-8").strip() if path.exists() else None


def status_payload() -> dict:
    env = parse_env(BASE / "config" / "network.env")
    engines = parse_env(BASE / "config" / "engines.env")
    defaults = {"lobby":"bds","survival":"bds","pvp":"pnx","bedwars":"pnx","skywars":"pnx"}
    servers=[]; total=0
    for instance in INSTANCES:
        props=parse_env(BASE/"instances"/instance/"server.properties")
        port=int(props.get("server-port",env.get(f"{instance.upper()}_PORT","19132")))
        ping=ping_bedrock(port)
        if isinstance(ping.get("players"),int): total+=ping["players"]
        engine=engines.get(f"{instance.upper()}_ENGINE",defaults[instance]).lower()
        servers.append({"id":instance,"name":props.get("server-name",instance.title()),"port":port,"engine":engine,**ping})
    return {"network":env.get("SERVER_NAME","Bedrock Network"),"host":env.get("PUBLIC_HOST","127.0.0.1"),"lobby_port":int(env.get("LOBBY_PORT","19132")),"bds_version":read_state("bds-version"),"pnx_version":read_state("pnx-version"),"players":total,"servers":servers,"generated_at":int(time.time())}


def token_configured() -> bool:
    return TOKEN_HASH_FILE.is_file() and bool(TOKEN_HASH_FILE.read_text(encoding="utf-8",errors="ignore").strip())


def valid_admin_token(token: str | None) -> bool:
    if not token or len(token)>256 or not token_configured(): return False
    expected=TOKEN_HASH_FILE.read_text(encoding="utf-8",errors="ignore").strip().lower()
    actual=hashlib.sha256(token.encode("utf-8")).hexdigest()
    return hmac.compare_digest(actual,expected)


def atomic_json(path:Path,payload:dict)->None:
    path.parent.mkdir(parents=True,exist_ok=True)
    tmp=path.with_suffix(path.suffix+".tmp")
    tmp.write_text(json.dumps(payload,ensure_ascii=False,separators=(",",":")),encoding="utf-8")
    os.replace(tmp,path)


class Handler(BaseHTTPRequestHandler):
    server_version="BedrockNetworkWeb/1.2"
    def log_message(self,fmt,*args): print(f"[web] {self.address_string()} {fmt % args}")
    def common_headers(self):
        self.send_header("X-Content-Type-Options","nosniff"); self.send_header("X-Frame-Options","DENY"); self.send_header("Referrer-Policy","no-referrer"); self.send_header("Permissions-Policy","camera=(), microphone=(), geolocation=()"); self.send_header("Cache-Control","no-store"); self.send_header("Content-Security-Policy","default-src 'self'; style-src 'self'; script-src 'self'; connect-src 'self'; img-src 'self' data:; base-uri 'none'; frame-ancestors 'none'")
    def json_response(self,payload,status=200):
        data=json.dumps(payload,ensure_ascii=False).encode(); self.send_response(status); self.common_headers(); self.send_header("Content-Type","application/json; charset=utf-8"); self.send_header("Content-Length",str(len(data))); self.end_headers(); self.wfile.write(data)
    def secure_admin_request(self)->bool:
        forwarded=self.headers.get("X-Forwarded-Proto","").lower().strip()
        if forwarded: return forwarded=="https"
        return self.client_address[0] in {"127.0.0.1","::1"}
    def admin_ok(self)->bool:
        if not self.secure_admin_request():
            self.json_response({"ok":False,"error":"El panel administrativo requiere HTTPS."},403); return False
        if valid_admin_token(self.headers.get("X-Admin-Token")): return True
        self.json_response({"ok":False,"error":"Token administrativo inválido o no configurado."},401); return False
    def do_GET(self):
        parsed=urlparse(self.path)
        if parsed.path=="/api/status": self.json_response(status_payload()); return
        if parsed.path=="/healthz": self.json_response({"ok":True}); return
        if parsed.path=="/api/admin/check":
            if not self.admin_ok(): return
            self.json_response({"ok":True,"max_upload_mb":MAX_UPLOAD_MB}); return
        if parsed.path=="/api/admin/survival/import-status":
            if not self.admin_ok(): return
            ident=parse_qs(parsed.query).get("id",[""])[0]
            if len(ident)!=32 or any(c not in "0123456789abcdef" for c in ident): self.json_response({"ok":False,"error":"ID inválido."},400); return
            path=RESULT_DIR/f"{ident}.json"
            if not path.is_file(): self.json_response({"ok":True,"id":ident,"state":"queued"}); return
            try: payload=json.loads(path.read_text(encoding="utf-8"))
            except (OSError,json.JSONDecodeError): payload={"ok":False,"id":ident,"state":"unknown","error":"Estado no disponible."}
            self.json_response(payload); return
        rel=unquote(parsed.path.lstrip("/")) or "index.html"; target=(STATIC/rel).resolve()
        try: target.relative_to(STATIC.resolve())
        except ValueError: self.send_error(403); return
        if not target.is_file(): target=STATIC/"index.html"
        data=target.read_bytes(); ctype=mimetypes.guess_type(target.name)[0] or "application/octet-stream"; self.send_response(200); self.common_headers(); self.send_header("Content-Type",ctype); self.send_header("Content-Length",str(len(data))); self.end_headers(); self.wfile.write(data)
    def do_POST(self):
        parsed=urlparse(self.path)
        if parsed.path!="/api/admin/survival/upload": self.json_response({"ok":False,"error":"Endpoint no encontrado."},404); return
        if not self.admin_ok(): return
        raw_length=self.headers.get("Content-Length","")
        try: length=int(raw_length)
        except ValueError: length=0
        if length<=0: self.json_response({"ok":False,"error":"Archivo vacío o Content-Length inválido."},411); return
        if length>MAX_UPLOAD_BYTES: self.json_response({"ok":False,"error":f"El archivo supera el límite de {MAX_UPLOAD_MB} MB."},413); return
        original=Path(self.headers.get("X-Filename","survival.zip")).name; suffix=Path(original).suffix.lower()
        if suffix not in {".zip",".mcworld"}: self.json_response({"ok":False,"error":"Solo se admiten archivos .zip o .mcworld."},415); return
        ident=uuid.uuid4().hex; UPLOAD_DIR.mkdir(parents=True,exist_ok=True); REQUEST_DIR.mkdir(parents=True,exist_ok=True); RESULT_DIR.mkdir(parents=True,exist_ok=True)
        final_path=UPLOAD_DIR/f"{ident}{suffix}"; part_path=UPLOAD_DIR/f".{ident}{suffix}.part"; digest=hashlib.sha256(); remaining=length
        try:
            with part_path.open("wb") as fh:
                while remaining:
                    chunk=self.rfile.read(min(1024*1024,remaining))
                    if not chunk: raise ConnectionError("La conexión terminó antes de completar la subida.")
                    fh.write(chunk); digest.update(chunk); remaining-=len(chunk)
                fh.flush(); os.fsync(fh.fileno())
            os.replace(part_path,final_path); now=int(time.time())
            atomic_json(RESULT_DIR/f"{ident}.json",{"ok":True,"id":ident,"state":"queued","filename":original,"size":length,"created_at":now})
            atomic_json(REQUEST_DIR/f"{ident}.json",{"id":ident,"stored_name":final_path.name,"filename":original,"size":length,"sha256":digest.hexdigest(),"created_at":now})
        except (OSError,ConnectionError) as exc:
            part_path.unlink(missing_ok=True); final_path.unlink(missing_ok=True); self.json_response({"ok":False,"error":f"No se pudo guardar la subida: {exc}"},500); return
        self.json_response({"ok":True,"id":ident,"state":"queued","filename":original,"size":length},202)


def main():
    httpd=ThreadingHTTPServer((HOST,PORT),Handler); print(f"Bedrock Network web escuchando en http://{HOST}:{PORT}"); httpd.serve_forever()
if __name__=="__main__": main()
