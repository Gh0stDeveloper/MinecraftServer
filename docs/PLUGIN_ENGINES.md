# Motores y plugins

## Política de motores

- `lobby`: BDS oficial. Ejecuta el addon del hub y `/transfer`.
- `survival`: BDS oficial obligatorio. Nunca carga PowerNukkitX ni plugins.
- `pvp`, `bedwars`, `skywars`: PowerNukkitX por defecto; BDS queda como fallback.

La selección persistente vive en `/opt/bedrock-network/config/engines.env`.

## PowerNukkitX

Se mantiene como runtime versionado en:

```text
/opt/bedrock-network/pnx/releases/<version-sha>/powernukkitx-shaded.jar
/opt/bedrock-network/pnx/current -> releases/<version-sha>
```

`mcserver update pnx` descarga el snapshot oficial, calcula SHA-256, conserva releases anteriores, aplica el symlink y hace rollback si las instancias que estaban online no vuelven a iniciar.

## Catálogo de plugins

`config/plugins.json` contiene instancia, motor requerido, versión Bedrock objetivo, API PNX, repositorio/fuente, commit o versión fijada, tarea de compilación, licencia conocida y política de redistribución.

Los plugins externos no se copian al repositorio MinecraftServer. `plugin-manager.sh` los obtiene desde el upstream, hace checkout del commit exacto, compila y reemplaza el JAR únicamente después de una compilación exitosa.

## PvP

`pnx-plugins/nexora-practice` es nuestro plugin inicial para las colas Solo/Duo/Escuadra y retorno al lobby. La siguiente capa será ArenaManager: arenas registradas, spawns, kits, equipos, ronda, espectador y reset.

## BedWars / SkyWars

Los plugins externos se tratan como dependencias administradas, no como código propio. CI compila las referencias fijadas para detectar una ruptura con Java/PowerNukkitX antes de actualizar el catálogo.

Si un plugin deja de ser viable:

```bash
sudo mcserver engine set bedwars bds
```

permite volver temporalmente al framework BDS anterior mientras se cambia o adapta el plugin.
