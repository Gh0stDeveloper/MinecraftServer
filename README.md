# Minecraft Bedrock Network

Red híbrida para Minecraft Bedrock **26.40** con Lobby, Survival persistente, PvP, BedWars y SkyWars administrados desde una sola CLI.

## Despliegue

```text
IP pública : 163.192.204.78
Dominio    : minecraftnexora.duckdns.org
Lobby      : UDP 19132
Survival   : UDP 19133
PvP        : UDP 19134
BedWars    : UDP 19135
SkyWars    : UDP 19136
Web interno: TCP 8080
HTTP/HTTPS : TCP 80/443
```

`163.192.204.78` queda disponible como fallback. `mcserver network use-domain` solo activa `minecraftnexora.duckdns.org` si resuelve exactamente a esa IP.

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
  --public-ip 163.192.204.78 \
  --domain minecraftnexora.duckdns.org
```

Después de una actualización de kernel de Ubuntu/Oracle es recomendable reiniciar la VPS antes de continuar:

```bash
sudo reboot
```

### Recuperar/completar una instalación

Si una instalación se interrumpió después de crear los servicios pero `doctor` muestra `BDS: none`, `PowerNukkitX: none` o plugins Nexora faltantes:

```bash
sudo mcserver update project
sudo mcserver bootstrap
```

`bootstrap` completa de forma idempotente los runtimes BDS/PNX, plugins, minijuegos, Lobby, web y firewall local. Mantiene Survival detenido mientras `survival-pending-import` exista.

Después:

```bash
sudo mcserver plugins doctor
sudo mcserver minigames status
sudo mcserver firewall status
sudo mcserver network verify
sudo mcserver doctor
```

Mientras el Survival todavía no se haya importado, `network verify` considera normal que UDP/19133 no esté escuchando.

## Importar Survival desde Android

No es necesario copiar el mundo dentro del repositorio.

La opción recomendada, una vez activo HTTPS, es el panel privado:

```text
https://minecraftnexora.duckdns.org/admin.html
```

También puedes subir el archivo por SSH/SFTP a cualquier directorio de la VPS, por ejemplo:

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

## Red, firewall y DuckDNS

```bash
sudo mcserver network status
sudo mcserver firewall status
sudo mcserver network verify
```

Aplicar/reparar el firewall local:

```bash
sudo mcserver firewall apply
```

En imágenes Oracle con UFW desactivado, `mcserver` crea una cadena `BEDROCK-NETWORK` antes del `REJECT` global y permite TCP 80/443 + UDP 19132-19136. Las reglas se persisten con `netfilter-persistent`. TCP/22 no se modifica.

En Oracle Cloud también deben permitirse en Security Lists/NSG:

```text
TCP 80,443
UDP 19132-19136
```

No es necesario publicar TCP/8080; Nginx recibe 80/443 y reenvía internamente a la web.

Activar el dominio cuando DNS sea correcto:

```bash
sudo mcserver network use-domain
```

Volver a la IP:

```bash
sudo mcserver network use-ip
```

## Página web y HTTPS

Configurar Nginx con el dominio real:

```bash
sudo mcserver web domain minecraftnexora.duckdns.org
```

Configurar HTTPS:

```bash
sudo mcserver web https minecraftnexora.duckdns.org TU_CORREO
```

El administrador se niega a configurar Nginx/Certbot si el dominio no resuelve a `163.192.204.78`. Esto evita solicitar accidentalmente certificados para otro hostname.

Panel privado:

```bash
sudo mcserver web admin-token
```

Luego abre:

```text
https://minecraftnexora.duckdns.org/admin.html
```

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
- recuperación de permisos;
- safety gates de DNS/HTTPS;
- web y artifact desplegable.
