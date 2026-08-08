# Minecraft Bedrock Network

Red autoadministrable para Minecraft Bedrock basada en **Bedrock Dedicated Server oficial**. Incluye Lobby, Survival, PvP, BedWars, SkyWars, actualización segura, backups, GitHub Actions y una web pública de estado.

## Arquitectura

```text
                         UDP 19132
Jugador  ───────────────► LOBBY
                             │
                 ┌───────────┼───────────┐
                 │           │           │
                 ▼           ▼           ▼
             SURVIVAL       PVP      MINIJUEGOS
              :19133       :19134     ├─ BedWars :19135
                                     └─ SkyWars :19136
```

El lobby es una **isla flotante** con zona central y cuatro plataformas de acceso. El comando `!buildhub` genera su estructura base después de asignar al administrador la etiqueta `network.admin`.

## Survival y logros

Survival está deliberadamente aislado:

```ini
gamemode=survival
force-gamemode=false
allow-cheats=false
online-mode=true
allow-list=true
```

- no recibe el Behavior Pack del lobby;
- no recibe los Behavior Packs de minijuegos;
- el importador copia `level.dat` sin modificarlo;
- las actualizaciones de BDS no reemplazan el directorio `worlds/`;
- GitHub Actions falla si las propiedades de seguridad del template Survival cambian.

> Si el mundo ya perdió previamente la elegibilidad para logros, moverlo al servidor no la restaura. El objetivo aquí es no introducir cambios que la deshabiliten en un mundo que todavía la conserva.

# Instalación: un comando

En Ubuntu 22.04/24.04 AMD64/x86_64:

```bash
curl -fsSL https://raw.githubusercontent.com/Gh0stDeveloper/MinecraftServer/main/install.sh | bash
```

El asistente solicita la IP o dominio público y hace la instalación completa.

No interactivo:

```bash
curl -fsSL https://raw.githubusercontent.com/Gh0stDeveloper/MinecraftServer/main/install.sh | sudo bash -s -- --host play.example.com
```

También funciona desde un clone:

```bash
git clone https://github.com/Gh0stDeveloper/MinecraftServer.git
cd MinecraftServer
sudo ./mcserver install --host play.example.com
```

## Administración diaria

```bash
mcserver status
sudo mcserver doctor
sudo mcserver backup
sudo mcserver restart
sudo mcserver logs survival
```

## Actualizar todo

```bash
sudo mcserver update
```

Ese comando sincroniza la versión del proyecto y comprueba BDS. Cuando existe un BDS más nuevo:

1. descarga el ZIP en staging;
2. exige que el archivo venga de un dominio oficial de Minecraft;
3. detiene las cinco instancias;
4. crea backup;
5. comprueba nuevamente que Survival tenga cheats desactivados;
6. aplica los archivos de runtime sin reemplazar mundos, configuración, allowlists o permisos;
7. inicia y valida las instancias;
8. permite rollback al runtime anterior.

El software BDS se obtiene del CDN oficial. Para descubrir de forma automatizable el número/URL de la versión estable se utiliza el índice de `Bedrock-OSS/BDS-Versions`; el resolver rechaza cualquier `download_url` que no apunte a un host oficial permitido de Minecraft.

Solo BDS:

```bash
sudo mcserver update bds
```

Solo proyecto/web:

```bash
sudo mcserver update project
```

Rollback:

```bash
sudo mcserver rollback 1.26.40.1
```

Auto-update BDS opcional:

```bash
sudo mcserver auto-update enable
```

Está desactivado de fábrica.

# Página oficial del servidor

La instalación levanta automáticamente una web pública en:

```text
http://IP_O_DOMINIO:8080
```

Incluye:

- estado en vivo de las cinco instancias;
- número de jugadores mediante ping Bedrock;
- versión BDS;
- dirección del lobby con botón para copiar;
- descripción de Survival/PvP/BedWars/SkyWars;
- diseño responsive para teléfono y escritorio.

Para poner un dominio delante con Nginx:

```bash
sudo mcserver web domain mc.example.com
```

Y HTTPS:

```bash
sudo mcserver web https mc.example.com correo@example.com
```

# Importar tu mundo avanzado

Guarda primero una copia original fuera del servidor y ejecuta:

```bash
sudo mcserver import-survival "/ruta/al/Mundo"
```

El importador verifica `level.dat` y `db/`, detiene Survival, hace backup del mundo existente y copia la nueva carpeta sin editar `level.dat`.

# GitHub Actions

Cada push/PR valida:

- estructura y JSON;
- manifests y UUID;
- puertos;
- aislamiento de Survival;
- propiedades de seguridad de logros;
- sintaxis Bash;
- sintaxis JavaScript;
- sintaxis Python;
- resolver de actualizaciones BDS, incluyendo rechazo de URLs no oficiales;
- smoke test de la web;
- empaquetado del proyecto como artifact.

# Documentación

- [`docs/ADMIN_GUIDE.md`](docs/ADMIN_GUIDE.md): instalación, actualización, rollback, web y mantenimiento.
- [`docs/SURVIVAL_IMPORT.md`](docs/SURVIVAL_IMPORT.md): migración del mundo.
- [`docs/LOBBY_ISLAND.md`](docs/LOBBY_ISLAND.md): isla flotante del hub.
- [`docs/PORTS.md`](docs/PORTS.md): puertos.
- [`docs/NEXT_PHASE.md`](docs/NEXT_PHASE.md): minijuegos y siguientes fases.

## Estado del proyecto

La infraestructura, administración y lobby base están preparados. PvP/BedWars/SkyWars ya tienen el framework inicial de colas; las siguientes fases completarán `ArenaManager`, mapas, equipos, generadores, tiendas, camas, loot, espectador, reset de arenas y estadísticas persistentes.
