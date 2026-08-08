# Minecraft Bedrock Network

Red híbrida para Minecraft Bedrock **26.40** con Lobby, Survival persistente, PvP, BedWars y SkyWars administrados desde una sola CLI.

## Despliegue

```text
IP pública : 147.224.196.17
Dominio    : minecraftnexora.duckdns.org
Lobby      : UDP 19132
Survival   : UDP 19133
PvP        : UDP 19134
BedWars    : UDP 19135
SkyWars    : UDP 19136
Web        : TCP 8080
HTTP/HTTPS : TCP 80/443
```

`147.224.196.17` queda disponible como fallback. `mcserver network use-domain` solo activa `minecraftnexora.duckdns.org` si resuelve exactamente a esa IP.

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
       +--> PvP      :19134  PowerNukkitX + NexoraPractice 0.2
       +--> BedWars  :19135  PowerNukkitX + NexoraBedWars 0.1
       +--> SkyWars  :19136  PowerNukkitX + NexoraSkyWars 0.1
```

Lobby y Survival permanecen en BDS. Los minijuegos usan motores Nexora propios sobre PowerNukkitX y generan sus arenas automáticamente.

## Instalación

Ubuntu 22.04/24.04 AMD64/x86_64:

```bash
curl -fsSL https://raw.githubusercontent.com/Gh0stDeveloper/MinecraftServer/main/install.sh | sudo bash
```

También puede indicarse el despliegue explícitamente:

```bash
curl -fsSL https://raw.githubusercontent.com/Gh0stDeveloper/MinecraftServer/main/install.sh | sudo bash -s -- \
  --public-ip 147.224.196.17 \
  --domain minecraftnexora.duckdns.org
```

Después de una actualización de kernel de Ubuntu/Oracle es recomendable reiniciar la VPS antes de continuar:

```bash
sudo reboot
```

### Recuperar/completar una instalación

Si una instalación se interrumpió después de crear los servicios:

```bash
sudo mcserver update
sudo mcserver restart
sudo systemctl restart bedrock-web.service
sudo mcserver doctor
sudo mcserver network verify
```

Mientras el Survival todavía no se haya importado, `network verify` considera normal que UDP/19133 no esté escuchando.

## Importar Survival desde Android

No es necesario copiar el mundo dentro del repositorio.

Puedes subir el archivo a cualquier directorio de la VPS; se recomienda:

```text
/root/uploads/MiSurvival.zip
```

o, si accedes con el usuario `ubuntu`:

```text
/home/ubuntu/uploads/MiSurvival.zip
```

El comando acepta:

- una carpeta Bedrock ya extraída;
- un `.zip`;
- un `.mcworld`.

Ejemplos:

```bash
sudo mcserver import-survival "/root/uploads/MiSurvival.zip"
```

```bash
sudo mcserver import-survival "/root/uploads/MiSurvival.mcworld"
```

El archivo puede contener directamente `level.dat`/`db/` o una carpeta contenedora. El importador encuentra el mundo automáticamente y rechaza archivos con más de un mundo o rutas ZIP inseguras.

Validar sin importar:

```bash
sudo /opt/bedrock-network/app/scripts/import-survival.sh --check "/root/uploads/MiSurvival.zip"
```

Destino final administrado por el servidor:

```text
/opt/bedrock-network/instances/survival/worlds/SurvivalWorld/
```

No copies manualmente archivos allí mientras el servicio esté encendido; usa `mcserver import-survival` para obtener backup, permisos y configuración segura.

### Protección de logros

Survival conserva:

```ini
gamemode=survival
force-gamemode=false
allow-cheats=false
online-mode=true
allow-list=true
```

`level.dat` se copia sin modificar, `SURVIVAL_ENGINE=bds` permanece bloqueado y no se instalan plugins PNX ni Behavior Packs de minijuegos en Survival.

## Red y DuckDNS

```bash
sudo mcserver network status
sudo mcserver network verify
```

Activar el dominio cuando DNS sea correcto:

```bash
sudo mcserver network use-domain
```

Volver a la IP:

```bash
sudo mcserver network use-ip
```

## Página web y HTTPS

Backend inicial:

```text
http://147.224.196.17:8080
```

Configurar Nginx con el dominio real:

```bash
sudo mcserver web domain minecraftnexora.duckdns.org
```

Configurar HTTPS:

```bash
sudo mcserver web https minecraftnexora.duckdns.org TU_CORREO
```

El administrador se niega a configurar Nginx/Certbot si el dominio no resuelve a `147.224.196.17`. Esto evita solicitar accidentalmente certificados para otro hostname.

En Oracle Cloud también deben permitirse TCP 80/443 en Security Lists/NSG; UFW por sí solo no abre el firewall externo de Oracle.

## Administración

```bash
mcserver status
sudo mcserver doctor
sudo mcserver backup
sudo mcserver restart
sudo mcserver update
sudo mcserver network verify
```

Logs:

```bash
sudo mcserver logs lobby
sudo mcserver logs pvp
sudo mcserver logs bedwars
sudo mcserver logs skywars
```

Web:

```bash
sudo mcserver web status
sudo mcserver web restart
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

Incluye arenas autogeneradas, colas, equipos, kit, friendly-fire bloqueado, espectador, eliminación por vacío y partidas `first-to-3`.

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

Genera bases, centro, puentes, camas-núcleo, respawn condicionado, recursos y tienda. SilentBedwars permanece como fallback manual.

## SkyWars — NexoraSkyWars 0.1

```text
/sw solo     -> 4 equipos de 1
/sw duo      -> 4 equipos de 2
/sw squad    -> 4 equipos de 4
/sw leave
/sw status
/lobby
```

Genera cuatro islas y centro, loot-crates, bloques para puentes, friendly-fire bloqueado, espectador y eliminación definitiva. PowerSkywars permanece como fallback manual.

## Actualizaciones

Actualizar todo:

```bash
sudo mcserver update
```

Por componente:

```bash
sudo mcserver update project
sudo mcserver update bds
sudo mcserver update pnx
sudo mcserver update plugins
```

Rollback de runtimes:

```bash
sudo mcserver rollback bds VERSION
sudo mcserver rollback pnx RELEASE
```

## GitHub Actions

CI valida:

- configuración y aislamiento de Survival;
- dominio/IP de despliegue;
- Bash, Python y JavaScript;
- los tres motores Nexora;
- fallbacks SilentBedwars/PowerSkywars;
- importación de Survival desde `.zip` y `.mcworld`;
- rechazo de ZIPs inseguros;
- safety gates de DNS/HTTPS;
- web y artifact desplegable.
