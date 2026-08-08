# Administración con `mcserver`

`mcserver` es la interfaz única para instalar y mantener Bedrock Network.

## Primera instalación

### Opción A: un solo comando

```bash
curl -fsSL https://raw.githubusercontent.com/Gh0stDeveloper/MinecraftServer/main/install.sh | bash
```

El instalador pedirá la IP o dominio público de Minecraft y realizará el resto automáticamente.

Para una instalación no interactiva:

```bash
curl -fsSL https://raw.githubusercontent.com/Gh0stDeveloper/MinecraftServer/main/install.sh | sudo bash -s -- --host play.example.com
```

Si ya existe un dominio para la web:

```bash
curl -fsSL https://raw.githubusercontent.com/Gh0stDeveloper/MinecraftServer/main/install.sh | sudo bash -s -- --host play.example.com --domain mc.example.com
```

### Opción B: clonar GitHub

```bash
git clone https://github.com/Gh0stDeveloper/MinecraftServer.git
cd MinecraftServer
sudo ./mcserver install --host play.example.com
```

## Qué hace la instalación

1. Valida x86_64/AMD64 y la plataforma.
2. Instala dependencias de Ubuntu.
3. Crea el usuario de sistema `bedrock`.
4. Crea `/opt/bedrock-network`.
5. Descarga el BDS estable.
6. Valida que la URL del ZIP pertenezca a un dominio oficial de Minecraft.
7. Prepara Lobby, Survival, PvP, BedWars y SkyWars.
8. Mantiene el Survival con `allow-cheats=false`.
9. Genera una primera ejecución para crear los mundos de lobby/minijuegos e instala sus addons.
10. Instala servicios systemd.
11. Inicia la página de estado pública en el puerto 8080.
12. Abre los puertos UDP de la red en UFW.

El Behavior Pack de la red **no se instala en Survival**.

## Actualizar todo

```bash
sudo mcserver update
```

El comando actualiza:

- código del administrador desde `main`;
- página web;
- unidades systemd;
- addons incluidos en el proyecto;
- BDS estable, si existe una versión nueva.

La actualización BDS funciona así:

1. descarga el runtime nuevo en un directorio separado;
2. detiene las instancias;
3. crea un backup consistente;
4. verifica la configuración segura de Survival;
5. aplica el runtime sin sobrescribir `server.properties`, allowlist, permisos ni mundos;
6. conserva packs personalizados y actualiza los packs vanilla incluidos por BDS;
7. inicia las cinco instancias;
8. comprueba que los servicios estén activos;
9. si algo falla, vuelve al runtime anterior.

## Actualizar solo BDS

```bash
sudo mcserver update bds
```

Versión concreta previamente publicada en el índice:

```bash
sudo mcserver update bds 1.26.40.1
```

## Actualizar solo el proyecto

```bash
sudo mcserver update project
```

## Rollback BDS

Ver versiones descargadas:

```bash
sudo mcserver rollback
```

Volver a una versión:

```bash
sudo mcserver rollback 1.26.40.1
```

El rollback cambia el runtime. No restaura ni reemplaza el mundo Survival.

## Actualización BDS automática

Está desactivada inicialmente para evitar cambios inesperados.

Activar:

```bash
sudo mcserver auto-update enable
```

Desactivar:

```bash
sudo mcserver auto-update disable
```

Consultar:

```bash
sudo mcserver auto-update status
```

El timer comprueba BDS diariamente. Antes de instalar una actualización utiliza el mismo mecanismo de backup y comprobación que el comando manual.

## Estado

```bash
mcserver status
```

## Diagnóstico

```bash
sudo mcserver doctor
```

Comprueba arquitectura, runtime BDS, configuración persistente, seguridad del Survival, almacenamiento y servicios.

## Backups

```bash
sudo mcserver backup
```

Para que LevelDB quede consistente, el backup de red detiene las instancias brevemente, genera el archivo y vuelve a iniciarlas.

## Importar el Survival existente

Primero conserva una copia original fuera de la VPS. Después:

```bash
sudo mcserver import-survival "/ruta/al/Mundo"
```

El importador no modifica `level.dat`, fuerza las propiedades del servidor que deben seguir seguras y no añade addons de la red al Survival.

## Logs

```bash
sudo mcserver logs lobby
sudo mcserver logs survival
sudo mcserver logs bedwars
```

## Web pública

Nada más instalar:

```text
http://IP_DE_LA_VPS:8080
```

La web muestra:

- dirección para conectarse;
- versión BDS instalada;
- estado de Lobby, Survival, PvP, BedWars y SkyWars;
- jugadores obtenidos mediante ping Bedrock;
- puertos;
- descripción de modalidades.

### Dominio

```bash
sudo mcserver web domain mc.example.com
```

### HTTPS

Después de que el DNS apunte a la VPS:

```bash
sudo mcserver web https mc.example.com correo@example.com
```

Esto configura Nginx y Let's Encrypt.

## Directorios

```text
/opt/bedrock-network/
├── app/          # versión instalada del proyecto
├── addons/       # addons listos para desplegar
├── backups/      # copias de seguridad
├── bds/
│   ├── releases/ # runtimes oficiales descargados
│   └── current   # versión activa registrada
├── cache/        # ZIP descargados
├── config/       # configuración persistente
├── instances/    # Lobby/Survival/PvP/BedWars/SkyWars y mundos
├── scripts/
└── state/
```

`/usr/local/bin/mcserver` enlaza al administrador instalado.
