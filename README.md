# Minecraft Bedrock Network

Red híbrida para Minecraft Bedrock **26.40** orientada a un grupo privado: Lobby, Survival persistente, PvP, BedWars y SkyWars administrados desde una sola CLI.

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
       +--> PvP      :19134  PowerNukkitX + NexoraPractice
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
curl -fsSL https://raw.githubusercontent.com/Gh0stDeveloper/MinecraftServer/main/install.sh | sudo bash -s -- --host TU_IP_O_DOMINIO
```

Instala BDS, Java 21, PowerNukkitX, plugins administrados, systemd, backups, firewall y página pública.

Después importa tu mundo:

```bash
sudo mcserver import-survival "/ruta/a/TuMundo"
```

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

Catálogo inicial:

| Instancia | Plugin | Fuente |
|---|---|---|
| PvP | NexoraPractice | propio, Maven |
| BedWars | SilentBedwars | upstream fijado, Gradle |
| SkyWars | PowerSkywars | upstream fijado, Gradle |

GitHub Actions recompila esos plugins para detectar incompatibilidades antes de aceptar cambios.

## Actualizaciones

```bash
sudo mcserver update
```

Actualiza secuencialmente proyecto/web/scripts, BDS, PowerNukkitX, plugins fijados y ejecuta un diagnóstico final. Los updaters recuerdan qué instancias estaban activas y no arrancan durante una actualización servidores que estuvieran detenidos.

También puedes actualizar por componente:

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

La instalación levanta la web en `http://TU_IP:8080`. Muestra jugadores, estado, puerto, motor (`BDS oficial`/`PowerNukkitX`) y versiones de runtime mediante ping Bedrock nativo.

Dominio y HTTPS:

```bash
sudo mcserver web domain mc.example.com
sudo mcserver web https mc.example.com correo@example.com
```

## Lobby

El lobby sigue siendo una isla flotante BDS. Después de dar la etiqueta `network.admin` al constructor, `!buildhub` crea el hub base con plataformas para Survival, PvP, BedWars y SkyWars.

## GitHub Actions

CI valida configuración BDS y protección de Survival, arquitectura híbrida, sintaxis, catálogo/commits fijados, compilación del plugin PvP propio, compilación de BedWars/SkyWars, resolver BDS, smoke test de la web y artifact desplegable.

Consulta `docs/PLUGIN_ENGINES.md` para el diseño de motores y plugins.
