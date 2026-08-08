# Nexora · Minecraft Bedrock Network

Servidor/red híbrida para Minecraft Bedrock con **Lobby**, **Survival vanilla**, **PvP**, **BedWars**, **SkyWars**, panel web y administración desde una sola CLI.

El proyecto está preparado para una VPS Ubuntu AMD64/x86_64 y no incluye una IP o dominio del autor: cada instalación configura sus propios datos durante el asistente inicial.

## Arquitectura

```text
Jugador Bedrock
      |
      | UDP 19132
      v
+-------------+
|    LOBBY    | BDS oficial + addon del hub
+------+------+ 
       |
       +--> Survival :19133  BDS oficial, sin plugins, cheats=false
       +--> PvP      :19134  PowerNukkitX + NexoraPractice
       +--> BedWars  :19135  PowerNukkitX + NexoraBedWars
       +--> SkyWars  :19136  PowerNukkitX + NexoraSkyWars
```

Lobby y Survival permanecen en Bedrock Dedicated Server oficial. Los minijuegos usan PowerNukkitX y plugins Nexora administrados por el proyecto.

## Requisitos

- Ubuntu 22.04 o 24.04.
- CPU AMD64/x86_64.
- Acceso `sudo`/root.
- Java 21 para PowerNukkitX.
- Puertos externos:

```text
TCP 80,443
UDP 19132-19136
```

TCP/8080 es interno para el backend web y no necesita publicarse si se utiliza Nginx.

## Instalación rápida

```bash
curl -fsSL https://raw.githubusercontent.com/Gh0stDeveloper/MinecraftServer/main/install.sh | sudo bash
```

La primera instalación abre un asistente en terminal que:

1. comprueba arquitectura y dependencias;
2. detecta la IPv4 pública de la VPS;
3. pide el dominio público;
4. comprueba si el DNS ya apunta a la VPS;
5. instala BDS y PowerNukkitX;
6. prepara Lobby, PvP, BedWars y SkyWars;
7. configura firewall local y panel web;
8. mantiene Survival detenido hasta importar el mundo real.

### Instalación no interactiva

```bash
curl -fsSL https://raw.githubusercontent.com/Gh0stDeveloper/MinecraftServer/main/install.sh | sudo bash -s -- \
  --public-ip 203.0.113.10 \
  --domain miservidor.duckdns.org
```

## Dominio gratis con DuckDNS

Si no tienes dominio, puedes crear un subdominio gratuito en:

```text
https://www.duckdns.org/
```

Ejemplo:

```text
miservidor.duckdns.org -> IP_PUBLICA_DE_TU_VPS
```

El instalador pide el dominio. Si todavía no resuelve a la IP correcta, guarda el dominio pero utiliza temporalmente la IPv4 para no bloquear la instalación.

Cuando el DNS ya sea correcto:

```bash
sudo mcserver network use-domain
```

Después puedes activar Nginx/HTTPS:

```bash
sudo mcserver web domain TU_DOMINIO
sudo mcserver web https TU_DOMINIO TU_CORREO
```

## Interfaz de terminal

El instalador y el bootstrap usan una salida compacta con secciones y estados:

```text
╭────────────────────────────────────────────────────────╮
│  NEXORA · BEDROCK NETWORK                              │
│  Instalación guiada · BDS + PowerNukkitX               │
╰────────────────────────────────────────────────────────╯

━━ Runtimes
[✓] Bedrock Dedicated Server actualizado
[✓] PowerNukkitX 3.0.2 compatible con Bedrock 26.40
[◆] Buscando snapshot oficial de PowerNukkitX
[!] Snapshot oficial no disponible; compilando desde el commit fijado.
[✓] Descargando/preparando Gradle
[✓] Compilando release de PowerNukkitX 3.0.2
```

Los comandos ruidosos (`apt`, `curl`, Gradle, etc.) se compactan y sus detalles se guardan en:

```text
/var/log/mcserver/tasks.log
```

Para mostrar la salida técnica completa:

```bash
sudo MCSERVER_VERBOSE=1 mcserver bootstrap
```

Para desactivar colores ANSI:

```bash
sudo NO_COLOR=1 mcserver bootstrap
```

## PowerNukkitX resiliente

El updater intenta primero el snapshot oficial publicado por PowerNukkitX. Si ese asset no existe o upstream devuelve 404, compila automáticamente un `shadowJar` desde un commit oficial fijado y validado para la versión Bedrock soportada.

