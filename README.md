# Minecraft Bedrock Network

Red híbrida para Minecraft Bedrock **26.40** orientada a un grupo privado: Lobby, Survival persistente, PvP, BedWars y SkyWars administrados desde una sola CLI.

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

`147.224.196.17` permanece como fallback seguro. El proyecto solo cambia las transferencias al dominio cuando `minecraftserver.duckdns.org` resuelve exactamente a esa IP.

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
       +--> BedWars  :19135  PowerNukkitX + plugin administrado
       +--> SkyWars  :19136  PowerNukkitX + plugin administrado
```

PowerNukkitX se usa **solo para minijuegos**. Lobby y Survival están bloqueados a BDS por diseño.

## Survival y logros

El template de Survival exige:

```ini
gamemode=survival
force-gamemode=false
allow-cheats=false
online-mode=true
allow-list=true
```

Además:

- `SURVIVAL_ENGINE=bds` no puede cambiarse mediante `mcserver engine`;
- no se instalan plugins PNX ni Behavior Packs de minijuegos en Survival;
- `import-survival` copia `level.dat` sin modificarlo;
- una instalación nueva crea `state/survival-pending-import`, por lo que no se genera un Survival vacío antes de importar tu mundo;
- los backups incluyen mundo, configuración y estado antes de actualizaciones/cambios de motor.

> Si el mundo ya perdió previamente la elegibilidad para logros, moverlo al servidor no la restaura. El proyecto está diseñado para no introducir cambios que deshabiliten los logros en un mundo que todavía los conserva.

## Instalación con un comando

Ubuntu 22.04/24.04 AMD64/x86_64:

```bash
curl -fsSL https://raw.githubusercontent.com/Gh0stDeveloper/MinecraftServer/main/install.sh | sudo bash
```

La IP y el dominio objetivo ya están definidos en el proyecto. También puedes pasarlos explícitamente:

```bash
curl -fsSL https://raw.githubusercontent.com/Gh0stDeveloper/MinecraftServer/main/install.sh | sudo bash -s -- \
  --public-ip 147.224.196.17 \
  --domain minecraftserver.duckdns.org
```

El instalador comprueba DNS antes de elegir el host público. Si DuckDNS todavía no apunta a la VPS, usa la IP.

Instala BDS, Java 21, PowerNukkitX, plugins administrados, systemd, backups, firewall, utilidades de red y página pública.

Después importa tu Survival:

```bash
sudo mcserver import-survival "/ruta/a/TuMundo"
```

## PvP jugable

NexoraPractice 0.2 genera sus arenas automáticamente. No necesita mapas externos.

```text
/pvp solo    -> 1v1
/pvp duo     -> 2v2
/pvp squad   -> 4v4
/pvp leave
/pvp status
/lobby
```

Incluye:

- colas independientes;
- hasta 8 arenas simultáneas por defecto;
- equipos automáticos;
- kit PvP;
- friendly-fire bloqueado;
- eliminación sin perder la sesión;
- espectador al morir;
- eliminación por vacío;
- rondas `first-to-3`;
- liberación y reutilización automática de arena.

Consulta `docs/MINIGAMES.md` para detalles.

## BedWars y SkyWars

Estas modalidades **no se muestran como listas en el lobby solo porque el servidor esté encendido**. Necesitan contenido jugable válido.

Estado:

```bash
sudo mcserver minigames status
```

### Importar BedWars

```bash
sudo mcserver minigames import-bedwars "/ruta/al/MapaBedWars"
```

El mapa debe contener `level.dat` y `db/`. El importador hace backup y crea un marcador de validación para evitar confundir el mundo vacío generado por PNX con un mapa real.

### Importar SkyWars

```bash
sudo mcserver minigames import-skywars Islas1 "/ruta/Islas1" \
  --spawns "20,70,0;-20,70,0;0,70,20;0,70,-20" \
  --mid "0,68,0"
