# Panel web administrativo

El panel privado permite administrar Survival desde Android o cualquier navegador sin usar SFTP ni descomprimir el mundo manualmente.

## URL

Después de configurar HTTPS:

```text
https://TU_DOMINIO/admin.html
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

1. Abre `/admin.html` desde el navegador.
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
Navegador/HTTPS
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

## Dominio recomendado

Si no tienes un dominio, el instalador recomienda DuckDNS porque permite crear gratuitamente un subdominio `*.duckdns.org` que puede apuntar a la IPv4 pública de tu VPS.

Ejemplo:

```text
miservidor.duckdns.org -> 203.0.113.10
```

El instalador pide el dominio durante la primera configuración. Si el DNS todavía no apunta a la VPS, conserva el dominio pero usa temporalmente la IP.

Cuando el DNS sea correcto:

```bash
sudo mcserver network use-domain
```

## Activación en una VPS ya instalada

```bash
sudo mcserver update project
sudo mcserver web admin-token
sudo mcserver web domain TU_DOMINIO
sudo mcserver web https TU_DOMINIO TU_CORREO
```

Después abre:

```text
https://TU_DOMINIO/admin.html
```
