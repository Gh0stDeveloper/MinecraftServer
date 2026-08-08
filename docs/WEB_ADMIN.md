# Panel web administrativo

El panel privado está pensado para administrar Survival desde Android sin usar SFTP ni descomprimir el mundo manualmente.

## URL

Después de configurar HTTPS:

```text
https://minecraftnexora.duckdns.org/admin.html
```

La API administrativa rechaza accesos públicos por HTTP. La página pública de estado sigue funcionando normalmente.

## Crear o cambiar el token

En la VPS:

```bash
sudo mcserver web admin-token
```

El comando imprime el token una sola vez. En disco solo se guarda su SHA-256 en:

```text
/opt/bedrock-network/config/web-admin.token.sha256
```

El archivo queda `root:bedrock` con modo `0640`.

## Subir Survival

1. Abre `/admin.html` desde Android.
2. Pega el token y pulsa **Validar**.
3. Selecciona un `.zip` o `.mcworld`.
4. Pulsa **Subir e importar Survival**.
5. La página muestra progreso de subida y luego el estado de la importación.

Límite predeterminado:

```text
WEB_MAX_UPLOAD_MB=4096
```

El proxy Nginx usa el mismo límite y desactiva el buffering de request para que archivos grandes no se dupliquen innecesariamente en la caché de Nginx.

## Arquitectura de seguridad

El proceso web se ejecuta como `bedrock`, sin privilegios root. Solo puede escribir en:

```text
/opt/bedrock-network/uploads
/opt/bedrock-network/state
```

Flujo:

```text
Android/HTTPS
  -> web/server.py (bedrock)
  -> uploads/<id>.zip
  -> uploads/requests/<id>.json
  -> systemd.path
  -> bedrock-survival-import.service (root)
  -> process-web-import.sh
  -> import-survival.sh
```

El worker root:

- serializa la operación con el lock global de `mcserver`;
- comprueba ID, ruta, tamaño y SHA-256 de la subida;
- reutiliza las defensas ZIP/MCWORLD de `import-survival.sh`;
- crea el backup del mundo anterior;
- copia `level.dat` sin modificarlo;
- fuerza `SURVIVAL_ENGINE=bds`;
- mantiene `allow-cheats=false` y `force-gamemode=false`;
- inicia Survival y devuelve el resultado al panel.

El ZIP subido se elimina del staging al terminar la operación. Los backups permanecen en `/opt/bedrock-network/backups/imports/`.

## Activación en una VPS ya instalada

```bash
sudo mcserver update project
sudo mcserver web admin-token
sudo mcserver web domain minecraftnexora.duckdns.org
sudo mcserver web https minecraftnexora.duckdns.org TU_CORREO
```

Después abre:

```text
https://minecraftnexora.duckdns.org/admin.html
```
