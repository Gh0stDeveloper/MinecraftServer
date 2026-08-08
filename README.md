# Minecraft Bedrock Network

Red híbrida para Minecraft Bedrock **26.40**: Lobby, Survival persistente, PvP, BedWars y SkyWars administrados desde una sola CLI.

## Despliegue principal

```text
IP pública : 147.224.196.17
Dominio    : minecraftserver.duckdns.org
Lobby      : UDP 19132
Survival   : UDP 19133
PvP        : UDP 19134
BedWars    : UDP 19135
SkyWars    : UDP 19136
Web        : TCP 8080
```

`147.224.196.17` es el fallback seguro. El proyecto solo activa `minecraftserver.duckdns.org` para transferencias cuando el DNS resuelve exactamente a esa IP.

## Arquitectura

```text
Jugador Bedrock
      |
      | UDP 19132
      v
+-------------+
|    LOBBY    |  BDS oficial + addon del hub
+------+------+ 
       |
       +--> Survival :19133  BDS oficial, sin plugins, cheats=false
       +--> PvP      :19134  PowerNukkitX + NexoraPractice 0.2
       +--> BedWars  :19135  PowerNukkitX + NexoraBedWars 0.1
       +--> SkyWars  :19136  PowerNukkitX + NexoraSkyWars 0.1
```

Lobby y Survival están bloqueados a BDS. Los tres minijuegos usan motores Nexora propios sobre PowerNukkitX y generan sus arenas automáticamente.

## Survival y logros

```ini
gamemode=survival
force-gamemode=false
allow-cheats=false
online-mode=true
allow-list=true
```

- `SURVIVAL_ENGINE=bds` no puede cambiarse con `mcserver engine`;
- Survival no recibe plugins PNX ni Behavior Packs de minijuegos;
- `import-survival` copia `level.dat` sin modificarlo;
- una instalación nueva bloquea la creación de un Survival vacío hasta importar el mundo real;
- actualizaciones y cambios de motor crean backups.

## Instalación

Ubuntu 22.04/24.04 AMD64/x86_64:

```bash
curl -fsSL https://raw.githubusercontent.com/Gh0stDeveloper/MinecraftServer/main/install.sh | sudo bash
```

Explícito:

```bash
curl -fsSL https://raw.githubusercontent.com/Gh0stDeveloper/MinecraftServer/main/install.sh | sudo bash -s -- \
  --public-ip 147.224.196.17 \
  --domain minecraftserver.duckdns.org
```

Si DuckDNS todavía no apunta a la VPS, el instalador conserva la IP como host público.

Después importa el Survival:

```bash
sudo mcserver import-survival "/ruta/a/TuMundo"
```

## PvP — NexoraPractice 0.2

```text
/pvp solo    -> 1v1
/pvp duo     -> 2v2
/pvp squad   -> 4v4
/pvp leave
/pvp status
/lobby
```

No requiere mapas externos. Incluye colas, hasta 8 arenas, equipos automáticos, kit PvP, friendly-fire bloqueado, espectador, vacío, `first-to-3` y reutilización automática.

## BedWars — NexoraBedWars 0.1

```text
/bw solo     -> 1v1
/bw duo      -> 2v2
/bw squad    -> 4v4
/bw leave
/bw status
/bw shop <blocks|sword|pickaxe|bow>
/lobby
```

Genera bases, centro y vacío para puentes. Cada equipo tiene una cama-núcleo: mientras viva hay respawn; destruida, la próxima muerte es definitiva. La estructura está protegida y los bloques temporales se limpian al terminar.

Tienda:

```text
4 hierro  -> 16 bloques del equipo
10 hierro -> espada de piedra
12 hierro -> pico de hierro
8 oro     -> arco + flechas
```

SilentBedwars queda como fallback manual:

```bash
sudo mcserver plugins install silentbedwars
```

Para volver:

```bash
sudo mcserver plugins install nexora-bedwars
sudo mcserver minigames prepare
```

## SkyWars — NexoraSkyWars 0.1

SkyWars también es ahora **propio y autogenerado**.

```text
/sw solo     -> 4 equipos de 1 (4 jugadores)
/sw duo      -> 4 equipos de 2 (8 jugadores)
/sw squad    -> 4 equipos de 4 (16 jugadores)
/sw leave
/sw status
/lobby
```

Cada arena genera cuatro islas —Rojo, Azul, Verde y Amarillo— más un centro. Los jugadores reciben bloques para puentes y pueden abrir loot-crates de isla y crates de mejor nivel en el centro. No hay respawn: muerte o vacío elimina al jugador; el último equipo vivo gana. Puentes, bloques y crates se restauran al terminar.

PowerSkywars queda como fallback manual:

```bash
sudo mcserver plugins install powerskywars
```

Solo en ese modo legacy se usan mapas externos:

```bash
sudo mcserver minigames import-skywars Islas1 "/ruta/Islas1" \
  --spawns "20,70,0;-20,70,0;0,70,20;0,70,-20" \
  --mid "0,68,0"
```

Para regresar al motor propio:

```bash
sudo mcserver plugins install nexora-skywars
sudo mcserver minigames prepare
```

## Estado de minijuegos

```bash
sudo mcserver minigames status
sudo mcserver minigames verify
sudo mcserver plugins doctor
```

Con los motores predeterminados, PvP, BedWars y SkyWars quedan disponibles sin importar mapas. Los importadores se mantienen exclusivamente para los fallbacks upstream.

## Red y DuckDNS

```bash
sudo mcserver network status
sudo mcserver network verify
```

Cuando DuckDNS ya resuelva a `147.224.196.17`:

```bash
sudo mcserver network use-domain
```

Para volver a IP:

```bash
sudo mcserver network use-ip
```

## Administración

```bash
mcserver status
sudo mcserver doctor
sudo mcserver backup
sudo mcserver restart
sudo mcserver update
```

Motores:

```bash
mcserver engine status
sudo mcserver engine set bedwars pnx
sudo mcserver engine set bedwars bds
```

Plugins:

```bash
sudo mcserver plugins list
sudo mcserver plugins doctor
sudo mcserver plugins sync
```

| Instancia | Plugin predeterminado | Fuente |
|---|---|---|
| PvP | NexoraPractice 0.2 | propio, Maven |
| BedWars | NexoraBedWars 0.1 | propio, Maven |
| SkyWars | NexoraSkyWars 0.1 | propio, Maven |
| BedWars fallback | SilentBedwars | upstream fijado, manual |
| SkyWars fallback | PowerSkywars | upstream fijado, manual |

## Actualizaciones

```bash
sudo mcserver update
```

También:

```bash
sudo mcserver update bds
sudo mcserver update pnx
sudo mcserver update plugins
sudo mcserver update project
sudo mcserver rollback bds VERSION
sudo mcserver rollback pnx RELEASE
```

## Web

Inicialmente:

```text
http://147.224.196.17:8080
```

Nginx:

```bash
sudo mcserver web domain minecraftserver.duckdns.org
```

HTTPS después de que DNS funcione:

```bash
sudo mcserver web https minecraftserver.duckdns.org TU_CORREO
```

## GitHub Actions

CI valida configuración, aislamiento de Survival, sintaxis, resolver BDS, web, los tres motores Nexora nativos, compatibilidad de SilentBedwars/PowerSkywars como fallbacks y el artifact desplegable.

Documentación:

- `docs/PLUGIN_ENGINES.md`
- `docs/MINIGAMES.md`
- `docs/VPS_DEPLOYMENT.md`