Esto evita que una instalación nueva quede bloqueada porque desaparezca un asset `snapshot`.

## Recuperar una instalación incompleta

```bash
sudo mcserver update project
sudo mcserver bootstrap
```

`bootstrap` es idempotente: completa runtimes, plugins, minijuegos, web, firewall y servicios sin reemplazar el mundo Survival.

Después:

```bash
sudo mcserver status
sudo mcserver plugins doctor
sudo mcserver minigames status
sudo mcserver network verify
sudo mcserver doctor
```

## Survival y protección de logros

Survival conserva:

```ini
gamemode=survival
force-gamemode=false
allow-cheats=false
online-mode=true
allow-list=true
```

Además:

- permanece en BDS;
- no recibe plugins PowerNukkitX;
- no recibe Behavior Packs de minijuegos;
- `level.dat` se importa sin modificar;
- en una instalación nueva permanece detenido hasta importar el mundo real.

### Importar por CLI

Acepta carpeta, `.zip` o `.mcworld`:

```bash
sudo mcserver import-survival /ruta/MiMundo.zip
```

El importador valida `level.dat`, `db/`, rutas ZIP, crea backup y evita archivos ambiguos o inseguros.

### Importar desde el panel web

Genera el token:

```bash
sudo mcserver web admin-token
```

Con HTTPS activo abre:

```text
https://TU_DOMINIO/admin.html
```

Desde ahí puedes subir `.zip` o `.mcworld`. El panel guarda solo el hash SHA-256 del token, la subida se procesa mediante un worker root separado y el archivo temporal se elimina al finalizar.

Consulta [`docs/WEB_ADMIN.md`](docs/WEB_ADMIN.md) para el flujo completo.

## Firewall

```bash
sudo mcserver firewall apply
sudo mcserver firewall status
```

En imágenes donde UFW está inactivo, `mcserver` crea una cadena `BEDROCK-NETWORK` antes de reglas `REJECT` existentes y permite:

```text
TCP 80,443
UDP 19132,19133,19134,19135,19136
```

Las reglas se persisten con `netfilter-persistent`. **TCP/22 no se modifica**, por lo que SSH queda fuera de la administración automática del proyecto.

Recuerda que proveedores cloud como Oracle también requieren reglas equivalentes en su Security List/NSG/firewall externo.

## Administración

```bash
mcserver status
sudo mcserver doctor
sudo mcserver backup
sudo mcserver restart
sudo mcserver update
sudo mcserver network verify
```

Logs por instancia:

```bash
sudo mcserver logs lobby
sudo mcserver logs pvp
sudo mcserver logs bedwars
sudo mcserver logs skywars
```

## Minijuegos

### PvP — NexoraPractice

```text
/pvp solo
/pvp duo
/pvp squad
/pvp leave
/pvp status
/lobby
```

Incluye arenas autogeneradas, colas, equipos, kits, friendly-fire bloqueado, espectador, eliminación por vacío y partidas `first-to-3`.

### BedWars — NexoraBedWars

```text
/bw solo
/bw duo
/bw squad
/bw leave
/bw status
/bw shop <blocks|sword|pickaxe|bow>
/lobby
```

Incluye bases, centro, camas-núcleo, respawn condicionado, recursos y tienda. SilentBedwars permanece como fallback manual.

### SkyWars — NexoraSkyWars

```text
/sw solo
/sw duo
/sw squad
/sw leave
/sw status
/lobby
```

Incluye islas, centro, loot-crates, bloques para puentes, friendly-fire bloqueado, espectador y eliminación definitiva. PowerSkywars permanece como fallback manual.

## Actualizaciones y rollback

```bash
sudo mcserver update
sudo mcserver update project
sudo mcserver update bds
sudo mcserver update pnx
sudo mcserver update plugins
```

Rollback:

```bash
sudo mcserver rollback bds VERSION
sudo mcserver rollback pnx RELEASE
```

## GitHub Actions

CI valida, entre otras cosas:

- que el template público no contenga IP/dominio del autor;
- aislamiento y protección de Survival;
- Bash, Python y JavaScript;
- preparación PNX en una instalación fresca con `set -u`;
- los tres plugins Nexora;
- pin oficial de PowerNukkitX;
- fallbacks SilentBedwars/PowerSkywars;
- importación `.zip`/`.mcworld` y rechazo de ZIPs inseguros;
- recuperación de permisos;
- panel web y paquete desplegable.
