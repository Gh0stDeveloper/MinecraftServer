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
       +--> SkyWars  :19136  PowerNukkitX + PowerSkywars
```

Lobby y Survival están bloqueados a BDS. PowerNukkitX se usa solo para minijuegos.

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

No requiere mapas externos.

```text
/pvp solo    -> 1v1
/pvp duo     -> 2v2
/pvp squad   -> 4v4
/pvp leave
/pvp status
/lobby
```

Incluye colas, hasta 8 arenas, equipos automáticos, kit PvP, friendly-fire bloqueado, espectador, vacío, `first-to-3` y reutilización automática de arena.

## BedWars — NexoraBedWars 0.1

BedWars ahora usa un motor **propio y autogenerado**; tampoco requiere mapas externos.

```text
/bw solo     -> 1v1
/bw duo      -> 2v2
/bw squad    -> 4v4
/bw leave
/bw status
/bw shop <blocks|sword|pickaxe|bow>
/lobby
```

Cada arena tiene dos bases, centro y vacío para puentes. Cada equipo posee una cama-núcleo:

- cama viva -> el jugador reaparece;
- cama destruida -> la próxima muerte es definitiva;
- último equipo con jugadores vivos -> victoria.

Recursos y tienda:

```text
4 hierro  -> 16 bloques del equipo
10 hierro -> espada de piedra
12 hierro -> pico de hierro
8 oro     -> arco + flechas
```

La estructura de la arena está protegida; solo pueden romperse bloques colocados durante la partida y la cama rival. Al terminar, se eliminan los puentes/bloques temporales y la arena se reutiliza.

SilentBedwars permanece en `config/plugins.json` únicamente como fallback manual:

```bash
sudo mcserver plugins install silentbedwars
```

El administrador retira automáticamente `nexora-bedwars.jar` para evitar ejecutar ambos a la vez. Para volver:

```bash
sudo mcserver plugins install nexora-bedwars
sudo mcserver minigames prepare
```

## SkyWars

PowerSkywars usa mapas administrados:

```bash
sudo mcserver minigames import-skywars Islas1 "/ruta/Islas1" \
  --spawns "20,70,0;-20,70,0;0,70,20;0,70,-20" \
  --mid "0,68,0"
```

El sistema valida el mundo, hace backup, registra las coordenadas y genera `maps_config.yml`.

## Estado de minijuegos

```bash
sudo mcserver minigames status
sudo mcserver minigames verify
sudo mcserver plugins doctor
```

El lobby usa `NETWORK.ready`: PvP y BedWars quedan disponibles por sus motores autogenerados; SkyWars solo cuando tiene al menos un mapa válido.

`mcserver minigames import-bedwars` se conserva exclusivamente para el fallback legacy SilentBedwars.

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
sudo mcserver plugins install powerskywars
```

| Instancia | Plugin predeterminado | Fuente |
|---|---|---|
| PvP | NexoraPractice 0.2 | propio, Maven |
| BedWars | NexoraBedWars 0.1 | propio, Maven |
| SkyWars | PowerSkywars | upstream fijado, Gradle |
| BedWars fallback | SilentBedwars | upstream fijado, manual |

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

CI valida configuración, aislamiento de Survival, sintaxis, resolver BDS, web, NexoraPractice, **NexoraBedWars**, compatibilidad del fallback SilentBedwars, PowerSkywars y el artifact desplegable.

Documentación:

- `docs/PLUGIN_ENGINES.md`
- `docs/MINIGAMES.md`
- `docs/VPS_DEPLOYMENT.md`
