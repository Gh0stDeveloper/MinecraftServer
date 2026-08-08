# Importación segura del mundo Survival

## Antes de exportar desde tu dispositivo

1. Entra al mundo original y confirma que sigue mostrando que se pueden obtener logros.
2. **No actives cheats** para facilitar la exportación.
3. No cambies temporalmente a Creative.
4. Cierra Minecraft por completo antes de copiar la carpeta del mundo.
5. Conserva una copia independiente del mundo original en tu teléfono/PC.

## Qué hace el importador

`import-survival.sh` valida que existan `level.dat` y `db/`, detiene la instancia Survival, hace backup del destino existente y copia el mundo completo usando `rsync`.

No edita `level.dat`. Solo fuerza en `server.properties`:

```ini
allow-cheats=false
force-gamemode=false
gamemode=survival
online-mode=true
allow-list=true
level-name=SurvivalWorld
```

## Qué NO se debe hacer después

- No ejecutar `/changesetting allowcheats true`.
- No cambiar el mundo a Creative.
- No activar Experiments en ese mundo.
- No instalar el Behavior Pack del lobby/minijuegos dentro de `SurvivalWorld`.
- No sustituir `level.dat` por uno modificado para intentar recuperar logros.

## Allowlist

Ejemplo de `/opt/bedrock-network/instances/survival/allowlist.json`:

```json
[
  { "name": "Gamertag1", "ignoresPlayerLimit": false },
  { "name": "Gamertag2", "ignoresPlayerLimit": false }
]
```

Añade los 8 Gamertags y reinicia Survival.