```

El sistema copia el mapa, registra las coordenadas y genera automáticamente `maps_config.yml` para PowerSkywars.

Validación:

```bash
sudo mcserver minigames verify
```

Mientras una modalidad no esté lista, el menú/NPC del lobby muestra `PREPARANDO MAPA` y no transfiere al jugador.

## Red y DuckDNS

Ver estado:

```bash
sudo mcserver network status
sudo mcserver network verify
```

Cuando `minecraftserver.duckdns.org` ya resuelva a `147.224.196.17`:

```bash
sudo mcserver network use-domain
```

El comando se niega a activarlo si el DNS apunta a otra IP.

Volver al fallback por IP:

```bash
sudo mcserver network use-ip
```

Consulta `docs/VPS_DEPLOYMENT.md` para firewall, DuckDNS, Nginx y HTTPS.

## Administración

```bash
mcserver status
sudo mcserver doctor
sudo mcserver backup
sudo mcserver restart
sudo mcserver update
```

### Motores

```bash
mcserver engine status
sudo mcserver engine set bedwars pnx
sudo mcserver engine set bedwars bds
```

Solo `pvp`, `bedwars` y `skywars` pueden cambiar entre `pnx` y `bds`. Cada cambio hace backup y rollback si el nuevo motor no inicia.

### Plugins

```bash
sudo mcserver plugins list
sudo mcserver plugins doctor
sudo mcserver plugins sync
sudo mcserver plugins install powerskywars
```

El catálogo está en `config/plugins.json`. Las fuentes de terceros están fijadas a commits concretos; no se redistribuyen sus JAR dentro de este repositorio.

| Instancia | Plugin | Fuente |
|---|---|---|
| PvP | NexoraPractice 0.2 | propio, Maven |
| BedWars | SilentBedwars | upstream fijado, Gradle |
| SkyWars | PowerSkywars | upstream fijado, Gradle |

GitHub Actions recompila esos plugins para detectar incompatibilidades antes de aceptar cambios.

## Actualizaciones

```bash
sudo mcserver update
```

Actualiza secuencialmente proyecto/web/scripts, BDS, PowerNukkitX, plugins fijados, configuración administrada de minijuegos y ejecuta un diagnóstico final. Los updaters recuerdan qué instancias estaban activas y no arrancan durante una actualización servidores que estuvieran detenidos.

Por componente:

```bash
sudo mcserver update bds
sudo mcserver update pnx
sudo mcserver update plugins
sudo mcserver update project
```

Rollback:

```bash
sudo mcserver rollback bds VERSION
sudo mcserver rollback pnx RELEASE
```

Auto-update opcional:

```bash
sudo mcserver auto-update enable
```

## Página oficial

La instalación levanta la web inicialmente en:

```text
http://147.224.196.17:8080
```

Muestra jugadores, estado, puerto, motor (`BDS oficial`/`PowerNukkitX`) y versiones de runtime mediante ping Bedrock nativo.

Nginx y dominio:

```bash
sudo mcserver web domain minecraftserver.duckdns.org
```

HTTPS, solo después de que DNS funcione:

```bash
sudo mcserver web https minecraftserver.duckdns.org TU_CORREO
```

## Lobby

El lobby sigue siendo una isla flotante BDS. Después de dar la etiqueta `network.admin` al constructor, `!buildhub` crea el hub base con plataformas para Survival, PvP, BedWars y SkyWars.

La disponibilidad de cada minijuego se genera desde el estado real de la VPS mediante `NETWORK.ready`.

## GitHub Actions

CI valida:

- configuración BDS y aislamiento de Survival;
- IP/dominio y fallback de despliegue;
- arquitectura híbrida;
- sintaxis Bash, Python y JavaScript;
- catálogo/commits fijados;
- compilación real de NexoraPractice 0.2;
- compilación de SilentBedwars y PowerSkywars contra PNX actual;
- safety gates de mapas;
- resolver BDS;
- smoke test de la web;
- artifact desplegable.

Documentación adicional:

- `docs/PLUGIN_ENGINES.md`
- `docs/MINIGAMES.md`
- `docs/VPS_DEPLOYMENT.md`
