<div align="center">

# ⛏️ Nexora · Minecraft Bedrock Network

### Una red Bedrock self-hosted, modular y lista para VPS Ubuntu

**Lobby + Survival vanilla + PvP + BedWars + SkyWars + panel web + CLI administrativa**

[![CI](https://github.com/Gh0stDeveloper/MinecraftServer/actions/workflows/ci.yml/badge.svg)](https://github.com/Gh0stDeveloper/MinecraftServer/actions/workflows/ci.yml)
![Minecraft Bedrock](https://img.shields.io/badge/Minecraft-Bedrock-62B47A?style=for-the-badge)
![Bash](https://img.shields.io/badge/Bash-5%2B-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white)
![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04%20%7C%2024.04-E95420?style=for-the-badge&logo=ubuntu&logoColor=white)
![Java](https://img.shields.io/badge/Java-21-ED8B00?style=for-the-badge&logo=openjdk&logoColor=white)
![PowerNukkitX](https://img.shields.io/badge/PowerNukkitX-3.0.2-7B61FF?style=for-the-badge)

[![Stars](https://img.shields.io/github/stars/Gh0stDeveloper/MinecraftServer?style=social)](https://github.com/Gh0stDeveloper/MinecraftServer/stargazers)
[![Forks](https://img.shields.io/github/forks/Gh0stDeveloper/MinecraftServer?style=social)](https://github.com/Gh0stDeveloper/MinecraftServer/forks)

[📚 Documentación](docs/README.md) · [🌐 Panel web](docs/WEB_ADMIN.md) · [☁️ Oracle Cloud](docs/ORACLE_RECOVERY.md) · [⚙️ PowerNukkitX](docs/PNX_RUNTIME.md)

</div>

---

## ✨ ¿Qué es este proyecto?

**Nexora Bedrock Network** automatiza la creación y administración de una red de servidores Minecraft Bedrock sobre una sola VPS Ubuntu.

No viene ligado a una IP, dominio o VPS concreta: el instalador detecta la red del usuario, solicita su dominio y genera la configuración persistente durante la primera instalación.

> [!IMPORTANT]
> **Survival se mantiene en Bedrock Dedicated Server oficial**, sin plugins PowerNukkitX y con cheats desactivados. PvP, BedWars y SkyWars usan PowerNukkitX de manera independiente.

### Incluye

- 🏠 **Lobby** en BDS oficial con selector de servidores.
- 🌲 **Survival vanilla** protegido para conservar la experiencia y los logros.
- ⚔️ **PvP** con NexoraPractice.
- 🛏️ **BedWars** con NexoraBedWars.
- ☁️ **SkyWars** con NexoraSkyWars.
- 🌐 **Panel web administrativo** para importar Survival.
- 🔐 **Token administrativo almacenado como SHA-256**.
- 🧱 **Firewall local administrado** para UFW o iptables/nftables.
- ♻️ **Actualización, backups y rollback** de runtimes.
- 🩺 **Doctor, validación de red y health checks** desde `mcserver`.
- 🎨 **Instalador y bootstrap visuales** con salida compacta y logs técnicos separados.

---

## 🏗️ Arquitectura

```text
                               ┌────────────────────┐
Jugador Bedrock ── UDP/19132 ─►│       LOBBY        │
                               │   BDS + Lobby BP   │
                               └─────────┬──────────┘
                                         │
                  ┌──────────────────────┼──────────────────────┐
                  │                      │                      │
                  ▼                      ▼                      ▼
        UDP/19133 Survival     UDP/19134 PvP          UDP/19135 BedWars
        BDS oficial            PowerNukkitX           PowerNukkitX
        vanilla                NexoraPractice         NexoraBedWars
                                                            │
                                                            ▼
                                                  UDP/19136 SkyWars
                                                  PowerNukkitX
                                                  NexoraSkyWars

Internet ── TCP/80,443 ──► Nginx ──► backend web local TCP/8080
```

| Instancia | Motor | Puerto | Estado esperado tras bootstrap |
|---|---|---:|---|
| 🏠 Lobby | BDS | `19132/UDP` | Online |
| 🌲 Survival | BDS | `19133/UDP` | Detenido hasta importar mundo |
| ⚔️ PvP | PowerNukkitX | `19134/UDP` | Online |
| 🛏️ BedWars | PowerNukkitX | `19135/UDP` | Online |
| ☁️ SkyWars | PowerNukkitX | `19136/UDP` | Online |
| 🌐 Web | Python + Nginx | `8080/TCP` interno | Online |

---

## 📋 Requisitos

| Requisito | Valor |
|---|---|
| Sistema | Ubuntu 22.04 / 24.04 |
| Arquitectura | AMD64 / x86_64 |
| Acceso | `sudo` o root |
| Java | 21+ |
| Minecraft | Bedrock Edition |
| Web público | TCP `80`, `443` |
| Bedrock | UDP `19132-19136` |

> [!NOTE]
> El backend web escucha en `8080/TCP` localmente. No es necesario exponer ese puerto a Internet cuando se utiliza Nginx.

---

## 🚀 Instalación rápida

```bash
curl -fsSL https://raw.githubusercontent.com/Gh0stDeveloper/MinecraftServer/main/install.sh | sudo bash
```

El asistente realiza automáticamente:

1. 🔍 comprobación de arquitectura y dependencias;
2. 🌍 detección de la IPv4 pública;
3. 🔗 solicitud y validación del dominio;
4. 📦 instalación de BDS;
5. ⚙️ instalación o compilación reproducible de PowerNukkitX;
6. 🎮 preparación de Lobby, PvP, BedWars y SkyWars;
7. 🧩 instalación de addons y plugins Nexora;
8. 🧱 configuración del firewall local;
9. 🌐 preparación del panel web;
10. 🛡️ bloqueo de Survival hasta importar el mundo real.

### Instalación no interactiva

```bash
curl -fsSL https://raw.githubusercontent.com/Gh0stDeveloper/MinecraftServer/main/install.sh | sudo bash -s -- \
  --public-ip 203.0.113.10 \
  --domain miservidor.duckdns.org
```

---

## 🦆 Dominio gratuito con DuckDNS

Si no tienes dominio, el instalador recomienda **DuckDNS** por ser sencillo para una VPS personal.

```text
miservidor.duckdns.org  →  IPv4 pública de tu VPS
```

Crea el subdominio en:

**https://www.duckdns.org/**

Si el DNS todavía no apunta a la VPS, Nexora guarda el dominio y utiliza temporalmente la IP pública.

Cuando el DNS sea correcto:

```bash
sudo mcserver network use-domain
sudo mcserver web domain TU_DOMINIO
sudo mcserver web https TU_DOMINIO TU_CORREO
```

---

## 🎨 Interfaz de terminal

```text
╭────────────────────────────────────────────────────────╮
│  NEXORA · BEDROCK NETWORK                              │
│  Recuperación y bootstrap del servidor                 │
╰────────────────────────────────────────────────────────╯

━━ Base del sistema
[✓] Verificando dependencias
[✓] Normalizando permisos
[✓] Aplicando firewall local

━━ Runtimes
[✓] BDS actualizado
[✓] PowerNukkitX compatible
[◆] Buscando snapshot oficial
[!] Snapshot no disponible; usando fallback reproducible
```

Los detalles extensos de `apt`, `curl`, Gradle y otras tareas se guardan en:

```text
/var/log/mcserver/tasks.log
```

Modo detallado:

```bash
sudo MCSERVER_VERBOSE=1 mcserver bootstrap
```

Sin colores ANSI:

```bash
sudo NO_COLOR=1 mcserver bootstrap
```

---

## ♻️ Recuperar una instalación incompleta

```bash
sudo mcserver update project
sudo mcserver bootstrap
```

Después:

```bash
sudo mcserver status
sudo mcserver plugins doctor
sudo mcserver minigames status
sudo mcserver network verify
sudo mcserver doctor
```

`bootstrap` está diseñado para ser **idempotente**: reutiliza runtimes válidos, completa piezas faltantes y no reemplaza el mundo Survival.

---

## 🌲 Survival y protección de logros

```ini
gamemode=survival
force-gamemode=false
allow-cheats=false
online-mode=true
allow-list=true
```

Nexora además garantiza que Survival:

- usa siempre BDS oficial;
- no recibe plugins PowerNukkitX;
- no recibe Behavior Packs de minijuegos;
- conserva `level.dat` durante la importación;
- permanece apagado hasta que exista un mundo real importado.

### Importar desde terminal

```bash
sudo mcserver import-survival /ruta/MiMundo.zip
```

Admite carpeta, `.zip` y `.mcworld`.

### Importar desde el panel

```bash
sudo mcserver web admin-token
```

Después, con HTTPS activo:

```text
https://TU_DOMINIO/admin.html
```

Consulta [docs/WEB_ADMIN.md](docs/WEB_ADMIN.md).

---

## 🎮 Minijuegos

### ⚔️ PvP · NexoraPractice

```text
/pvp solo
/pvp duo
/pvp squad
/pvp leave
/pvp status
/lobby
```

Arenas autogeneradas, equipos, kits, friendly-fire bloqueado, espectador, vacío y partidas `first-to-3`.

### 🛏️ BedWars · NexoraBedWars

```text
/bw solo
/bw duo
/bw squad
/bw leave
/bw status
/bw shop <blocks|sword|pickaxe|bow>
/lobby
```

Bases generadas, camas-núcleo, respawn condicionado, recursos, tienda y limpieza automática.

### ☁️ SkyWars · NexoraSkyWars

```text
/sw solo
/sw duo
/sw squad
/sw leave
/sw status
/lobby
```

Islas, centro, loot crates, puentes, equipos, espectador y eliminación definitiva.

---

## 🧰 CLI administrativa

| Acción | Comando |
|---|---|
| Estado | `mcserver status` |
| Diagnóstico | `sudo mcserver doctor` |
| Reparar/completar | `sudo mcserver bootstrap` |
| Backup | `sudo mcserver backup` |
| Reiniciar red | `sudo mcserver restart` |
| Verificar red | `sudo mcserver network verify` |
| Estado firewall | `sudo mcserver firewall status` |
| Actualizar proyecto | `sudo mcserver update project` |
| Actualizar BDS | `sudo mcserver update bds` |
| Actualizar PNX | `sudo mcserver update pnx` |
| Actualizar plugins | `sudo mcserver update plugins` |

Logs:

```bash
sudo mcserver logs lobby
sudo mcserver logs pvp
sudo mcserver logs bedwars
sudo mcserver logs skywars
```

---

## 🧱 Firewall y nube

El proyecto administra localmente:

```text
TCP 80,443
UDP 19132-19136
```

Cuando UFW está desactivado, crea una cadena `BEDROCK-NETWORK` en iptables/nftables antes de reglas `REJECT` existentes y persiste las reglas con `netfilter-persistent`.

> [!WARNING]
> Nexora **no modifica TCP/22**, por lo que la administración del acceso SSH permanece separada. Además, Oracle Cloud/AWS/Azure/etc. requieren abrir los mismos puertos en su firewall o Security List/NSG externo.

---

## ⚙️ PowerNukkitX resiliente

El updater intenta primero el snapshot oficial. Si upstream devuelve 404 o retira el asset, Nexora construye el `shadowJar` desde un commit oficial fijado y validado.

La release se valida antes de activarse y, si ya existe una build correcta del mismo commit, se reutiliza sin recompilar Gradle.

Más detalles: [docs/PNX_RUNTIME.md](docs/PNX_RUNTIME.md).

---

## ✅ GitHub Actions

CI comprueba entre otras cosas:

- Bash, Python y JavaScript;
- plugins Nexora;
- fallbacks externos fijados;
- runtime PowerNukkitX;
- aislamiento de Survival;
- importación segura `.zip` / `.mcworld`;
- permisos y recuperación de runtime;
- detección real de sockets UDP/TCP;
- permisos de Script API del addon del Lobby;
- panel web y paquete desplegable;
- que la plantilla pública no contenga IP o dominio del autor.

---

## 📚 Documentación

| Guía | Contenido |
|---|---|
| [📚 Índice](docs/README.md) | Centro de documentación |
| [🌐 Panel web](docs/WEB_ADMIN.md) | Token, HTTPS e importación de Survival |
| [☁️ Oracle Recovery](docs/ORACLE_RECOVERY.md) | Firewall y recuperación en Oracle Cloud |
| [⚙️ PNX Runtime](docs/PNX_RUNTIME.md) | Política y fallback de PowerNukkitX |

---

<div align="center">

### ⭐ Si el proyecto te resulta útil, puedes darle una estrella

**Nexora Bedrock Network** · creado para que levantar una red Bedrock propia sea reproducible y administrable.

</div>
